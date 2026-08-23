"""An agent the user can ask about their own stored health data, their
PhenoAge and the simulation result they are looking at in the app — Moirai's
voice, grounded in retrieved fragments instead of a full data dump.

How a turn works (see `app/chat_rag/`):

1. Load `/me` + `/me/health-context` and compute PhenoAge fresh (cheap).
2. Split that, plus the `resultado` the app sent (spec §8 JSON, a few KB), plus
   a static knowledge base about the engine, into ~60 short chunks.
3. Retrieve the few chunks that match the question (BM25 + Spanish synonyms,
   biased by the previous user turn and by `enfoque` — where in the app the
   chat was opened from) under a ~1.600-token budget; an always-on core card
   carries the headline numbers regardless.
4. Call the model with those fragments in the system prompt — written in
   the register the person asked for in onboarding (`perfil_conocimiento`:
   plain words by default, technical only on explicit request) — and one
   tool, `buscar_mis_datos`, that runs the same retriever again when the
   first pass missed something (bounded to two rounds).
5. Return the reply, the plain-text history to send back next turn, and the
   ids/titles of the fragments used (`fuentes`), which the app shows as
   "esto es lo que leí" under the answer.

Stateless like the rest of this API's chat-shaped surface: the caller sends
the conversation back each turn; nothing is persisted server-side.
"""

from __future__ import annotations

import logging
from typing import Annotated, Any, Literal

import anthropic
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.anthropic_client import get_anthropic_client
from app.auth import CurrentUserDep
from app.chat_rag.chunks import Chunk
from app.chat_rag.documents import build_documents
from app.chat_rag.prompt import TOOL_BUSCAR, TOOL_NAME, build_system, render_tool_result
from app.chat_rag.retriever import buscar, retrieve
from app.config import Settings, get_settings
from app.db import get_db
from app.health_metrics import phenoage
from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.phenoage import PhenoAgeResult
from app.models import HealthContext, Profile
from app.routers.health_context import PerfilConocimiento
from app.routers.profile import biological_inputs

log = logging.getLogger("app")

router = APIRouter(prefix="/me/health-context", tags=["health-chat"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]
SettingsDep = Annotated[Settings, Depends(get_settings)]

MAX_TOKENS = 1024
#: Keeps one request from ballooning into an unbounded, unbounded-cost prompt —
#: same spirit as the Monte Carlo trajectory/year caps.
MAX_HISTORY_TURNS = 40
MAX_MESSAGE_LENGTH = 4000
#: Retrieval budgets (tokens, conservatively estimated). The system rules are
#: ~700 tokens and the core card ~150, so a turn lands around 2.500 input
#: tokens instead of the ~8–10k a full dump of data + result + knowledge costs.
PRESUPUESTO_FRAGMENTOS = 1600
#: How many times the model may call `buscar_mis_datos` in one turn before
#: it has to answer with what it has.
MAX_RONDAS_HERRAMIENTA = 2


async def _load_context(
    session: AsyncSession, user_id
) -> tuple[dict, dict, PhenoAgeResult | None]:
    """(perfil, health-context, PhenoAge-or-None): the same data sources
    `/phenoage` uses, gathered without its 422-on-missing behavior — chat
    degrades gracefully instead of failing."""
    edad, sexo = await biological_inputs(session, user_id)
    profile = await session.get(Profile, user_id)
    imc = None
    if profile is not None and profile.height_cm and profile.weight_kg:
        m = float(profile.height_cm) / 100
        imc = round(float(profile.weight_kg) / (m * m), 1)
    perfil = {
        "nombre": profile.full_name if profile else None,
        "edad": edad,
        "sexo_biologico": sexo,
        "estatura_cm": float(profile.height_cm) if profile and profile.height_cm else None,
        "peso_kg": float(profile.weight_kg) if profile and profile.weight_kg else None,
        "imc": imc,
    }

    row = await session.get(HealthContext, user_id)
    context = {
        "demografia": (row.demografia if row else None) or {},
        "biomarcadores": (row.biomarcadores if row else None) or [],
        "habitos": (row.habitos if row else None) or {},
        "historia_familiar": (row.historia_familiar if row else None) or [],
        "objetivos_usuario": (row.objetivos_usuario if row else None) or [],
        "datos_faltantes": (row.datos_faltantes if row else None) or [],
        "notas_incertidumbre": (row.notas_incertidumbre if row else None),
    }

    if edad is None or sexo is None:
        return perfil, context, None

    biomarcadores = {
        b["nombre"]: b["valor"]
        for b in context["biomarcadores"]
        if b["nombre"] in PHENOAGE_BIOMARKERS
    }
    return perfil, context, phenoage.compute(biomarcadores, edad, sexo)


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str


class ResultadoIn(BaseModel):
    """The simulation result as the app holds it (`SimulacionResultado
    .toChatJson()`, spec §8 + the app's extensions). Deliberately tolerant —
    `extra="ignore"`, every field optional — because the app assembles part of
    it locally and its shape moves faster than this API: a field this model
    does not know is dropped, never a 422. `muestra_trayectorias` (the 60
    illustrative lines) must not be sent; it is the bulk of the payload and
    the chat never reads it."""

    model_config = ConfigDict(extra="ignore")

    id: str | None = Field(default=None, max_length=80)
    creado_en: str | None = Field(default=None, max_length=40)
    edad_cronologica: float | None = None
    edad_biologica_hoy: float | None = None
    trayectoria_baseline: dict[str, Any] | None = None
    mejor_decision: dict[str, Any] | None = None
    veredicto_gemelo: str | None = Field(default=None, max_length=600)
    porque: str | None = Field(default=None, max_length=1200)
    shap_top_drivers: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
    comparacion_poblacional: dict[str, Any] | None = None
    incertidumbre: str | None = Field(default=None, max_length=1200)
    descargo: str | None = Field(default=None, max_length=400)
    escenarios: list[dict[str, Any]] = Field(default_factory=list, max_length=24)
    intervenciones_catalogo: list[dict[str, Any]] = Field(default_factory=list, max_length=24)
    biomarcadores_usados: list[dict[str, Any]] = Field(default_factory=list, max_length=24)


class ChatIn(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "message": "¿Por qué el ejercicio es mi primera palanca?",
                "history": [],
                "enfoque": "escenario:0",
                "perfil_conocimiento": "general",
                "resultado": {
                    "id": "sim_abc",
                    "edad_cronologica": 34,
                    "edad_biologica_hoy": 37.8,
                    "trayectoria_baseline": {"anios": [0, 10], "mediana": [37.8, 47.2], "p10": [37.8, 43.1], "p90": [37.8, 51.4]},
                    "escenarios": [
                        {"intervenciones": ["ejercicio_aerobico"], "etiqueta": "Ejercicio aeróbico regular",
                         "anios_ganados": 2.4, "rango": [1.1, 3.7], "esfuerzo": 3, "ratio_impacto_esfuerzo": 0.8,
                         "pct_futuros_que_mejoran": 79,
                         "curva": {"anios": [0, 10], "mediana": [37.8, 44.8], "p10": [37.8, 41.0], "p90": [37.8, 48.6]}}
                    ],
                },
            }
        },
    )

    message: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)
    #: The conversation so far, oldest first. Send back what the previous
    #: response returned in `history` to continue the same conversation.
    history: list[ChatMessage] = Field(default_factory=list, max_length=MAX_HISTORY_TURNS)
    #: The simulation the user is looking at, so the agent can answer about
    #: *those* numbers. Optional: without it the chat covers stored data,
    #: PhenoAge and how the engine works.
    resultado: ResultadoIn | None = None
    #: Where in the app the chat was opened from — biases retrieval towards
    #: that topic. Free text, but the app uses: `escenario:<índice>` (a lever's
    #: detail), `porque`, `incertidumbre`, `biomarcador:<nombre>`, `medir`,
    #: `poblacion`.
    enfoque: str | None = Field(default=None, max_length=80)
    #: How technical the reply may be (`general` | `curioso` | `profesional`).
    #: Overrides `demografia.perfil_conocimiento` stored in the health
    #: context for this turn — the app sends what it has locally so the
    #: register is right even when the onboarding sync hasn't landed. Omit to
    #: use the stored value; neither set → `general` (plain words).
    perfil_conocimiento: PerfilConocimiento | None = None


class Fuente(BaseModel):
    id: str
    titulo: str
    #: "usuario" (stored data) | "resultado" (the simulation sent) |
    #: "conocimiento" (how the engine works).
    grupo: str


class ChatOut(BaseModel):
    reply: str
    #: `history` + this turn's user message + the reply — pass this straight
    #: back as `history` on the next call.
    history: list[ChatMessage]
    #: The fragments the answer was grounded in (initial retrieval + anything
    #: the agent fetched with its tool), in the order they were shown. Empty
    #: only when nothing matched and nothing was fetched.
    fuentes: list[Fuente]


def _fuentes(chunks: list[Chunk]) -> list[Fuente]:
    return [Fuente(id=c.id, titulo=c.titulo, grupo=c.grupo) for c in chunks]


@router.post(
    "/chat",
    summary="Ask Moirai about the signed-in user's data, PhenoAge and simulation result",
    responses={
        502: {"description": "The agent is unreachable or misconfigured"},
        503: {"description": "ANTHROPIC_API_KEY is not set on this deployment"},
    },
)
async def chat(
    body: ChatIn, user: CurrentUserDep, session: SessionDep, settings: SettingsDep
) -> ChatOut:
    perfil, context, pheno = await _load_context(session, user.id)
    resultado = body.resultado.model_dump() if body.resultado is not None else None
    core, chunks = build_documents(perfil, context, pheno, resultado)

    previas = [m.content for m in body.history if m.role == "user"][-2:]
    fragmentos = retrieve(
        chunks,
        body.message,
        contexto_previo=previas,
        enfoque=body.enfoque,
        presupuesto_tokens=PRESUPUESTO_FRAGMENTOS,
    )
    mostrados = {c.id for c in fragmentos}
    usados: list[Chunk] = list(fragmentos)

    registro = body.perfil_conocimiento or context["demografia"].get("perfil_conocimiento")
    system_prompt = build_system(
        perfil.get("nombre") or user.email, core, fragmentos, perfil=registro
    )
    messages: list[dict] = [{"role": m.role, "content": m.content} for m in body.history]
    messages.append({"role": "user", "content": body.message})

    try:
        client = get_anthropic_client()
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    rondas = 0
    try:
        while True:
            # On the last allowed round the model must answer with what it
            # has — otherwise a turn could end on a tool call with no text.
            ultima = rondas >= MAX_RONDAS_HERRAMIENTA
            response = await client.messages.create(
                model=settings.chat_model,
                max_tokens=MAX_TOKENS,
                system=system_prompt,
                tools=[TOOL_BUSCAR],
                tool_choice={"type": "none"} if ultima else {"type": "auto"},
                messages=messages,
            )
            if response.stop_reason != "tool_use":
                break
            rondas += 1
            resultados_tool: list[dict] = []
            for block in response.content:
                if block.type != "tool_use":
                    continue
                consulta = str((block.input or {}).get("consulta", "")) if block.name == TOOL_NAME else ""
                extra = buscar(chunks, consulta, excluir=mostrados) if consulta else []
                mostrados.update(c.id for c in extra)
                usados.extend(extra)
                resultados_tool.append(
                    {"type": "tool_result", "tool_use_id": block.id, "content": render_tool_result(extra)}
                )
            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": resultados_tool})
    except anthropic.AuthenticationError as exc:
        log.error("health_chat.auth_error %s", exc)
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, detail="el agente no está configurado correctamente"
        ) from exc
    except anthropic.RateLimitError as exc:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="demasiadas solicitudes al agente, intenta de nuevo en un momento",
        ) from exc
    except anthropic.APIConnectionError as exc:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="no se pudo contactar al agente"
        ) from exc
    except anthropic.APIStatusError as exc:
        log.error("health_chat.api_error status=%s body=%s", exc.status_code, exc.message)
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, detail="el agente no respondió correctamente"
        ) from exc

    reply = "".join(block.text for block in response.content if block.type == "text").strip()
    if response.stop_reason == "refusal" or not reply:
        reply = (
            "Eso no lo puedo responder desde aquí. Puedo contarte de tus datos, tu edad biológica, "
            "tus palancas y cómo funciona la simulación; para decisiones clínicas, habla con un profesional."
        )

    usage = getattr(response, "usage", None)
    log.info(
        "health_chat.turn user_id=%s fragmentos=%d rondas=%d input_tokens=%s output_tokens=%s",
        user.id, len(usados), rondas,
        getattr(usage, "input_tokens", "?"), getattr(usage, "output_tokens", "?"),
    )

    return ChatOut(
        reply=reply,
        history=[*body.history, ChatMessage(role="user", content=body.message),
                 ChatMessage(role="assistant", content=reply)],
        fuentes=_fuentes(usados),
    )
