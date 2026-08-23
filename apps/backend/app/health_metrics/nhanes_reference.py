"""Reference population for the 9 PhenoAge biomarkers: median by age/sex
(imputation + "persona de referencia") and the population spread around that
median (uncertainty of an imputed value, percentile of a PhenoAge).

Levine et al. 2018 fit PhenoAge on NHANES III. These medians are hand-set,
clinically plausible values *in the shape and trend* of what NHANES reports
(creatinine, alkaline phosphatase, RDW and CRP rising with age; albumin and
lymphocyte percent falling) — not values extracted from the NHANES microdata.

CALIBRACIÓN (2026-08-22). La tabla anterior era más "sana" que la población
sobre la que se ajustó la fórmula: la persona mediana de cada tramo (los 9
valores imputados) marcaba 5–8 años MENOS que su edad cronológica entre los
20 y los 45, y +4 a los 80 en hombres. Eso sesgaba a todo usuario sin
exámenes, ponía a la mediana en el percentil ~15 y hacía que la línea base
envejeciera 1,2 años PhenoAge por año. Dos diferencias de ensayo conocidas
entre NHANES III y un laboratorio actual explican la mayor parte: la
creatinina de NHANES III no estaba estandarizada a IDMS y lee ~0,2 mg/dL más
alta (Selvin et al. 2007), y la PCR tenía límite de detección de 0,21 mg/dL
(2,1 mg/L), así que la mediana joven del ajuste está en ese piso. La tabla se
recalibró bajo un criterio explícito y verificable (`tests/test_phenoage.py`):
**la persona mediana de cada tramo y sexo marca ≈ su edad cronológica**
(aceleración dentro de ±2 años, mujeres ~1 año por debajo de los hombres,
como en NHANES), con gradientes por edad moderados y plausibles. Sigue siendo
una tabla de referencia aproximada, no el microdato; el chat y la UI lo dicen.
"""

from __future__ import annotations

import math
from typing import Literal

import numpy as np

from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS

#: (age < upper_bound, label). Checked in order.
_AGE_BRACKETS: tuple[tuple[float, str], ...] = (
    (30, "<30"),
    (45, "30-44"),
    (60, "45-59"),
    (75, "60-74"),
    (float("inf"), "75+"),
)

#: Chronological age at the centre of each bracket, for gradients/tests.
BRACKET_MIDPOINTS: dict[str, float] = {"<30": 25, "30-44": 37, "45-59": 52, "60-74": 67, "75+": 80}

#: bracket_label -> sex -> biomarker -> median value, in the storage units
#: from `BIOMARKER_SPECS` (mg/dL, g/dL, %, fL, ...).
_MEDIANS: dict[str, dict[str, dict[str, float]]] = {
    "<30": {
        "F": {"hs_CRP": 2.2, "glucosa": 92, "albumina": 4.22, "creatinina": 0.9, "fosfatasa_alcalina": 78, "linfocitos_pct": 30.5, "vcm": 90.3, "rdw": 13.35, "leucocitos": 7.0},
        "M": {"hs_CRP": 1.8, "glucosa": 96, "albumina": 4.34, "creatinina": 1.08, "fosfatasa_alcalina": 81, "linfocitos_pct": 29.5, "vcm": 90.8, "rdw": 13.15, "leucocitos": 7.0},
    },
    "30-44": {
        "F": {"hs_CRP": 2.3, "glucosa": 94.5, "albumina": 4.17, "creatinina": 0.92, "fosfatasa_alcalina": 80, "linfocitos_pct": 30, "vcm": 90.7, "rdw": 13.5, "leucocitos": 7.05},
        "M": {"hs_CRP": 1.9, "glucosa": 98.5, "albumina": 4.29, "creatinina": 1.1, "fosfatasa_alcalina": 83, "linfocitos_pct": 29, "vcm": 91.2, "rdw": 13.3, "leucocitos": 7.05},
    },
    "45-59": {
        "F": {"hs_CRP": 2.5, "glucosa": 97.5, "albumina": 4.1, "creatinina": 0.945, "fosfatasa_alcalina": 82, "linfocitos_pct": 29.2, "vcm": 91.2, "rdw": 13.7, "leucocitos": 7.1},
        "M": {"hs_CRP": 2.1, "glucosa": 101.5, "albumina": 4.22, "creatinina": 1.125, "fosfatasa_alcalina": 85, "linfocitos_pct": 28.2, "vcm": 91.7, "rdw": 13.5, "leucocitos": 7.1},
    },
    "60-74": {
        "F": {"hs_CRP": 2.65, "glucosa": 100.5, "albumina": 4.02, "creatinina": 0.97, "fosfatasa_alcalina": 84.5, "linfocitos_pct": 28.5, "vcm": 91.7, "rdw": 13.9, "leucocitos": 7.2},
        "M": {"hs_CRP": 2.25, "glucosa": 104.5, "albumina": 4.14, "creatinina": 1.15, "fosfatasa_alcalina": 87.5, "linfocitos_pct": 27.5, "vcm": 92.2, "rdw": 13.7, "leucocitos": 7.2},
    },
    "75+": {
        "F": {"hs_CRP": 2.8, "glucosa": 103, "albumina": 3.95, "creatinina": 0.99, "fosfatasa_alcalina": 86, "linfocitos_pct": 27.8, "vcm": 92.2, "rdw": 14.0, "leucocitos": 7.25},
        "M": {"hs_CRP": 2.4, "glucosa": 107, "albumina": 4.07, "creatinina": 1.17, "fosfatasa_alcalina": 89, "linfocitos_pct": 26.8, "vcm": 92.7, "rdw": 13.8, "leucocitos": 7.25},
    },
}

Distribucion = Literal["normal", "lognormal"]

#: Dispersión poblacional aproximada de cada biomarcador alrededor de su
#: mediana, para (a) muestrear el valor de arranque de un biomarcador NO medido
#: en la Capa 3 — así un dato imputado ensancha la banda, como pide la spec §6 —
#: y (b) convertir una aceleración PhenoAge en percentil poblacional.
#: `lognormal` = sigma en escala log (asimétricos, cola derecha: PCR, glucosa,
#: creatinina, fosfatasa, RDW, leucocitos); `normal` = SD en la unidad de
#: almacenamiento. Órdenes de magnitud de distribuciones adultas publicadas
#: (NHANES / rangos de referencia de laboratorio), no ajustes propios:
#: PCR ~ GSD 2,7; glucosa en ayunas SD ~10–12 mg/dL; albúmina SD 0,3 g/dL;
#: creatinina GSD ~1,2; fosfatasa alcalina GSD ~1,35; linfocitos SD 7 puntos;
#: VCM SD 5 fL; RDW SD ~1 %; leucocitos GSD ~1,3.
DISPERSION: dict[str, tuple[Distribucion, float]] = {
    "hs_CRP": ("lognormal", 1.0),
    "glucosa": ("lognormal", 0.12),
    "albumina": ("normal", 0.3),
    "creatinina": ("lognormal", 0.2),
    "fosfatasa_alcalina": ("lognormal", 0.3),
    "linfocitos_pct": ("normal", 7.0),
    "vcm": ("normal", 5.0),
    "rdw": ("lognormal", 0.075),
    "leucocitos": ("lognormal", 0.27),
}

assert set(DISPERSION) == set(PHENOAGE_BIOMARKERS)


def _bracket(edad: float) -> str:
    for upper, label in _AGE_BRACKETS:
        if edad < upper:
            return label
    return "75+"  # pragma: no cover — unreachable, last bracket is inf


def _sex_bucket(sexo_biologico: str | None) -> str | None:
    """"F"/"female"/"femenino" -> "F"; "M"/"male"/"masculino" -> "M"; else None
    (caller averages both buckets)."""
    if not sexo_biologico:
        return None
    first = sexo_biologico.strip().lower()[:1]
    if first == "f":
        return "F"
    if first == "m":
        return "M"
    return None


def median_for(nombre: str, edad: float, sexo_biologico: str | None) -> float:
    """The reference median for one biomarker at this age/sex.

    Falls back to the average of the male and female median when sex is
    unspecified or not recognised, rather than guessing.
    """
    bracket = _MEDIANS[_bracket(edad)]
    sex = _sex_bucket(sexo_biologico)
    if sex is not None:
        return bracket[sex][nombre]
    return (bracket["F"][nombre] + bracket["M"][nombre]) / 2


def reference_person(edad: float, sexo_biologico: str | None) -> dict[str, float]:
    """The 9 medians for this age/sex — the "persona de referencia"."""
    return {nombre: median_for(nombre, edad, sexo_biologico) for nombre in PHENOAGE_BIOMARKERS}


def impute_missing(
    valores: dict[str, float], edad: float, sexo_biologico: str | None
) -> tuple[dict[str, float], list[str]]:
    """Fill in whichever of the 9 PhenoAge biomarkers `valores` is missing.

    Returns the complete 9-value dict plus the list of names that were
    imputed rather than measured — that list is what the caller marks
    "inferido" in the response, same spirit as `datos_faltantes`.
    """
    complete = dict(valores)
    imputed: list[str] = []
    for nombre in PHENOAGE_BIOMARKERS:
        if complete.get(nombre) is None:
            complete[nombre] = median_for(nombre, edad, sexo_biologico)
            imputed.append(nombre)
    return complete, imputed


def sample_reference(
    nombre: str, mediana: float, rng: np.random.Generator, n: int
) -> np.ndarray:
    """`n` plausible values of a biomarker we did NOT measure, drawn around the
    reference median with the population spread of `DISPERSION`. This is the
    starting-state uncertainty of an imputed biomarker in the Monte Carlo."""
    dist, sigma = DISPERSION[nombre]
    if dist == "lognormal":
        return mediana * np.exp(rng.normal(0.0, sigma, size=n))
    return mediana + rng.normal(0.0, sigma, size=n)


def desviacion_tipica_1sd(nombre: str, mediana: float) -> float:
    """One population SD of `nombre` expressed in storage units at `mediana`
    (for lognormal ones: the upward 1-sigma step). Used for sensitivity /
    percentile maths without sampling."""
    dist, sigma = DISPERSION[nombre]
    if dist == "lognormal":
        return mediana * (math.exp(sigma) - 1.0)
    return sigma


__all__ = [
    "BRACKET_MIDPOINTS",
    "DISPERSION",
    "desviacion_tipica_1sd",
    "impute_missing",
    "median_for",
    "reference_person",
    "sample_reference",
]
