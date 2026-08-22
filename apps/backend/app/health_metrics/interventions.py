"""Per-year biomarker dynamics for the Monte Carlo simulation: how each of the
9 PhenoAge biomarkers drifts with age alone, how much it jitters year to year,
and how much each intervention scenario shifts that drift.

These are directional, order-of-magnitude numbers synthesized from the general
direction of the exercise / diet / smoking-cessation biomarker literature
(aerobic exercise and Mediterranean-diet trials lowering CRP and fasting
glucose, smoking cessation lowering WBC and CRP) — not coefficients fitted to
a specific trial or meta-analysis. Good enough to make the scenarios visibly
separate from each other and from "no intervention" in the fan of simulated
futures; not something to point at a real recommendation before it is
replaced with real effect sizes. All in the storage units from
`BIOMARKER_SPECS` (mg/dL, g/dL, %, fL, ...), applied once per simulated year.
"""

from __future__ import annotations

from typing import NamedTuple

from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS


class BiomarkerDynamics(NamedTuple):
    deriva_anual: float  # natural aging trend, per year
    ruido_anual_sd: float  # year-to-year biological variability (Gaussian SD)


#: Natural aging trend + noise, independent of any intervention.
DYNAMICS: dict[str, BiomarkerDynamics] = {
    "hs_CRP": BiomarkerDynamics(0.03, 0.6),
    "glucosa": BiomarkerDynamics(0.5, 4.0),
    "albumina": BiomarkerDynamics(-0.01, 0.08),
    "creatinina": BiomarkerDynamics(0.005, 0.04),
    "fosfatasa_alcalina": BiomarkerDynamics(0.3, 4.0),
    "linfocitos_pct": BiomarkerDynamics(-0.15, 1.5),
    "vcm": BiomarkerDynamics(0.1, 1.0),
    "rdw": BiomarkerDynamics(0.03, 0.3),
    "leucocitos": BiomarkerDynamics(0.01, 0.4),
}

assert set(DYNAMICS) == set(PHENOAGE_BIOMARKERS)


class Scenario(NamedTuple):
    nombre: str
    #: Additional per-year delta on top of `DYNAMICS[...].deriva_anual`, for
    #: whichever biomarkers this intervention plausibly moves. Absent
    #: biomarkers get no adjustment beyond the natural drift.
    efectos_anuales: dict[str, float]


SCENARIOS: dict[str, Scenario] = {
    "ninguna": Scenario("Sin intervención (línea base)", {}),
    "ejercicio_aerobico": Scenario(
        "Ejercicio aeróbico regular",
        {"hs_CRP": -0.08, "glucosa": -0.9, "leucocitos": -0.03},
    ),
    "dieta_mediterranea": Scenario(
        "Dieta mediterránea",
        {"hs_CRP": -0.06, "glucosa": -0.6, "albumina": 0.01},
    ),
    "cesacion_tabaco": Scenario(
        "Cesación de tabaco",
        {"leucocitos": -0.15, "hs_CRP": -0.10, "vcm": -0.15},
    ),
    "combinada": Scenario(
        "Ejercicio + dieta mediterránea + cesación de tabaco",
        {
            "hs_CRP": -0.20, "glucosa": -1.4, "leucocitos": -0.16,
            "albumina": 0.01, "vcm": -0.10,
        },
    ),
}
