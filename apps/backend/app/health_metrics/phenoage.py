"""Levine et al. 2018 PhenoAge — the original published (NHANES III-fit)
coefficients, as reproduced in the `phenoage_calc(..., orig = TRUE)` branch of
the `dayoonkwon/BioAge` R package (the reference implementation maintained by
the original PhenoAge/BioAge research group).

Levine, M.E. et al. "An epigenetic biomarker of aging for lifespan and
healthspan." Aging (Albany NY) 10(4):573-591, 2018.

Besides the clock itself this module answers two questions the app asks
about the number: *por qué* (how much each measured biomarker moves it away
from the reference person of the same age/sex) and *frente a personas como
tú* (percentile of the acceleration against the population spread of
`nhanes_reference.DISPERSION`). Both used to be approximated on the device;
computing them here keeps them consistent with the imputation table.
"""

from __future__ import annotations

import math
from collections.abc import Mapping
from typing import NamedTuple

import numpy as np

from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.nhanes_reference import (
    DISPERSION,
    impute_missing,
    reference_person,
)

#: Gompertz mortality-score constants from the published fit. Not
#: biomarker-specific — fixed parts of the mortality-score -> age conversion.
_GAMMA = 0.0076927
_MORTALITY_SCALE = -1.51714
_BA_SCALE = -0.0055305
_BA_EXPONENT = 0.090165
_BA_INTERCEPT = 141.50225

#: Regression coefficients on the (unit-converted) biomarkers, in the order
#: the paper lists them, plus the intercept and the age coefficient.
_INTERCEPT = -19.90667
_COEF = {
    "albumin_gL": -0.03359355,
    "creatinine_umol": 0.009506491,
    "glucose_mmol": 0.1953192,
    "ln_crp_mgdL": 0.09536762,
    "lymphocyte_pct": -0.01199984,
    "mcv_fL": 0.02676401,
    "rdw_pct": 0.3306156,
    "alp_UL": 0.001868778,
    "wbc_1000uL": 0.05542406,
    "age_years": 0.08035356,
}


def to_formula_units(v: Mapping[str, float]) -> dict[str, float]:
    """Convert from the storage units in `BIOMARKER_SPECS` (what a lab report
    reads in) to the units the 2018 fit was trained on."""
    return {
        "albumin_gL": v["albumina"] * 10,  # g/dL -> g/L
        "creatinine_umol": v["creatinina"] * 88.402,  # mg/dL -> umol/L
        "glucose_mmol": v["glucosa"] / 18.0182,  # mg/dL -> mmol/L
        "ln_crp_mgdL": math.log(v["hs_CRP"] / 10),  # mg/L -> mg/dL, then ln
        "lymphocyte_pct": v["linfocitos_pct"],
        "mcv_fL": v["vcm"],
        "rdw_pct": v["rdw"],
        "alp_UL": v["fosfatasa_alcalina"],
        "wbc_1000uL": v["leucocitos"],
    }


def phenoage_years(biomarcadores_formula_units: Mapping[str, float], edad: float) -> float:
    """The formula itself, given values already in the paper's units. Split
    out from `compute()` so it can be unit-tested against the R reference
    without going through unit conversion or imputation."""
    xb = _INTERCEPT + sum(
        _COEF[key] * value for key, value in biomarcadores_formula_units.items()
    ) + _COEF["age_years"] * edad

    # The paper writes this in two steps: M = 1 - exp(k) and then ln(1 - M).
    # Done literally that round-trips through a subtraction that saturates: for
    # a badly-off profile exp(k) underflows, M becomes exactly 1.0, and
    # ln(1 - M) = ln(0) raises. Since ln(1 - M) == k identically, skip M and use
    # k directly — same value everywhere the two-step form is well-conditioned,
    # and stable at the extremes Monte Carlo actually draws.
    ln_1_minus_mortality = (_MORTALITY_SCALE * math.exp(xb)) / _GAMMA
    return (math.log(_BA_SCALE * ln_1_minus_mortality) / _BA_EXPONENT) + _BA_INTERCEPT


def phenoage_years_vector(valores_storage: Mapping[str, np.ndarray], edad: float) -> np.ndarray:
    """Same formula, applied at once to N people/trajectories: every value in
    `valores_storage` is a 1-D array in storage units (one entry per
    trajectory). Identical to `phenoage_years(to_formula_units(...))` element
    by element — `tests/test_phenoage.py` pins that — but ~100x faster, which
    is what lets the Monte Carlo evaluate the clock every simulated year."""
    xb = (
        _INTERCEPT
        + _COEF["albumin_gL"] * (np.asarray(valores_storage["albumina"], dtype=float) * 10)
        + _COEF["creatinine_umol"] * (np.asarray(valores_storage["creatinina"], dtype=float) * 88.402)
        + _COEF["glucose_mmol"] * (np.asarray(valores_storage["glucosa"], dtype=float) / 18.0182)
        + _COEF["ln_crp_mgdL"] * np.log(np.asarray(valores_storage["hs_CRP"], dtype=float) / 10)
        + _COEF["lymphocyte_pct"] * np.asarray(valores_storage["linfocitos_pct"], dtype=float)
        + _COEF["mcv_fL"] * np.asarray(valores_storage["vcm"], dtype=float)
        + _COEF["rdw_pct"] * np.asarray(valores_storage["rdw"], dtype=float)
        + _COEF["alp_UL"] * np.asarray(valores_storage["fosfatasa_alcalina"], dtype=float)
        + _COEF["wbc_1000uL"] * np.asarray(valores_storage["leucocitos"], dtype=float)
        + _COEF["age_years"] * edad
    )
    ln_1_minus_mortality = (_MORTALITY_SCALE * np.exp(xb)) / _GAMMA
    return (np.log(_BA_SCALE * ln_1_minus_mortality) / _BA_EXPONENT) + _BA_INTERCEPT


# ---- "por qué" y "frente a personas como tú" -----------------------------------


def contribuciones(
    valores_usados: Mapping[str, float],
    edad: float,
    sexo_biologico: str | None,
    campos_inferidos: list[str] | tuple[str, ...] = (),
) -> dict[str, float]:
    """Años de edad biológica que cada biomarcador MEDIDO suma (+, envejece) o
    resta (−, rejuvenece) frente a la persona de referencia de la misma edad y
    sexo: PhenoAge(tus valores) − PhenoAge(tus valores con ese biomarcador en
    su mediana de referencia). Un biomarcador imputado contribuye exactamente
    0 — ya ES la mediana. Es la explicación tipo SHAP-sobre-el-basal de la
    spec §7: suficiente para decir "tu RDW es tu eje dominante"; no es SHAP
    sobre las 5.000 trayectorias (spec §12)."""
    base = phenoage_years(to_formula_units(valores_usados), edad)
    ref = reference_person(edad, sexo_biologico)
    out: dict[str, float] = {}
    for nombre in PHENOAGE_BIOMARKERS:
        if nombre in campos_inferidos:
            out[nombre] = 0.0
            continue
        alterado = dict(valores_usados)
        alterado[nombre] = ref[nombre]
        out[nombre] = base - phenoage_years(to_formula_units(alterado), edad)
    return out


def aceleracion_referencia(edad: float, sexo_biologico: str | None) -> float:
    """Aceleración (edad biológica − cronológica) de la persona de referencia
    —los 9 biomarcadores en su mediana— a esta edad y sexo. Por construcción
    de la tabla está cerca de 0 (±2 años); es el cero del percentil."""
    return phenoage_years(to_formula_units(reference_person(edad, sexo_biologico)), edad) - edad


def sd_poblacional(edad: float, sexo_biologico: str | None) -> float:
    """Desviación típica de la aceleración PhenoAge en la población de esa
    edad y sexo, propagando la dispersión poblacional de cada biomarcador
    (`DISPERSION`) por la fórmula (método delta en la persona de referencia).
    Sale ~5 años, consistente con la dispersión de PhenoAge en NHANES (~5–6)."""
    ref = reference_person(edad, sexo_biologico)
    base = phenoage_years(to_formula_units(ref), edad)
    var = 0.0
    for nombre in PHENOAGE_BIOMARKERS:
        dist, sigma = DISPERSION[nombre]
        alterado = dict(ref)
        alterado[nombre] = ref[nombre] * math.exp(sigma) if dist == "lognormal" else ref[nombre] + sigma
        var += (phenoage_years(to_formula_units(alterado), edad) - base) ** 2
    return math.sqrt(var)


def percentil_poblacional(aceleracion: float, edad: float, sexo_biologico: str | None) -> float:
    """Percentil de la aceleración frente a personas de la misma edad y sexo:
    50 = como la referencia; menor = más joven que el promedio; mayor = mayor
    edad biológica. Normal con la SD de `sd_poblacional`, centrada en la
    aceleración de la referencia (así la persona mediana cae en 50 y no en el
    percentil 15 que daba comparar contra 0 a secas)."""
    sd = sd_poblacional(edad, sexo_biologico)
    z = (aceleracion - aceleracion_referencia(edad, sexo_biologico)) / sd
    p = 0.5 * (1 + math.erf(z / math.sqrt(2)))
    return min(99.0, max(1.0, round(p * 100, 1)))


class PhenoAgeResult(NamedTuple):
    edad_cronologica: float
    edad_biologica: float
    aceleracion: float  # edad_biologica - edad_cronologica; positive = aging faster
    valores_usados: dict[str, float]  # the 9 inputs, in storage units, measured + imputed
    campos_inferidos: list[str]
    #: Años que cada biomarcador medido suma/resta frente a la referencia
    #: (0.0 para los imputados). Ver `contribuciones()`.
    contribuciones: dict[str, float]
    #: Aceleración de la persona de referencia a esta edad/sexo (≈0).
    aceleracion_referencia: float
    #: 1–99; 50 = como la referencia de tu edad y sexo.
    percentil_poblacional: float


def compute(
    biomarcadores: dict[str, float], edad: float, sexo_biologico: str | None
) -> PhenoAgeResult:
    """Impute whatever's missing from the 9 PhenoAge inputs, then run the
    formula. `biomarcadores` uses storage units and canonical names from
    `app/health_metrics/biomarkers.py` — pass only the ones actually measured;
    the rest come back imputed."""
    complete, imputed = impute_missing(biomarcadores, edad, sexo_biologico)
    edad_biologica = phenoage_years(to_formula_units(complete), edad)
    aceleracion = edad_biologica - edad
    return PhenoAgeResult(
        edad_cronologica=edad,
        edad_biologica=edad_biologica,
        aceleracion=aceleracion,
        valores_usados=complete,
        campos_inferidos=imputed,
        contribuciones=contribuciones(complete, edad, sexo_biologico, imputed),
        aceleracion_referencia=aceleracion_referencia(edad, sexo_biologico),
        percentil_poblacional=percentil_poblacional(aceleracion, edad, sexo_biologico),
    )
