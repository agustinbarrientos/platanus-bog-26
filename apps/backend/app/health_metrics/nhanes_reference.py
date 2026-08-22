"""Median-by-age/sex imputation table for the 9 PhenoAge biomarkers.

Levine et al. 2018 fit PhenoAge on NHANES III. These medians are hand-set,
clinically-plausible reference values *in the shape and rough trend* of what
NHANES reports for each biomarker (creatinine and alkaline phosphatase rising
with age, lymphocyte percent falling, etc.) — not values extracted from the
NHANES microdata itself. Good enough to fill a gap in a demo and label it
honestly; not a substitute for a real NHANES percentile lookup before this
feeds anything beyond a demo.
"""

from __future__ import annotations

from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS

#: (age < upper_bound, label). Checked in order.
_AGE_BRACKETS: tuple[tuple[float, str], ...] = (
    (30, "<30"),
    (45, "30-44"),
    (60, "45-59"),
    (75, "60-74"),
    (float("inf"), "75+"),
)

#: bracket_label -> sex -> biomarker -> median value, in the storage units
#: from `BIOMARKER_SPECS` (mg/dL, g/dL, %, fL, ...).
_MEDIANS: dict[str, dict[str, dict[str, float]]] = {
    "<30": {
        "F": {
            "hs_CRP": 1.0, "glucosa": 88, "albumina": 4.4, "creatinina": 0.7,
            "fosfatasa_alcalina": 65, "linfocitos_pct": 34, "vcm": 89, "rdw": 12.8,
            "leucocitos": 6.5,
        },
        "M": {
            "hs_CRP": 1.0, "glucosa": 90, "albumina": 4.5, "creatinina": 0.9,
            "fosfatasa_alcalina": 70, "linfocitos_pct": 32, "vcm": 90, "rdw": 12.9,
            "leucocitos": 6.7,
        },
    },
    "30-44": {
        "F": {
            "hs_CRP": 1.3, "glucosa": 90, "albumina": 4.3, "creatinina": 0.75,
            "fosfatasa_alcalina": 68, "linfocitos_pct": 32, "vcm": 90, "rdw": 13.0,
            "leucocitos": 6.6,
        },
        "M": {
            "hs_CRP": 1.3, "glucosa": 93, "albumina": 4.4, "creatinina": 0.95,
            "fosfatasa_alcalina": 73, "linfocitos_pct": 30, "vcm": 91, "rdw": 13.1,
            "leucocitos": 6.8,
        },
    },
    "45-59": {
        "F": {
            "hs_CRP": 1.8, "glucosa": 94, "albumina": 4.2, "creatinina": 0.8,
            "fosfatasa_alcalina": 72, "linfocitos_pct": 30, "vcm": 91, "rdw": 13.3,
            "leucocitos": 6.7,
        },
        "M": {
            "hs_CRP": 1.8, "glucosa": 98, "albumina": 4.3, "creatinina": 1.0,
            "fosfatasa_alcalina": 77, "linfocitos_pct": 28, "vcm": 92, "rdw": 13.4,
            "leucocitos": 6.9,
        },
    },
    "60-74": {
        "F": {
            "hs_CRP": 2.2, "glucosa": 98, "albumina": 4.0, "creatinina": 0.85,
            "fosfatasa_alcalina": 78, "linfocitos_pct": 28, "vcm": 92, "rdw": 13.8,
            "leucocitos": 6.8,
        },
        "M": {
            "hs_CRP": 2.2, "glucosa": 103, "albumina": 4.1, "creatinina": 1.05,
            "fosfatasa_alcalina": 83, "linfocitos_pct": 27, "vcm": 93, "rdw": 13.9,
            "leucocitos": 7.0,
        },
    },
    "75+": {
        "F": {
            "hs_CRP": 2.6, "glucosa": 102, "albumina": 3.8, "creatinina": 0.9,
            "fosfatasa_alcalina": 85, "linfocitos_pct": 26, "vcm": 93, "rdw": 14.4,
            "leucocitos": 6.9,
        },
        "M": {
            "hs_CRP": 2.6, "glucosa": 108, "albumina": 3.9, "creatinina": 1.1,
            "fosfatasa_alcalina": 90, "linfocitos_pct": 25, "vcm": 94, "rdw": 14.6,
            "leucocitos": 7.1,
        },
    },
}


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
