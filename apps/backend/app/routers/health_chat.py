"""An agent the user can ask to interpret their own stored health data —
biomarkers, habits, family history, and PhenoAge if `date_of_birth`/
`sex_at_birth` are on the profile. Every reply is grounded in exactly what
`/me/health-context` and `/me` hold for that user, recomputed fresh on each
turn; the agent gets no other data source and no tools of its own.

Stateless like the rest of this API's chat-shaped surface: the caller sends
the full conversation history each turn (`ConversationManager` pattern) and
gets it back with the new turn appended — nothing is persisted server-side.
"""

from __future__ import annotations

import json
import logging
from typing import Annotated, Literal

import anthropic
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.anthropic_client import get_anthropic_client
from app.auth import CurrentUserDep
from app.db import get_db
from app.health_metrics import phenoage
from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.phenoage import PhenoAgeResult
from app.models import HealthContext
from app.routers.profile import biological_inputs

log = logging.getLogger("app")

router = APIRouter(prefix="/me/health-context", tags=["health-chat"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]

#: Cheapest current model ($1.00/$5.00 per 1M tokens) — this is grounded Q&A
#: over data already computed for it, not open-ended reasoning, so it doesn't
#: need a bigger model.
MODEL = "claude-haiku-4-5"
MAX_TOKENS = 1024
#: Keeps one request from ballooning into an unbounded, unbounded-cost prompt —
#: same spirit as the Monte Carlo trajectory/year caps.
MAX_HISTORY_TURNS = 40
MAX_MESSAGE_LENGTH = 4000


async def _load_context(
    session: AsyncSession, user_id
) -> tuple[dict, PhenoAgeResult | None]:
    """Everything in `/me/health-context`, plus the profile's age/sex and
    PhenoAge computed fresh if there's enough on file to compute it — the
    same data sources `/phenoage` uses, gathered here without its
    422-on-missing behavior, since chat should degrade gracefully instead of
    failing."""
    edad, sexo = await biological_inputs(session, user_id)

    row = await session.get(HealthContext, user_id)
    context = {
        "perfil": {"edad": edad, "sexo_biologico": sexo},
        "demografia": (row.demografia if row else None) or {},
        "biomarcadores": (row.biomarcadores if row else None) or [],
        "habitos": (row.habitos if row else None) or {},
        "historia_familiar": (row.historia_familiar if row else None) or [],
        "objetivos_usuario": (row.objetivos_usuario if row else None) or [],
        "datos_faltantes": (row.datos_faltantes if row else None) or [],
        "notas_incertidumbre": (row.notas_incertidumbre if row else None),
    }

    if edad is None or sexo is None:
        return context, None

    biomarcadores = {
        b["nombre"]: b["valor"]
        for b in context["biomarcadores"]
        if b["nombre"] in PHENOAGE_BIOMARKERS
    }
    result = phenoage.compute(biomarcadores, edad, sexo)
    return context, result


def _system_prompt(email: str, context: dict, pheno: PhenoAgeResult | None) -> str:
    datos_json = json.dumps(context, ensure_ascii=False, indent=2)
    if pheno is None:
        phenoage_json = '"no disponible — falta demografia.edad en el perfil"'
    else:
        phenoage_json = json.dumps(
            {
                "edad_cronologica": pheno.edad_cronologica,
                "edad_biologica": round(pheno.edad_biologica, 2),
                "aceleracion": round(pheno.aceleracion, 2),
                "campos_inferidos": pheno.campos_inferidos,
            },
            ensure_ascii=False,
            indent=2,
        )

    return f"""Eres un asistente que ayuda a {email} a entender sus propios datos de \
salud y su resultado del reloj de edad biológica PhenoAge.

Reglas:
- Respalda cada respuesta únicamente en los datos entregados abajo. No inventes \
valores ni asumas mediciones que no están presentes.
- Cuando un dato aparezca en "campos_inferidos" (dentro del resultado PhenoAge) o en \
"datos_faltantes", acláralo explícitamente: fue estimado a partir de medianas \
poblacionales, no medido en esta persona.
- No eres un profesional de la salud: no des diagnósticos ni indicaciones de \
tratamiento. Para decisiones clínicas, sugiere consultar a un médico.
- Si el usuario pregunta por algo que no está en los datos de abajo (por ejemplo, \
un biomarcador que nunca registró), dilo directamente en vez de adivinar.
- Sé claro y breve. Responde en español, salvo que el usuario escriba en otro idioma.

Datos de salud almacenados del usuario (JSON, desde /me/health-context):
{datos_json}

Resultado PhenoAge (Levine et al. 2018), calculado en este momento a partir de esos datos:
{phenoage_json}
"""


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str


class ChatIn(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {"message": "¿Qué significa que mi PhenoAge sea más bajo que mi edad?"}
        },
    )

    message: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)
    #: The conversation so far, oldest first. Send back what the previous
    #: response returned in `history` to continue the same conversation.
    history: list[ChatMessage] = Field(default_factory=list, max_length=MAX_HISTORY_TURNS)


class ChatOut(BaseModel):
    reply: str
    #: `history` + this turn's user message + the reply — pass this straight
    #: back as `history` on the next call.
    history: list[ChatMessage]


@router.post(
    "/chat",
    summary="Ask an agent to interpret the signed-in user's stored health data",
    responses={
        502: {"description": "The agent is unreachable or misconfigured"},
        503: {"description": "ANTHROPIC_API_KEY is not set on this deployment"},
    },
)
async def chat(body: ChatIn, user: CurrentUserDep, session: SessionDep) -> ChatOut:
    context, pheno = await _load_context(session, user.id)
    system_prompt = _system_prompt(user.email, context, pheno)

    messages = [{"role": m.role, "content": m.content} for m in body.history]
    messages.append({"role": "user", "content": body.message})

    try:
        client = get_anthropic_client()
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    try:
        response = await client.messages.create(
            model=MODEL, max_tokens=MAX_TOKENS, system=system_prompt, messages=messages
        )
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

    reply = next((block.text for block in response.content if block.type == "text"), "")

    return ChatOut(
        reply=reply,
        history=[*body.history, ChatMessage(role="user", content=body.message),
                  ChatMessage(role="assistant", content=reply)],
    )
