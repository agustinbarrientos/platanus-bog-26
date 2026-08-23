"""Upload a lab-exam document (PDF or photo), extract biomarker readings from
it with Claude, and save whatever passes validation straight into
`/me/health-context` — no review step. The only guardrail between a bad
extraction and storage is the same `Biomarcador` unit/range validator every
other write to this resource already goes through.
"""

from __future__ import annotations

import base64
import logging
from typing import Annotated

import anthropic
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.ext.asyncio import AsyncSession

from app.anthropic_client import get_anthropic_client
from app.auth import CurrentUserDep
from app.config import Settings, get_settings
from app.db import get_db
from app.lab_extraction import (
    ACCEPTED_CONTENT_TYPES,
    ExtractionResult,
    ExtractionWarning,
    build_content_block,
    build_prompt,
    convert_and_validate,
)
from app.routers.health_context import Biomarcador, get_or_create_health_context

log = logging.getLogger("app")

router = APIRouter(prefix="/me/health-context", tags=["lab-upload"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]
SettingsDep = Annotated[Settings, Depends(get_settings)]

#: Same model as the chat agent — reads-off-a-document is a bounded,
#: schema-constrained extraction, not open-ended reasoning, and this project
#: is optimizing for cost over accuracy by explicit choice.
MODEL = "claude-haiku-4-5"
MAX_TOKENS = 2048


def _merge_biomarcadores(existing: list[dict], nuevas: list[Biomarcador]) -> list[dict]:
    """Upsert by `nombre` — unlike `PATCH /me/health-context`, which replaces
    the array wholesale, an extraction only touches the biomarkers it found
    and leaves everything else in storage alone."""
    por_nombre = {b["nombre"]: b for b in existing}
    for b in nuevas:
        por_nombre[b.nombre] = b.model_dump(mode="json")
    return list(por_nombre.values())


def _merge_notas(existente: str | None, hallazgos: list[str]) -> str | None:
    """Appends whatever non-biomarker findings this extraction turned up to
    the existing free-text notes — never overwrites, since a second upload
    (or a manual `PATCH .../notas_incertidumbre`) shouldn't erase what an
    earlier one recorded. Skips any finding already present verbatim, so
    re-uploading the same document doesn't duplicate it into the notes
    forever."""
    ya_presentes = set(existente.split("; ")) if existente else set()
    nuevas = [h for h in hallazgos if h not in ya_presentes]
    if not nuevas:
        return existente
    agregado = "; ".join(nuevas)
    return f"{existente}; {agregado}" if existente else agregado


class BiomarkerExtractionOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "guardados": [
                    {"nombre": "glucosa", "valor": 92.0, "unidad": "mg/dL", "fuente": "documento"}
                ],
                "biomarcadores": [
                    {"nombre": "glucosa", "valor": 92.0, "unidad": "mg/dL", "fuente": "documento"},
                    {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"},
                ],
                "advertencias": [
                    {
                        "nombre": "hs_CRP",
                        "valor_reportado": 21.0,
                        "unidad_reportada": "mg/L",
                        "razon": "hs_CRP=21.0 fuera de rango plausible [0.01, 200.0] mg/L",
                    }
                ],
                "hallazgos": ["Médico recomienda control de presión arterial en 3 meses"],
                "notas_incertidumbre": "Médico recomienda control de presión arterial en 3 meses",
                "notas": None,
            }
        }
    )

    #: Extracted, validated, and just written this call.
    guardados: list[Biomarcador]
    #: The full biomarcadores list now in storage, after the merge.
    biomarcadores: list[Biomarcador]
    #: Readings Claude found but that failed unit/range validation — not saved.
    advertencias: list[ExtractionWarning]
    #: Non-biomarker findings from this extraction (a diagnosis, a doctor's
    #: recommendation, a mentioned allergy or family history) — just what
    #: this call added, already folded into `notas_incertidumbre` below.
    hallazgos: list[str]
    #: The full accumulated free-text notes now in storage, after this
    #: extraction's `hallazgos` (if any) were appended.
    notas_incertidumbre: str | None
    notas: str | None


@router.post(
    "/biomarkers/extract",
    summary="Upload a lab exam (PDF or photo); extract and save biomarkers found in it",
    responses={
        422: {"description": "Unsupported file type"},
        413: {"description": "File too large"},
        502: {"description": "The agent is unreachable or misconfigured"},
        503: {"description": "ANTHROPIC_API_KEY is not set on this deployment"},
    },
)
async def extract_biomarkers(
    user: CurrentUserDep,
    session: SessionDep,
    settings: SettingsDep,
    file: Annotated[UploadFile, File()],
) -> BiomarkerExtractionOut:
    if file.content_type not in ACCEPTED_CONTENT_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="tipo de archivo no soportado, use PDF o imagen (png/jpg/webp)",
        )

    max_bytes = settings.max_upload_mb * 1024 * 1024
    data = await file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"el archivo supera el máximo de {settings.max_upload_mb}MB",
        )

    data_b64 = base64.standard_b64encode(data).decode("ascii")
    content_block = build_content_block(file.content_type, data_b64)

    try:
        client = get_anthropic_client()
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    try:
        response = await client.messages.parse(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            messages=[
                {"role": "user", "content": [content_block, {"type": "text", "text": build_prompt()}]}
            ],
            output_format=ExtractionResult,
        )
    except anthropic.AuthenticationError as exc:
        log.error("lab_upload.auth_error %s", exc)
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
        log.error("lab_upload.api_error status=%s body=%s", exc.status_code, exc.message)
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, detail="el agente no respondió correctamente"
        ) from exc

    result = response.parsed_output

    guardados: list[Biomarcador] = []
    advertencias: list[ExtractionWarning] = []
    for lectura in result.lecturas:
        biomarcador, warning = convert_and_validate(lectura)
        if biomarcador is not None:
            guardados.append(biomarcador)
        else:
            assert warning is not None
            advertencias.append(warning)

    row = await get_or_create_health_context(session, user.id)
    row.biomarcadores = _merge_biomarcadores(row.biomarcadores or [], guardados)
    row.notas_incertidumbre = _merge_notas(row.notas_incertidumbre, result.hallazgos)
    await session.flush()
    await session.refresh(row)

    log.info(
        "lab_upload.extracted user_id=%s guardados=%d advertencias=%d hallazgos=%d",
        user.id, len(guardados), len(advertencias), len(result.hallazgos),
    )

    return BiomarkerExtractionOut(
        guardados=guardados,
        biomarcadores=[Biomarcador.model_validate(b) for b in row.biomarcadores],
        advertencias=advertencias,
        hallazgos=result.hallazgos,
        notas_incertidumbre=row.notas_incertidumbre,
        notas=result.notas,
    )
