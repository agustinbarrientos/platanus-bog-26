"""Upload one or more lab-exam documents (PDF or photo — pages of the same
exam, or several separate exams/medical reports from the same visit), extract
biomarker readings from them with Claude, and save whatever passes validation
straight into `/me/health-context` — no review step. The only guardrail
between a bad extraction and storage is the same `Biomarcador` unit/range
validator every other write to this resource already goes through.

All uploaded documents go to Claude in a single request (multiple content
blocks, one call) rather than one call per file: it's cheaper, and it lets
the model reconcile a biomarker that shows up on more than one document
instead of each document being read blind to the others.
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

#: A handful of documents from one visit (front/back of a page, a few
#: separate panels), not a bulk-upload feature — keeps one request bounded
#: and keeps the total comfortably under Claude's own per-request ceiling.
MAX_FILES_PER_REQUEST = 5
#: Checked against the combined *raw* bytes of all files, before base64 —
#: base64 inflates size by ~33%, and the Messages API caps a request at
#: 32MB total; staying under this leaves real headroom instead of finding
#: the provider's limit by hitting it.
MAX_TOTAL_MB = 20


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
    earlier one recorded."""
    if not hallazgos:
        return existente
    nuevas = "; ".join(hallazgos)
    return f"{existente}; {nuevas}" if existente else nuevas


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
    summary="Upload one or more lab exams (PDF or photo); extract and save biomarkers found in them",
    responses={
        422: {"description": "Unsupported file type, or no files sent"},
        413: {"description": "A file, or the combined upload, is too large"},
        502: {"description": "The agent is unreachable or misconfigured"},
        503: {"description": "ANTHROPIC_API_KEY is not set on this deployment"},
    },
)
async def extract_biomarkers(
    user: CurrentUserDep,
    session: SessionDep,
    settings: SettingsDep,
    files: Annotated[list[UploadFile], File()],
) -> BiomarkerExtractionOut:
    if not files:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="no se envió ningún archivo")
    if len(files) > MAX_FILES_PER_REQUEST:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"máximo {MAX_FILES_PER_REQUEST} archivos por solicitud, se enviaron {len(files)}",
        )

    invalidos = [f.filename for f in files if f.content_type not in ACCEPTED_CONTENT_TYPES]
    if invalidos:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"tipo de archivo no soportado (use PDF o imagen png/jpg/webp): {invalidos}",
        )

    max_bytes_por_archivo = settings.max_upload_mb * 1024 * 1024
    max_bytes_total = MAX_TOTAL_MB * 1024 * 1024
    content_blocks = []
    total_bytes = 0
    for f in files:
        data = await f.read(max_bytes_por_archivo + 1)
        if len(data) > max_bytes_por_archivo:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"{f.filename} supera el máximo de {settings.max_upload_mb}MB por archivo",
            )
        total_bytes += len(data)
        if total_bytes > max_bytes_total:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"el conjunto de archivos supera el máximo combinado de {MAX_TOTAL_MB}MB",
            )
        data_b64 = base64.standard_b64encode(data).decode("ascii")
        content_blocks.append(build_content_block(f.content_type, data_b64))

    try:
        client = get_anthropic_client()
    except RuntimeError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    try:
        response = await client.messages.parse(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            messages=[
                {
                    "role": "user",
                    "content": [*content_blocks, {"type": "text", "text": build_prompt(len(files))}],
                }
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

    # With more than one document, Claude can still occasionally report the
    # same biomarker twice despite being told to reconcile them into one
    # reading — collapse to the last one here too, so `guardados` in the
    # response always matches what `_merge_biomarcadores` actually persists
    # (same last-one-wins rule) instead of showing an entry that didn't win.
    guardados = list({b.nombre: b for b in guardados}.values())

    row = await get_or_create_health_context(session, user.id)
    row.biomarcadores = _merge_biomarcadores(row.biomarcadores or [], guardados)
    row.notas_incertidumbre = _merge_notas(row.notas_incertidumbre, result.hallazgos)
    await session.flush()
    await session.refresh(row)

    log.info(
        "lab_upload.extracted user_id=%s archivos=%d guardados=%d advertencias=%d hallazgos=%d",
        user.id, len(files), len(guardados), len(advertencias), len(result.hallazgos),
    )

    return BiomarkerExtractionOut(
        guardados=guardados,
        biomarcadores=[Biomarcador.model_validate(b) for b in row.biomarcadores],
        advertencias=advertencias,
        hallazgos=result.hallazgos,
        notas_incertidumbre=row.notas_incertidumbre,
        notas=result.notas,
    )
