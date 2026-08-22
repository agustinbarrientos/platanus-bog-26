"""N-trajectory Monte Carlo: for one scenario, evolve every biomarker a year
at a time for `anios` years, computing PhenoAge at the end of each of the N
independent trajectories. The spread across trajectories — driven by the
per-biomarker noise in `interventions.DYNAMICS`, applied fresh every
simulated year — is what turns a single point prediction into a distribution
of plausible futures.
"""

from __future__ import annotations

from typing import NamedTuple

import numpy as np

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.nhanes_reference import impute_missing
from app.health_metrics.phenoage import phenoage_years, to_formula_units

#: Hard ceiling on trajectory count so an authenticated caller can't turn this
#: into a CPU-burning DoS by asking for an arbitrarily large N.
MAX_TRAYECTORIAS = 20_000
MAX_ANIOS = 30

DEFAULT_TRAYECTORIAS = 5000
DEFAULT_ANIOS = 10


class ScenarioResult(NamedTuple):
    escenario: str
    nombre: str
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float


def _simulate_scenario(
    valores_iniciales: dict[str, float],
    edad_inicial: float,
    escenario_key: str,
    n_trayectorias: int,
    anios: int,
    rng: np.random.Generator,
) -> ScenarioResult:
    scenario = SCENARIOS[escenario_key]

    # One row per trajectory, one column per biomarker — evolved together so
    # every trajectory's noise draw is independent of every other trajectory's.
    state = np.array(
        [[valores_iniciales[nombre]] * n_trayectorias for nombre in PHENOAGE_BIOMARKERS]
    )  # shape (9, n_trayectorias)

    for _year in range(anios):
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            dyn = DYNAMICS[nombre]
            deriva = dyn.deriva_anual + scenario.efectos_anuales.get(nombre, 0.0)
            ruido = rng.normal(0.0, dyn.ruido_anual_sd, size=n_trayectorias)
            state[i] = state[i] + deriva + ruido

        # Clamp after each year, not just at the end: an unclamped random walk
        # can wander a biomarker (e.g. leucocitos) negative mid-simulation and
        # never recover, which would poison every later year for that path.
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            state[i] = np.clip(state[i], *_bounds(nombre))

    edad_final = edad_inicial + anios
    edades_biologicas = np.empty(n_trayectorias)
    for t in range(n_trayectorias):
        valores_t = {nombre: state[i, t] for i, nombre in enumerate(PHENOAGE_BIOMARKERS)}
        edades_biologicas[t] = phenoage_years(to_formula_units(valores_t), edad_final)

    p10, mediana, p90 = np.percentile(edades_biologicas, [10, 50, 90])
    return ScenarioResult(
        escenario=escenario_key,
        nombre=scenario.nombre,
        edad_biologica_p10=float(p10),
        edad_biologica_mediana=float(mediana),
        edad_biologica_p90=float(p90),
    )


def _bounds(nombre: str) -> tuple[float, float]:
    spec = BIOMARKER_SPECS[nombre]
    return spec.valor_min, spec.valor_max


def run(
    biomarcadores: dict[str, float],
    edad: float,
    sexo_biologico: str | None,
    escenarios: list[str],
    n_trayectorias: int = DEFAULT_TRAYECTORIAS,
    anios: int = DEFAULT_ANIOS,
    seed: int | None = None,
) -> tuple[list[ScenarioResult], list[str]]:
    """Run every scenario in `escenarios` from the same starting point, so
    they are directly comparable. Returns the per-scenario distributions plus
    the list of biomarkers that had to be imputed to get a starting point."""
    valores_iniciales, imputados = impute_missing(biomarcadores, edad, sexo_biologico)

    n = min(n_trayectorias, MAX_TRAYECTORIAS)
    a = min(anios, MAX_ANIOS)
    rng = np.random.default_rng(seed)

    resultados = [
        _simulate_scenario(valores_iniciales, edad, key, n, a, rng) for key in escenarios
    ]
    return resultados, imputados
