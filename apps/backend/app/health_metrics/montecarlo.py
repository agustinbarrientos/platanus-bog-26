"""Capa 3 — Monte Carlo (MOIRAI_ENGINE_SPEC.md §6): correr la Capa 2 N veces
con ruido biológico y devolver el abanico de futuros.

Qué hace, y por qué así:

- **Ruido año a año** (`DYNAMICS[...].ruido_anual_sd`) sobre cada biomarcador,
  nuevo cada año simulado: es lo que convierte una predicción puntual en una
  distribución de futuros plausibles.
- **Incertidumbre de arranque para lo imputado**: un biomarcador NO medido no
  se fija en la mediana — se muestrea de la dispersión poblacional de su grupo
  de edad y sexo (`nhanes_reference.DISPERSION`). Es lo que la spec exige
  ("biomarcadores imputados ⇒ más sigma ⇒ banda más ancha") y lo que hace
  verdad la promesa de la app de que medir angosta el rango.
- **Futuros pareados**: todos los escenarios usan exactamente los mismos
  arranques muestreados y los mismos ruidos (misma semilla, mismo orden), así
  que "la misma vida" se puede comparar con y sin la palanca. Los años ganados
  son la distribución de esa diferencia trayectoria a trayectoria — su mediana,
  su P10–P90 y el porcentaje de futuros en que la palanca termina mejor.
- **Curva por año**: PhenoAge se evalúa en cada año de cada trayectoria
  (vectorizado, `phenoage_years_vector`), así que la banda P10–P90 sale año a
  año en vez de interpolarse en la app.
- **Valor de información**: para cada biomarcador imputado, cuánto se
  angostaría la banda de la línea base si estuviera medido (misma semilla, ese
  biomarcador fijo en la mediana).

Lo que NO hace (spec §12): SHAP sobre las trayectorias, más de 3 palancas.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import NamedTuple

import numpy as np

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.evolution import (
    ajuste_habitos,
    contribuciones_habitos,
    deriva_natural,
    efectos_palancas,
    factor_combinacion,
)
from app.health_metrics.interventions import (
    DYNAMICS,
    EFECTO_RELATIVO_A,
    HETEROGENEIDAD_RESPUESTA,
    PALANCAS,
    aplica,
    esfuerzo_de,
    etiqueta_de,
    expandir,
)
from app.health_metrics.nhanes_reference import impute_missing, sample_reference
from app.health_metrics.phenoage import phenoage_years_vector

#: Hard ceiling on trajectory count so an authenticated caller can't turn this
#: into a CPU-burning DoS by asking for an arbitrarily large N.
MAX_TRAYECTORIAS = 20_000
MAX_ANIOS = 30

DEFAULT_TRAYECTORIAS = 10_000
DEFAULT_ANIOS = 10
#: Semilla por defecto: el mismo input da el mismo abanico (reproducible en un
#: demo y entre escenarios). El caller puede pasar otra.
DEFAULT_SEED = 20260822
#: Cuántas trayectorias de la línea base se devuelven para dibujar.
MUESTRA_TRAYECTORIAS = 40

Brechas = Mapping[str, float | None]

class ScenarioResult(NamedTuple):
    escenario: str
    nombre: str
    intervenciones: tuple[str, ...]
    esfuerzo: int
    #: False cuando ninguna de sus palancas tiene brecha abierta para esta
    #: persona (ya tiene el hábito): el escenario colapsa sobre la línea base.
    aplica: bool
    # Al horizonte (compatibilidad con la forma anterior del endpoint).
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float
    # Año a año, del 0 al horizonte.
    curva_anios: list[int]
    curva_p10: list[float]
    curva_mediana: list[float]
    curva_p90: list[float]
    # Diferencia pareada frente a la línea base, trayectoria a trayectoria.
    anios_ganados: float
    anios_ganados_p10: float
    anios_ganados_p90: float
    pct_futuros_que_mejoran: float
    ratio_impacto_esfuerzo: float


class ValorDeInformacion(NamedTuple):
    nombre: str
    #: Cuánto se angosta (años) la banda P10–P90 de la línea base al horizonte
    #: si este biomarcador imputado estuviera medido.
    reduccion_banda_anios: float
    #: Parte de la reducción total que aporta este biomarcador (suma 1).
    fraccion: float


class MontecarloResult(NamedTuple):
    escenarios: list[ScenarioResult]
    campos_inferidos: list[str]
    muestra_trayectorias: list[list[float]]
    valor_de_informacion: list[ValorDeInformacion]
    contribuciones_habitos: list[dict[str, object]]
    semilla: int
    n_trayectorias: int
    anios: int
    #: P90 − P10 de la edad biológica HOY (año 0): 0 si los 9 están medidos;
    #: la incertidumbre de lo imputado si no.
    ancho_banda_hoy: float


def _bounds(nombre: str) -> tuple[float, float]:
    spec = BIOMARKER_SPECS[nombre]
    return spec.valor_min, spec.valor_max


def _phenoage(state: np.ndarray, edad: float) -> np.ndarray:
    return phenoage_years_vector(
        {nombre: state[i] for i, nombre in enumerate(PHENOAGE_BIOMARKERS)}, edad
    )


def _trayectorias(
    start: np.ndarray,
    ruido: np.ndarray,
    respuesta: Mapping[str, np.ndarray],
    edad_inicial: float,
    escenario: str,
    brechas: Brechas | None,
    anios: int,
) -> np.ndarray:
    """PhenoAge de cada trayectoria en cada año: forma (anios + 1, n).

    `start` (9, n) es el estado de arranque (medidos fijos, imputados
    muestreados); `ruido` (anios, 9, n) los choques anuales, ya escalados por
    `ruido_anual_sd`; `respuesta[palanca]` (n,) el multiplicador de respuesta
    individual a cada palanca. Los tres se comparten entre escenarios: eso es
    lo que deja las trayectorias pareadas.
    """
    state = start.copy()
    n = start.shape[1]
    out = np.empty((anios + 1, n))
    out[0] = _phenoage(state, edad_inicial)
    # Same drift rule as the deterministic Capa 2 stepper — one source of
    # truth in `evolution` (`deriva_natural` + `ajuste_habitos` +
    # `efectos_palancas` × `factor_combinacion`, × `escala` for the relative
    # biomarkers), plus this layer's noise and per-trajectory response
    # multiplier on top.
    naturales: list[float] = []
    relativas: list[np.ndarray] = []  # parte que se escala al valor actual (PCR)
    for nombre in PHENOAGE_BIOMARKERS:
        rel = np.full(n, ajuste_habitos(nombre, brechas))
        efectos = efectos_palancas(nombre, [escenario], brechas)
        if efectos:
            factor = factor_combinacion(len(efectos))
            for palanca, efecto in efectos:
                rel = rel + respuesta[palanca] * (efecto * factor)
        naturales.append(deriva_natural(nombre))
        relativas.append(rel)
    for year in range(anios):
        for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
            if nombre in EFECTO_RELATIVO_A:
                state[i] += naturales[i] + relativas[i] * (state[i] / EFECTO_RELATIVO_A[nombre]) + ruido[year, i]
            else:
                state[i] += naturales[i] + relativas[i] + ruido[year, i]
            # Clamp after each year, not just at the end: an unclamped random
            # walk can wander a biomarker (e.g. leucocitos) negative
            # mid-simulation and never recover, which would poison every later
            # year for that path.
            np.clip(state[i], *_bounds(nombre), out=state[i])
        out[year + 1] = _phenoage(state, edad_inicial + year + 1)
    return out


def _percentiles(matriz: np.ndarray) -> tuple[list[float], list[float], list[float]]:
    p10, p50, p90 = np.percentile(matriz, [10, 50, 90], axis=1)
    return p10.tolist(), p50.tolist(), p90.tolist()


def simular(
    biomarcadores: dict[str, float],
    edad: float,
    sexo_biologico: str | None,
    escenarios: Iterable[str],
    n_trayectorias: int = DEFAULT_TRAYECTORIAS,
    anios: int = DEFAULT_ANIOS,
    seed: int | None = None,
    brechas: Brechas | None = None,
    muestra: int = MUESTRA_TRAYECTORIAS,
    valor_de_informacion: bool = True,
) -> MontecarloResult:
    """Run every scenario in `escenarios` from the same starting point and the
    same noise, so they are directly comparable trajectory by trajectory.

    `brechas` (ver `interventions.brechas_desde_habitos`) es lo que hace al
    gemelo personal: hábitos actuales en la línea base y palancas escaladas
    por la brecha que les queda. `None` = modo legado sin hábitos.
    """
    escenarios = list(escenarios)
    for key in escenarios:
        expandir(key)  # ValueError temprano si alguna clave no es válida
    valores_iniciales, imputados = impute_missing(biomarcadores, edad, sexo_biologico)

    n = min(n_trayectorias, MAX_TRAYECTORIAS)
    a = min(anios, MAX_ANIOS)
    semilla = DEFAULT_SEED if seed is None else int(seed)
    rng = np.random.default_rng(semilla)

    # Estado de arranque: una columna por trayectoria. dtype float es
    # deliberado (con enteros numpy truncaría las derivas fraccionarias).
    start = np.empty((len(PHENOAGE_BIOMARKERS), n), dtype=float)
    for i, nombre in enumerate(PHENOAGE_BIOMARKERS):
        if nombre in imputados:
            muestras = sample_reference(nombre, valores_iniciales[nombre], rng, n)
            start[i] = np.clip(muestras, *_bounds(nombre))
        else:
            start[i] = float(valores_iniciales[nombre])
    sds = np.array([DYNAMICS[nombre].ruido_anual_sd for nombre in PHENOAGE_BIOMARKERS])
    ruido = rng.normal(0.0, 1.0, size=(a, len(PHENOAGE_BIOMARKERS), n)) * sds[None, :, None]
    # Respuesta individual a cada palanca (una por trayectoria, compartida por
    # todos los escenarios que la incluyan): N(1, HETEROGENEIDAD) truncada en 0.
    respuesta = {
        palanca: np.clip(rng.normal(1.0, HETEROGENEIDAD_RESPUESTA, size=n), 0.0, None)
        for palanca in PALANCAS
    }

    base = _trayectorias(start, ruido, respuesta, edad, "ninguna", brechas, a)
    base_final = base[-1]
    anios_lista = list(range(a + 1))

    resultados: list[ScenarioResult] = []
    for key in escenarios:
        m = base if key == "ninguna" else _trayectorias(start, ruido, respuesta, edad, key, brechas, a)
        p10, p50, p90 = _percentiles(m)
        delta = base_final - m[-1]
        if key == "ninguna":
            g_p10 = g_p50 = g_p90 = 0.0
            pct = 0.0
        else:
            g_p10, g_p50, g_p90 = (float(x) for x in np.percentile(delta, [10, 50, 90]))
            pct = float(np.mean(delta > 0.0) * 100.0)
        esfuerzo = esfuerzo_de(key)
        resultados.append(
            ScenarioResult(
                escenario=key,
                nombre=etiqueta_de(key),
                intervenciones=expandir(key),
                esfuerzo=esfuerzo,
                aplica=aplica(key, brechas),
                edad_biologica_p10=p10[-1],
                edad_biologica_mediana=p50[-1],
                edad_biologica_p90=p90[-1],
                curva_anios=anios_lista,
                curva_p10=p10,
                curva_mediana=p50,
                curva_p90=p90,
                anios_ganados=g_p50,
                anios_ganados_p10=g_p10,
                anios_ganados_p90=g_p90,
                pct_futuros_que_mejoran=pct,
                ratio_impacto_esfuerzo=(g_p50 / esfuerzo) if esfuerzo else 0.0,
            )
        )

    # Valor de información: la banda de la línea base si cada imputado
    # estuviera medido (fijo en su mediana), con la MISMA semilla.
    voi: list[ValorDeInformacion] = []
    if valor_de_informacion and imputados:
        ancho_todo = float(np.percentile(base_final, 90) - np.percentile(base_final, 10))
        reducciones: list[tuple[str, float]] = []
        for nombre in imputados:
            fijo = start.copy()
            fijo[PHENOAGE_BIOMARKERS.index(nombre)] = float(valores_iniciales[nombre])
            final = _trayectorias(fijo, ruido, respuesta, edad, "ninguna", brechas, a)[-1]
            ancho = float(np.percentile(final, 90) - np.percentile(final, 10))
            reducciones.append((nombre, max(0.0, ancho_todo - ancho)))
        total = sum(r for _, r in reducciones)
        voi = sorted(
            (
                ValorDeInformacion(nombre, red, (red / total) if total > 0 else 0.0)
                for nombre, red in reducciones
            ),
            key=lambda v: v.reduccion_banda_anios,
            reverse=True,
        )

    hoy_p10, hoy_p90 = np.percentile(base[0], [10, 90])
    return MontecarloResult(
        escenarios=resultados,
        campos_inferidos=imputados,
        muestra_trayectorias=base[:, : max(0, min(muestra, n))].T.tolist(),
        valor_de_informacion=voi,
        contribuciones_habitos=contribuciones_habitos(valores_iniciales, edad, brechas, a),
        semilla=semilla,
        n_trayectorias=n,
        anios=a,
        ancho_banda_hoy=float(hoy_p90 - hoy_p10),
    )


def run(
    biomarcadores: dict[str, float],
    edad: float,
    sexo_biologico: str | None,
    escenarios: list[str],
    n_trayectorias: int = DEFAULT_TRAYECTORIAS,
    anios: int = DEFAULT_ANIOS,
    seed: int | None = None,
    brechas: Brechas | None = None,
) -> tuple[list[ScenarioResult], list[str]]:
    """Compatibilidad: la firma anterior. Devuelve (resultados por escenario,
    biomarcadores imputados). `simular()` trae además curvas, muestra, valor
    de información y contribuciones de hábitos."""
    r = simular(
        biomarcadores, edad, sexo_biologico, escenarios, n_trayectorias, anios, seed, brechas,
        valor_de_informacion=False,
    )
    return r.escenarios, r.campos_inferidos
