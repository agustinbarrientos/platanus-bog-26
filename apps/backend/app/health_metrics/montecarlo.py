"""N-trajectory Monte Carlo: for one scenario, evolve every biomarker a year
at a time for `anios` years, computing PhenoAge at the end of each of the N
independent trajectories. The spread across trajectories — driven by the
per-biomarker noise in `interventions.DYNAMICS`, applied fresh every
simulated year — is what turns a single point prediction into a distribution
of plausible futures.

PhenoAge is scored with `phenoage_years_batch` (vectorized: one call scores
every trajectory at once) rather than one `phenoage_years` call per
trajectory — cheap enough that scoring every simulated year, not just the
last one, costs almost nothing, which is what makes the optional
`incluir_trayectoria` output affordable.
"""

from __future__ import annotations

from typing import NamedTuple

import numpy as np

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.nhanes_reference import impute_missing
from app.health_metrics.phenoage import phenoage_years_batch

#: Hard ceiling on trajectory count so an authenticated caller can't turn this
#: into a CPU-burning DoS by asking for an arbitrarily large N.
MAX_TRAYECTORIAS = 20_000
MAX_ANIOS = 30

DEFAULT_TRAYECTORIAS = 5000
DEFAULT_ANIOS = 10
DEFAULT_PERCENTIL_INFERIOR = 10
DEFAULT_PERCENTIL_SUPERIOR = 90


class TrayectoriaPunto(NamedTuple):
    anio: int
    edad_biologica_p_inferior: float
    edad_biologica_mediana: float
    edad_biologica_p_superior: float


class ScenarioResult(NamedTuple):
    escenario: str
    nombre: str
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float
    trayectoria: list[TrayectoriaPunto]


def _bounds(nombre: str) -> tuple[float, float]:
    spec = BIOMARKER_SPECS[nombre]
    return spec.valor_min, spec.valor_max


def _simulate_scenario(
    valores_iniciales: dict[str, float],
    edad_inicial: float,
    escenario_key: str,
    n_trayectorias: int,
    anios: int,
    adherencia: float,
    percentiles: tuple[float, float],
    rng: np.random.Generator,
) -> ScenarioResult:
    scenario = SCENARIOS[escenario_key]
    p_inf, p_sup = percentiles

    # One row per trajectory, one column per biomarker — evolved together so
    # every trajectory's noise draw is independent of every other trajectory's.
    state = np.array(
        [[valores_iniciales[nombre]] * n_trayectorias for nombre in PHENOAGE_BIOMARKERS]
    )  # shape (9, n_trayectorias)

    trayectoria: list[TrayectoriaPunto] = []
    for year in range(1, anios + 1):
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            dyn = DYNAMICS[nombre]
            # `adherencia` scales only the intervention's own effect, not the
            # natural-aging drift everyone gets regardless of intervention —
            # 0 adherencia should reduce to "ninguna", not to "no aging at all".
            deriva = dyn.deriva_anual + scenario.efectos_anuales.get(nombre, 0.0) * adherencia
            ruido = rng.normal(0.0, dyn.ruido_anual_sd, size=n_trayectorias)
            state[i] = state[i] + deriva + ruido

        # Clamp after each year, not just at the end: an unclamped random walk
        # can wander a biomarker (e.g. leucocitos) negative mid-simulation and
        # never recover, which would poison every later year for that path.
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            state[i] = np.clip(state[i], *_bounds(nombre))

        valores_anio = {nombre: state[i] for i, nombre in enumerate(PHENOAGE_BIOMARKERS)}
        edades_biologicas = phenoage_years_batch(valores_anio, edad_inicial + year)
        lo, mediana, hi = np.percentile(edades_biologicas, [p_inf, 50, p_sup])
        trayectoria.append(TrayectoriaPunto(year, float(lo), float(mediana), float(hi)))

    ultimo = trayectoria[-1]
    return ScenarioResult(
        escenario=escenario_key,
        nombre=scenario.nombre,
        edad_biologica_p10=ultimo.edad_biologica_p_inferior,
        edad_biologica_mediana=ultimo.edad_biologica_mediana,
        edad_biologica_p90=ultimo.edad_biologica_p_superior,
        trayectoria=trayectoria,
    )


def run(
    biomarcadores: dict[str, float],
    edad: float,
    sexo_biologico: str | None,
    escenarios: list[str],
    n_trayectorias: int = DEFAULT_TRAYECTORIAS,
    anios: int = DEFAULT_ANIOS,
    seed: int | None = None,
    adherencia: float = 1.0,
    percentiles: tuple[float, float] = (DEFAULT_PERCENTIL_INFERIOR, DEFAULT_PERCENTIL_SUPERIOR),
) -> tuple[list[ScenarioResult], list[str], int]:
    """Run every scenario in `escenarios` from the same starting point, so
    they are directly comparable. Returns the per-scenario distributions, the
    list of biomarkers that had to be imputed to get a starting point, and
    the seed actually used (generated here if the caller didn't pin one, so
    the response can echo it back for an exact replay later).

    `adherencia` (0–1) scales how strongly a scenario's intervention effect
    applies — 1.0 is "as modeled", 0.0 collapses every scenario to the
    `ninguna` baseline (only natural drift + noise, no intervention benefit).
    """
    valores_iniciales, imputados = impute_missing(biomarcadores, edad, sexo_biologico)

    n = min(n_trayectorias, MAX_TRAYECTORIAS)
    a = min(anios, MAX_ANIOS)
    seed_usado = seed if seed is not None else int(np.random.SeedSequence().entropy % (2**63))
    rng = np.random.default_rng(seed_usado)

    resultados = [
        _simulate_scenario(valores_iniciales, edad, key, n, a, adherencia, percentiles, rng)
        for key in escenarios
    ]
    return resultados, imputados, seed_usado
