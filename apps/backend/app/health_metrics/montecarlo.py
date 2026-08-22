"""Capa 3 — Monte Carlo (MOIRAI_ENGINE_SPEC.md §6).

Corre la regla de la Capa 2 N veces, añadiendo ruido biológico fresco en cada
paso anual. Las N trayectorias forman el abanico: mediana, P10 y P90 **año por
año**, no solo al horizonte. Eso es lo que da a la vez la honestidad (la banda
se ensancha con los años porque el futuro se conoce peor) y el wow visual (la
pantalla C dibuja el abanico).

Dos cosas que esta capa hace y que no son obvias:

- **Los biomarcadores imputados ensanchan la banda.** Si un valor no se midió
  sino que salió de la tabla de medianas, su ruido anual se multiplica por
  `SIGMA_IMPUTADO_FACTOR`. Es el requisito de §4 ("menos datos reales -> banda
  P10-P90 más ancha") y lo que hace que "qué conviene medir" tenga sentido como
  pantalla: medir un biomarcador angosta el abanico de verdad.
- **PhenoAge se evalúa vectorizado.** El bucle escalar sobre N trayectorias x
  (años+1) tardaba ~26 s por request con los valores por defecto. `_phenoage_vector`
  hace lo mismo con numpy en una fracción de eso, sin duplicar ni un solo
  número de la Capa 1: los coeficientes se importan de `phenoage.py` y los
  factores de conversión de unidades se derivan sondeando `to_formula_units()`.
  `tests/test_montecarlo.py` verifica que las dos rutas den el mismo resultado.
"""

from __future__ import annotations

from typing import NamedTuple

import numpy as np

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.evolution import deriva_total
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.nhanes_reference import impute_missing
from app.health_metrics.phenoage import (
    _BA_EXPONENT,
    _BA_INTERCEPT,
    _BA_SCALE,
    _COEF,
    _GAMMA,
    _INTERCEPT,
    _MORTALITY_SCALE,
    to_formula_units,
)

#: Hard ceiling on trajectory count so an authenticated caller can't turn this
#: into a CPU-burning DoS by asking for an arbitrarily large N.
MAX_TRAYECTORIAS = 20_000
MAX_ANIOS = 30

DEFAULT_TRAYECTORIAS = 5000
DEFAULT_ANIOS = 10

#: Cuánto se multiplica el ruido anual de un biomarcador que fue imputado en
#: vez de medido. La spec (§4, §6) pide "ensanchar la incertidumbre" sin dar un
#: número; 2x es una elección de modelado: dice que de un valor inferido de la
#: mediana poblacional sabemos aproximadamente la mitad de lo que sabemos de uno
#: medido en el laboratorio de esta persona. No sale de ninguna publicación.
SIGMA_IMPUTADO_FACTOR = 2.0


# --- PhenoAge vectorizado (misma fórmula que la Capa 1, sin copiar números) ---

#: Nombre de almacenamiento -> nombre en unidades de la fórmula. Solo nombres;
#: todos los factores numéricos se derivan del sondeo de abajo.
_FORMULA_KEY = {
    "albumina": "albumin_gL",
    "creatinina": "creatinine_umol",
    "glucosa": "glucose_mmol",
    "hs_CRP": "ln_crp_mgdL",
    "linfocitos_pct": "lymphocyte_pct",
    "vcm": "mcv_fL",
    "rdw": "rdw_pct",
    "fosfatasa_alcalina": "alp_UL",
    "leucocitos": "wbc_1000uL",
}

#: Todas las conversiones de `to_formula_units` son multiplicativas (g/dL->g/L
#: es x10, mg/dL->umol/L es x88.402, ...) salvo la de hs_CRP, que es un log.
#: Sondear la función con todos los valores en 1.0 devuelve entonces
#: exactamente el factor de cada una — y para hs_CRP, ln(1/10), que es el
#: término aditivo de ln(v/10) = ln(v) + ln(1/10). Así el fast path no repite
#: ni una constante de la Capa 1: si allá cambia una conversión, cambia acá.
_SONDEO = to_formula_units({nombre: 1.0 for nombre in PHENOAGE_BIOMARKERS})
_ESCALA = {
    nombre: _SONDEO[_FORMULA_KEY[nombre]]
    for nombre in PHENOAGE_BIOMARKERS
    if nombre != "hs_CRP"
}
_LN_CRP_OFFSET = _SONDEO["ln_crp_mgdL"]


def _phenoage_vector(state: np.ndarray, edad: float) -> np.ndarray:
    """PhenoAge para las N trayectorias a la vez.

    `state` tiene forma (9, N) con los biomarcadores en el orden de
    `PHENOAGE_BIOMARKERS`, en unidades de almacenamiento. Devuelve N edades
    biológicas. Usa la misma forma numéricamente estable que
    `phenoage.phenoage_years` (salta el score de mortalidad, que satura en 1.0
    y hace explotar el log).
    """
    xb = _INTERCEPT + _COEF["age_years"] * edad
    for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
        coef = _COEF[_FORMULA_KEY[nombre]]
        if nombre == "hs_CRP":
            xb = xb + coef * (np.log(state[i]) + _LN_CRP_OFFSET)
        else:
            xb = xb + coef * (_ESCALA[nombre] * state[i])

    ln_1_menos_mortalidad = (_MORTALITY_SCALE * np.exp(xb)) / _GAMMA
    return np.log(_BA_SCALE * ln_1_menos_mortalidad) / _BA_EXPONENT + _BA_INTERCEPT


# --- La simulación ------------------------------------------------------------


class ScenarioResult(NamedTuple):
    escenario: str
    nombre: str
    #: Percentiles al horizonte (año `anios`). Se conservan como campos planos
    #: porque son lo que la app usa para rankear palancas.
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float
    #: El abanico completo: un valor por año, del 0 al horizonte. `curva_*[-1]`
    #: coincide con los tres campos de arriba.
    curva_anios: list[int]
    curva_p10: list[float]
    curva_mediana: list[float]
    curva_p90: list[float]


def _bounds(nombre: str) -> tuple[float, float]:
    spec = BIOMARKER_SPECS[nombre]
    return spec.valor_min, spec.valor_max


def _sigma(nombre: str, imputados: set[str]) -> float:
    """Ruido anual del biomarcador, ensanchado si el punto de partida fue
    inferido de la tabla de medianas en vez de medido."""
    sd = DYNAMICS[nombre].ruido_anual_sd
    return sd * SIGMA_IMPUTADO_FACTOR if nombre in imputados else sd


def _simulate_scenario(
    valores_iniciales: dict[str, float],
    edad_inicial: float,
    escenario_key: str,
    n_trayectorias: int,
    anios: int,
    rng: np.random.Generator,
    imputados: set[str],
) -> ScenarioResult:
    scenario = SCENARIOS[escenario_key]

    # One row per biomarker, one column per trajectory — evolved together so
    # every trajectory's noise draw is independent of every other trajectory's.
    # dtype=float is load-bearing, not decoration: if every starting value
    # happens to be a whole number numpy infers int64, and then each
    # `state[i] = state[i] + deriva + ruido` silently truncates back to int.
    # The fractional drifts (creatinina +0.005/yr) vanish, hs_CRP walks down
    # to 0 past its own clip floor, and the formula's log(0) takes the
    # endpoint down with a 500.
    state = np.array(
        [[valores_iniciales[nombre]] * n_trayectorias for nombre in PHENOAGE_BIOMARKERS],
        dtype=float,
    )  # shape (9, n_trayectorias)

    # Same drift rule as the deterministic Capa 2 stepper — one source of truth
    # in `evolution`, plus this layer's noise on top. Resolved once per
    # scenario, not once per year: it doesn't depend on the year.
    derivas = [deriva_total(nombre, [escenario_key]) for nombre in PHENOAGE_BIOMARKERS]
    sigmas = [_sigma(nombre, imputados) for nombre in PHENOAGE_BIOMARKERS]

    # (anios + 1, n_trayectorias): la edad biológica de cada trayectoria en
    # cada año, incluido el año 0. Medir antes de evolucionar es lo que hace
    # que la fila 0 sea el estado de partida y no un año ya derivado.
    edades = np.empty((anios + 1, n_trayectorias))
    for t in range(anios + 1):
        edades[t] = _phenoage_vector(state, edad_inicial + t)
        if t == anios:
            break

        for i in range(len(PHENOAGE_BIOMARKERS)):
            ruido = rng.normal(0.0, sigmas[i], size=n_trayectorias)
            state[i] = state[i] + derivas[i] + ruido

        # Clamp after each year, not just at the end: an unclamped random walk
        # can wander a biomarker (e.g. leucocitos) negative mid-simulation and
        # never recover, which would poison every later year for that path.
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            state[i] = np.clip(state[i], *_bounds(nombre))

    p10, mediana, p90 = np.percentile(edades, [10, 50, 90], axis=1)
    return ScenarioResult(
        escenario=escenario_key,
        nombre=scenario.nombre,
        edad_biologica_p10=float(p10[-1]),
        edad_biologica_mediana=float(mediana[-1]),
        edad_biologica_p90=float(p90[-1]),
        curva_anios=list(range(anios + 1)),
        curva_p10=[float(v) for v in p10],
        curva_mediana=[float(v) for v in mediana],
        curva_p90=[float(v) for v in p90],
    )


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
    the list of biomarkers that had to be imputed to get a starting point —
    which is also what widens the band, see `SIGMA_IMPUTADO_FACTOR`."""
    valores_iniciales, imputados = impute_missing(biomarcadores, edad, sexo_biologico)

    n = min(n_trayectorias, MAX_TRAYECTORIAS)
    a = min(anios, MAX_ANIOS)
    rng = np.random.default_rng(seed)

    resultados = [
        _simulate_scenario(valores_iniciales, edad, key, n, a, rng, set(imputados))
        for key in escenarios
    ]
    return resultados, imputados
