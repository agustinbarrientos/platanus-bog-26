"""Two compute endpoints on top of the data `/me/health-context` stores:
PhenoAge right now, and a Monte Carlo projection of where PhenoAge lands in
`anios` years under each intervention scenario. Both are pure functions of
what's already saved — neither endpoint takes a body describing the person,
only (for the simulation) which scenarios to run and how big to make it.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUserDep
from app.db import get_db
from app.health_metrics import montecarlo, phenoage
from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import SCENARIOS
from app.models import HealthContext
from app.routers.profile import biological_inputs

router = APIRouter(prefix="/me/health-context", tags=["biological-age"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]


async def _read_inputs(
    session: AsyncSession, user_id
) -> tuple[float, str | None, dict[str, float]]:
    """Chronological age (from the profile) and whichever PhenoAge biomarkers
    are on file — everything both compute endpoints need."""
    edad, sexo = await biological_inputs(session, user_id)
    if edad is None or sexo is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="falta date_of_birth y/o sex_at_birth — PATCH /me antes de calcular",
        )

    row = await session.get(HealthContext, user_id)
    biomarcadores_guardados = (row.biomarcadores if row else None) or []
    biomarcadores = {
        b["nombre"]: b["valor"]
        for b in biomarcadores_guardados
        if b["nombre"] in PHENOAGE_BIOMARKERS
    }
    return edad, sexo, biomarcadores


class PhenoAgeOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "edad_cronologica": 52,
                "edad_biologica": 58.3,
                "aceleracion": 6.3,
                "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
                "valores_usados": {
                    "hs_CRP": 2.1, "glucosa": 92, "albumina": 4.4, "creatinina": 0.8,
                    "fosfatasa_alcalina": 72, "linfocitos_pct": 30, "vcm": 91, "rdw": 13.3,
                    "leucocitos": 6.7,
                },
            }
        }
    )

    edad_cronologica: float
    edad_biologica: float
    #: edad_biologica - edad_cronologica. Positive means the clock reads
    #: older than the calendar; negative means younger.
    aceleracion: float
    campos_inferidos: list[str]
    valores_usados: dict[str, float]


@router.post("/phenoage", summary="PhenoAge (Levine et al. 2018) from the stored health context")
async def compute_phenoage(user: CurrentUserDep, session: SessionDep) -> PhenoAgeOut:
    edad, sexo, biomarcadores = await _read_inputs(session, user.id)
    result = phenoage.compute(biomarcadores, edad, sexo)
    return PhenoAgeOut(
        edad_cronologica=result.edad_cronologica,
        edad_biologica=round(result.edad_biologica, 2),
        aceleracion=round(result.aceleracion, 2),
        campos_inferidos=result.campos_inferidos,
        valores_usados=result.valores_usados,
    )


class MontecarloIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    #: Defaults to every scenario in `SCENARIOS` if omitted.
    escenarios: list[str] | None = None
    n_trayectorias: int = Field(
        default=montecarlo.DEFAULT_TRAYECTORIAS, ge=100, le=montecarlo.MAX_TRAYECTORIAS
    )
    anios: int = Field(default=montecarlo.DEFAULT_ANIOS, ge=1, le=montecarlo.MAX_ANIOS)
    #: 1.0 = the scenario's modeled effect applies in full every year; 0.0
    #: collapses every requested scenario to the `ninguna` baseline (natural
    #: drift + noise only, no intervention benefit) — for "what if I only
    #: keep this up part of the time" rather than assuming perfect follow-through.
    adherencia: float = Field(default=1.0, ge=0.0, le=1.0)
    #: The lower/upper band around the median — default 10/90 matches the
    #: original behavior. Widen (e.g. 5/95) for a more pessimistic/optimistic
    #: band, narrow (e.g. 25/75) for a tighter one. Field names in the
    #: response stay `edad_biologica_p10`/`_p90` regardless, for backward
    #: compatibility — `percentil_inferior`/`percentil_superior` in the
    #: response say what they actually represent.
    percentil_inferior: int = Field(default=montecarlo.DEFAULT_PERCENTIL_INFERIOR, ge=1, le=49)
    percentil_superior: int = Field(default=montecarlo.DEFAULT_PERCENTIL_SUPERIOR, ge=51, le=99)
    #: Fixing this makes the run reproducible — same inputs + same seed =
    #: identical output, useful for "replay this exact simulation" or a
    #: before/after comparison. Omit to get fresh randomness each call; the
    #: seed actually used (generated if you didn't pass one) always comes
    #: back in the response so you can replay it later even if you didn't set it.
    seed: int | None = None
    #: Off by default (keeps the response the same size as before this
    #: field existed). When on, each scenario also returns its year-by-year
    #: percentile band, not just the final year — the actual "fan of
    #: futures" over time, not just its endpoint.
    incluir_trayectoria: bool = False


class TrayectoriaPuntoOut(BaseModel):
    anio: int
    edad_biologica_p_inferior: float
    edad_biologica_mediana: float
    edad_biologica_p_superior: float


class EscenarioOut(BaseModel):
    escenario: str
    nombre: str
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float
    #: Only populated when the request set `incluir_trayectoria: true`.
    trayectoria: list[TrayectoriaPuntoOut] | None = None


class MontecarloOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "edad_cronologica": 52,
                "horizonte_anios": 10,
                "trayectorias_por_escenario": 5000,
                "adherencia": 1.0,
                "percentil_inferior": 10,
                "percentil_superior": 90,
                "seed": 7823914502,
                "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
                "escenarios": [
                    {
                        "escenario": "ninguna",
                        "nombre": "Sin intervención (línea base)",
                        "edad_biologica_p10": 60.1,
                        "edad_biologica_mediana": 63.8,
                        "edad_biologica_p90": 67.2,
                        "trayectoria": None,
                    },
                    {
                        "escenario": "combinada",
                        "nombre": "Ejercicio + dieta mediterránea + cesación de tabaco",
                        "edad_biologica_p10": 53.4,
                        "edad_biologica_mediana": 56.9,
                        "edad_biologica_p90": 60.2,
                    },
                ],
            }
        }
    )

    edad_cronologica: float
    horizonte_anios: int
    trayectorias_por_escenario: int
    #: Echoed back so the caller knows what the percentile band and
    #: adherence scaling actually were, even if they didn't set them.
    adherencia: float
    percentil_inferior: int
    percentil_superior: int
    #: The seed actually used — always present, even if the request didn't
    #: pin one, so this exact run can be replayed later.
    seed: int
    campos_inferidos: list[str]
    escenarios: list[EscenarioOut]


@router.post(
    "/montecarlo",
    summary="N-trajectory Monte Carlo projection of PhenoAge under each intervention scenario",
    responses={422: {"description": "Unknown scenario key, or date_of_birth/sex_at_birth is not on file"}},
)
async def run_montecarlo(
    body: MontecarloIn, user: CurrentUserDep, session: SessionDep
) -> MontecarloOut:
    edad, sexo, biomarcadores = await _read_inputs(session, user.id)

    escenarios = body.escenarios if body.escenarios is not None else list(SCENARIOS)
    unknown = [key for key in escenarios if key not in SCENARIOS]
    if unknown:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"escenario(s) desconocido(s): {unknown}. válidos: {list(SCENARIOS)}",
        )

    resultados, imputados, seed_usado = montecarlo.run(
        biomarcadores,
        edad,
        sexo,
        escenarios,
        body.n_trayectorias,
        body.anios,
        seed=body.seed,
        adherencia=body.adherencia,
        percentiles=(body.percentil_inferior, body.percentil_superior),
    )
    return MontecarloOut(
        edad_cronologica=edad,
        horizonte_anios=min(body.anios, montecarlo.MAX_ANIOS),
        trayectorias_por_escenario=min(body.n_trayectorias, montecarlo.MAX_TRAYECTORIAS),
        adherencia=body.adherencia,
        percentil_inferior=body.percentil_inferior,
        percentil_superior=body.percentil_superior,
        seed=seed_usado,
        campos_inferidos=imputados,
        escenarios=[
            EscenarioOut(
                escenario=r.escenario,
                nombre=r.nombre,
                edad_biologica_p10=round(r.edad_biologica_p10, 2),
                edad_biologica_mediana=round(r.edad_biologica_mediana, 2),
                edad_biologica_p90=round(r.edad_biologica_p90, 2),
                trayectoria=(
                    [
                        TrayectoriaPuntoOut(
                            anio=p.anio,
                            edad_biologica_p_inferior=round(p.edad_biologica_p_inferior, 2),
                            edad_biologica_mediana=round(p.edad_biologica_mediana, 2),
                            edad_biologica_p_superior=round(p.edad_biologica_p_superior, 2),
                        )
                        for p in r.trayectoria
                    ]
                    if body.incluir_trayectoria
                    else None
                ),
            )
            for r in resultados
        ],
    )
