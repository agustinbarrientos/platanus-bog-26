"""`POST /me/health-context/reporte` (JSON) y `POST /me/health-context/reporte.pdf`
(PDF descargable): el reporte de salud orientativo de
docs/MOIRAI_REPORTE_SPEC.md, construido desde el MOTOR REAL sobre lo que
`/me` + `/me/health-context` ya guardan. Como `/phenoage` y `/montecarlo`, no
recibe un cuerpo que describa a la persona — solo (opcionalmente) el tamaño
de la simulación y la semilla, para que el reporte reproduzca exactamente lo
que la app mostró (la app usa los defaults, así que sin cuerpo coincide).

Nada se guarda: el reporte se genera en cada llamada y se devuelve; es
"se lee una vez, no se guarda" (spec §6). El PDF nunca toca disco.
"""

from __future__ import annotations

from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUserDep
from app.db import get_db
from app.health_metrics import montecarlo
from app.models import HealthContext, Profile
from app.report.builder import construir_reporte
from app.report.pdf import render_pdf
from app.report.schema import ReporteOut
from app.routers.biological_age import ENGINE_VERSION
from app.routers.profile import biological_inputs

router = APIRouter(prefix="/me/health-context", tags=["report"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]


class ReporteIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    n_trayectorias: int = Field(
        default=montecarlo.DEFAULT_TRAYECTORIAS, ge=100, le=montecarlo.MAX_TRAYECTORIAS
    )
    anios: int = Field(default=montecarlo.DEFAULT_ANIOS, ge=1, le=montecarlo.MAX_ANIOS)
    #: Omitida → la fija del motor (la misma que usa la app): mismo abanico.
    semilla: int | None = None
    #: Solo para `/reporte.pdf`: `true` = resumen de 1 página para la consulta.
    resumen: bool = False


async def _armar(body: ReporteIn, user_id, session: AsyncSession) -> dict:
    edad, sexo = await biological_inputs(session, user_id)
    if edad is None or sexo is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="falta date_of_birth y/o sex_at_birth — PATCH /me antes de generar el reporte",
        )
    perfil = await session.get(Profile, user_id)
    row = await session.get(HealthContext, user_id)
    demografia = dict((row.demografia if row else None) or {})
    return construir_reporte(
        nombre=(perfil.full_name if perfil else None),
        edad=edad,
        sexo=sexo,
        biomarcadores_guardados=list((row.biomarcadores if row else None) or []),
        habitos=dict((row.habitos if row else None) or {}),
        ancestria=demografia.get("ancestria_reportada"),
        n_trayectorias=body.n_trayectorias,
        anios=body.anios,
        semilla=body.semilla,
        version_motor=ENGINE_VERSION,
    )


@router.post(
    "/reporte",
    summary="Reporte de salud orientativo (JSON): foto de hoy, ejes, futuros, qué hacer, con quién consultar, qué medir",
    responses={422: {"description": "date_of_birth/sex_at_birth is not on file"}},
)
async def reporte_json(body: ReporteIn | None = None, *, user: CurrentUserDep, session: SessionDep) -> ReporteOut:
    rep = await _armar(body or ReporteIn(), user.id, session)
    return ReporteOut.model_validate(rep)


@router.post(
    "/reporte.pdf",
    summary="El mismo reporte como PDF descargable (o el resumen de 1 página con `resumen: true`)",
    response_class=Response,
    responses={
        200: {"content": {"application/pdf": {}}, "description": "El PDF, `Content-Disposition: attachment`"},
        422: {"description": "date_of_birth/sex_at_birth is not on file"},
    },
)
async def reporte_pdf(body: ReporteIn | None = None, *, user: CurrentUserDep, session: SessionDep) -> Response:
    body = body or ReporteIn()
    rep = await _armar(body, user.id, session)
    data = render_pdf(rep, resumen=body.resumen)
    nombre = (rep["persona"].get("nombre") or "moirai").strip().replace(" ", "-")
    fecha = rep["meta"]["generado_en"][:10]
    archivo = f"moirai-{'resumen' if body.resumen else 'reporte'}-{nombre}-{fecha}.pdf"
    return Response(
        content=data,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename=\"{archivo.encode('ascii', 'ignore').decode()}\"; filename*=UTF-8''{quote(archivo)}",
            "Cache-Control": "no-store",
            "X-Moirai-Reporte-Id": rep["meta"]["id"],
        },
    )
