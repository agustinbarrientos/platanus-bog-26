"""The user's longevity/risk-assessment intake — demographics, biomarkers,
habits, family history and stated goals. Same shape as `/me`: the token says
who is calling, and a PATCH saves whichever fields the caller was able to
collect without wiping the rest.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, model_validator
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUserDep
from app.db import get_db
from app.health_metrics.biomarkers import BIOMARKER_SPECS, BiomarkerName
from app.models import HealthContext

router = APIRouter(prefix="/me/health-context", tags=["health-context"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]

_EXAMPLE = {
    "demografia": {
        "edad": 52,
        "sexo_biologico": "F",
        "ancestria_reportada": "mixta_latam",
        "escolaridad_anios": 12,
    },
    "biomarcadores": [
        {"nombre": "hs_CRP", "valor": 2.1, "unidad": "mg/L", "fuente": "documento"},
        {"nombre": "glucosa", "valor": 92, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "albumina", "valor": 4.4, "unidad": "g/dL", "fuente": "reportado"},
        {"nombre": "colesterol_total", "valor": 262, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "presion_sistolica", "valor": 146, "unidad": "mmHg", "fuente": "reportado"},
        {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"},
    ],
    "habitos": {
        "sueno_h": 6,
        "tabaco": False,
        "actividad": "baja",
        "alimentacion": "media",
        "estres": "alto",
    },
    "historia_familiar": ["diabetes_t2", "alzheimer_materno"],
    "objetivos_usuario": ["energia", "prevencion"],
    "datos_faltantes": ["creatinina", "fosfatasa_alcalina", "APOE"],
    "notas_incertidumbre": (
        "creatinina y fosfatasa imputadas de medianas NHANES por edad/sexo; "
        "sin genotipo APOE, se usa CAIDE modelo 1 (sin genética)"
    ),
}


class Demografia(BaseModel):
    model_config = ConfigDict(extra="forbid")

    edad: int | None = None
    sexo_biologico: str | None = None
    ancestria_reportada: str | None = None
    escolaridad_anios: int | None = None


class Biomarcador(BaseModel):
    """`nombre` is pinned to the fixed vocabulary in `BIOMARKER_SPECS` — the
    compute endpoints (PhenoAge, Monte Carlo) key off these exact names, so a
    biomarker they don't recognise by an unlisted spelling is one they'd
    silently treat as missing instead of using. `unidad` and `valor` are
    checked against that same spec so a value can't be stored in the wrong
    unit or outside a physiologically plausible range.
    """

    model_config = ConfigDict(extra="forbid")

    nombre: BiomarkerName
    valor: float
    unidad: str
    #: e.g. "documento" | "reportado" | "calculado" — not constrained to a
    #: fixed set, since the source system decides that vocabulary, not this API.
    fuente: str

    @model_validator(mode="after")
    def _check_unit_and_range(self) -> "Biomarcador":
        spec = BIOMARKER_SPECS[self.nombre]
        if self.unidad != spec.unidad:
            raise ValueError(f"{self.nombre} se espera en {spec.unidad!r}, no {self.unidad!r}")
        if not (spec.valor_min <= self.valor <= spec.valor_max):
            raise ValueError(
                f"{self.nombre}={self.valor} fuera de rango plausible "
                f"[{spec.valor_min}, {spec.valor_max}] {spec.unidad}"
            )
        return self


class Habitos(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sueno_h: float | None = None
    tabaco: bool | None = None
    actividad: str | None = None
    alimentacion: str | None = None
    estres: str | None = None


class HealthContextPatch(BaseModel):
    """Every field optional and each one replaces the field wholesale when
    sent — same `exclude_unset` contract as `ProfilePatch`: a field the caller
    could not collect this round is simply omitted, not sent as null.
    """

    model_config = ConfigDict(extra="forbid", json_schema_extra={"example": _EXAMPLE})

    demografia: Demografia | None = None
    biomarcadores: list[Biomarcador] | None = None
    habitos: Habitos | None = None
    historia_familiar: list[str] | None = None
    objetivos_usuario: list[str] | None = None
    datos_faltantes: list[str] | None = None
    notas_incertidumbre: str | None = None


class HealthContextOut(BaseModel):
    model_config = ConfigDict(from_attributes=True, json_schema_extra={"example": _EXAMPLE})

    demografia: Demografia | None
    biomarcadores: list[Biomarcador] | None
    habitos: Habitos | None
    historia_familiar: list[str] | None
    objetivos_usuario: list[str] | None
    datos_faltantes: list[str] | None
    notas_incertidumbre: str | None


#: `demografia` and `habitos` are objects the caller fills in one field at a
#: time, same as the top-level profile — so a PATCH merges into what is
#: already stored instead of replacing the whole blob and losing siblings the
#: caller did not happen to resend this round. A key absent from the patch is
#: left alone; a key sent as `null` clears just that key, same as
#: `ProfilePatch`. Arrays (`biomarcadores`, `historia_familiar`, ...) are
#: still replaced wholesale — merging a list has no single obvious meaning,
#: so the caller resends the full list.
_MERGED_FIELDS = ("demografia", "habitos")


def _merge_patch(existing: dict | None, patch: dict) -> dict:
    return {**(existing or {}), **patch}


async def _get_or_create(session: AsyncSession, user_id) -> HealthContext:
    """The row does not exist until the first PATCH; this is the same
    lazy-create-on-read safety net `profiles` uses.
    """
    await session.execute(
        insert(HealthContext)
        .values(user_id=user_id)
        .on_conflict_do_nothing(index_elements=["user_id"])
    )
    row = await session.get(HealthContext, user_id)
    assert row is not None
    return row


@router.get("", summary="The signed-in user's health context")
async def read_health_context(user: CurrentUserDep, session: SessionDep) -> HealthContextOut:
    row = await _get_or_create(session, user.id)
    return HealthContextOut.model_validate(row)


@router.patch("", summary="Save one or more health-context fields")
async def update_health_context(
    patch: HealthContextPatch, user: CurrentUserDep, session: SessionDep
) -> HealthContextOut:
    row = await _get_or_create(session, user.id)
    # exclude_unset is what separates "not collected" from "collected as
    # null" — mode="json" so nested models land as plain dicts/lists for the
    # JSONB columns rather than Pydantic model instances.
    for field, value in patch.model_dump(exclude_unset=True, mode="json").items():
        if field in _MERGED_FIELDS and value is not None:
            value = _merge_patch(getattr(row, field), value)
        setattr(row, field, value)
    await session.flush()
    await session.refresh(row)
    return HealthContextOut.model_validate(row)
