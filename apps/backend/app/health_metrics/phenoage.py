"""Levine et al. 2018 PhenoAge — the original published (NHANES III-fit)
coefficients, as reproduced in the `phenoage_calc(..., orig = TRUE)` branch of
the `dayoonkwon/BioAge` R package (the reference implementation maintained by
the original PhenoAge/BioAge research group).

Levine, M.E. et al. "An epigenetic biomarker of aging for lifespan and
healthspan." Aging (Albany NY) 10(4):573-591, 2018.
"""

from __future__ import annotations

import math
from typing import NamedTuple

from app.health_metrics.nhanes_reference import impute_missing

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


def to_formula_units(v: dict[str, float]) -> dict[str, float]:
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


def phenoage_years(biomarcadores_formula_units: dict[str, float], edad: float) -> float:
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


class PhenoAgeResult(NamedTuple):
    edad_cronologica: float
    edad_biologica: float
    aceleracion: float  # edad_biologica - edad_cronologica; positive = aging faster
    valores_usados: dict[str, float]  # the 9 inputs, in storage units, measured + imputed
    campos_inferidos: list[str]


def compute(
    biomarcadores: dict[str, float], edad: float, sexo_biologico: str | None
) -> PhenoAgeResult:
    """Impute whatever's missing from the 9 PhenoAge inputs, then run the
    formula. `biomarcadores` uses storage units and canonical names from
    `app/health_metrics/biomarkers.py` — pass only the ones actually measured;
    the rest come back imputed."""
    complete, imputed = impute_missing(biomarcadores, edad, sexo_biologico)
    edad_biologica = phenoage_years(to_formula_units(complete), edad)
    return PhenoAgeResult(
        edad_cronologica=edad,
        edad_biologica=edad_biologica,
        aceleracion=edad_biologica - edad,
        valores_usados=complete,
        campos_inferidos=imputed,
    )
