"""The fixed biomarker vocabulary.

`nombre` used to be free text (see git history of `app/routers/health_context.py`),
which meant a compute endpoint could not tell "hs_CRP" from "proteina_c_reactiva"
from "PCR" — three callers describing the same measurement three ways. Every
biomarker this API accepts is listed here, each pinned to one storage unit, so
`nombre` can be validated as an enum and `unidad` checked against it.

Storage units are chosen to match what a person would actually read off a lab
report (mg/dL, g/dL, mmHg, ...), not the SI units the PhenoAge formula wants —
`app/health_metrics/phenoage.py` does that conversion at compute time, once,
in one place, rather than asking every caller to convert before sending data.
"""

from __future__ import annotations

from typing import Literal, NamedTuple

#: The 9 inputs of Levine et al. 2018's PhenoAge clock (plus chronological
#: age, which comes from `demografia.edad`, not this list).
PHENOAGE_BIOMARKERS = (
    "hs_CRP",
    "glucosa",
    "albumina",
    "creatinina",
    "fosfatasa_alcalina",
    "linfocitos_pct",
    "vcm",
    "rdw",
    "leucocitos",
)

#: Collected because they feed other risk models (CAIDE-style dementia risk
#: uses systolic BP, BMI and total cholesterol alongside age/sex/education),
#: not because PhenoAge needs them.
OTHER_BIOMARKERS = (
    "colesterol_total",
    "presion_sistolica",
    "imc",
)

BiomarkerName = Literal[
    "hs_CRP",
    "glucosa",
    "albumina",
    "creatinina",
    "fosfatasa_alcalina",
    "linfocitos_pct",
    "vcm",
    "rdw",
    "leucocitos",
    "colesterol_total",
    "presion_sistolica",
    "imc",
]


class BiomarkerSpec(NamedTuple):
    unidad: str
    valor_min: float
    valor_max: float
    descripcion: str


#: (unit, plausible min, plausible max, description). Bounds are wide clinical
#: sanity limits — the same spirit as the CHECK constraints on `profiles`
#: (profiles_height_plausible etc.), not tight reference ranges.
BIOMARKER_SPECS: dict[str, BiomarkerSpec] = {
    "hs_CRP": BiomarkerSpec("mg/L", 0.01, 200.0, "Proteína C reactiva de alta sensibilidad"),
    "glucosa": BiomarkerSpec("mg/dL", 30.0, 600.0, "Glucosa en ayunas"),
    "albumina": BiomarkerSpec("g/dL", 1.5, 6.0, "Albúmina sérica"),
    "creatinina": BiomarkerSpec("mg/dL", 0.2, 15.0, "Creatinina sérica"),
    "fosfatasa_alcalina": BiomarkerSpec("U/L", 20.0, 500.0, "Fosfatasa alcalina"),
    "linfocitos_pct": BiomarkerSpec("%", 1.0, 90.0, "Porcentaje de linfocitos"),
    "vcm": BiomarkerSpec("fL", 50.0, 130.0, "Volumen corpuscular medio"),
    "rdw": BiomarkerSpec("%", 10.0, 25.0, "Ancho de distribución eritrocitaria"),
    "leucocitos": BiomarkerSpec("10^3/uL", 1.0, 50.0, "Recuento de leucocitos"),
    "colesterol_total": BiomarkerSpec("mg/dL", 50.0, 500.0, "Colesterol total"),
    "presion_sistolica": BiomarkerSpec("mmHg", 60.0, 260.0, "Presión arterial sistólica"),
    "imc": BiomarkerSpec("kg/m2", 10.0, 80.0, "Índice de masa corporal"),
}


def clamp(nombre: str, valor: float) -> float:
    """Keep a value inside the physiologically plausible band for `nombre`.

    Used by the Monte Carlo random walk, which can otherwise wander a
    biomarker into a negative white cell count after enough noisy years.
    """
    spec = BIOMARKER_SPECS[nombre]
    return min(max(valor, spec.valor_min), spec.valor_max)
