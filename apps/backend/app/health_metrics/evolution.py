"""Capa 2 — motor de evolución (MOIRAI_ENGINE_SPEC.md §5).

La regla es una sola: dado el estado de los biomarcadores en el año `t` y las
intervenciones activas, produce el estado en `t+1`. Aplicada 10 veces da una
trayectoria de 10 años. Esto es lo que *predice*; la Capa 1 (`phenoage.py`)
solo mide el presente y la Capa 3 (`montecarlo.py`) solo le añade ruido.

Por qué existe este módulo por separado: la regla estaba escrita inline dentro
del bucle vectorizado de `montecarlo.py`, lo que hacía imposible correr el test
de signos de §5 —que exige comparar dos trayectorias *deterministas*— sin
mirarlo a través de 5.000 corridas con ruido. Ahora `deriva_total()` es la
única fuente de verdad de la regla y la usan las dos capas: el paso
determinista de acá y el paso con ruido de la Capa 3.

Los coeficientes viven en `interventions.py`, cada uno anotado con el estudio
del que sale. Son aproximados y derivados de literatura, NO del paper de
PhenoAge.
"""

from __future__ import annotations

from collections.abc import Iterable

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.phenoage import phenoage_years, to_formula_units


def deriva_total(nombre: str, escenarios: Iterable[str]) -> float:
    """Cambio anual de un biomarcador: su deriva natural por edad más el
    modificador de cada intervención activa.

    Los efectos de varias intervenciones se **suman**. Es la convención de la
    spec §5 y es una simplificación conocida: dos palancas que actúan sobre la
    misma vía inflamatoria no suman sus beneficios en la realidad. Por eso el
    escenario `combinada` de `interventions.py` trae su propio efecto
    sublineal en vez de armarse sumando sus tres partes.
    """
    cambio = DYNAMICS[nombre].deriva_anual
    for key in escenarios:
        cambio += SCENARIOS[key].efectos_anuales.get(nombre, 0.0)
    return cambio


def _clamp(nombre: str, valor: float) -> float:
    spec = BIOMARKER_SPECS[nombre]
    return min(max(valor, spec.valor_min), spec.valor_max)


def evolucionar_un_paso(
    estado: dict[str, float], escenarios: Iterable[str] = ()
) -> dict[str, float]:
    """estado(t) + intervenciones -> estado(t+1). La regla de §5.

    Acota cada valor a los límites clínicos de `BIOMARKER_SPECS` en cada paso,
    igual que hace la Capa 3: sin eso una deriva sostenida a 10 o 30 años
    empuja biomarcadores fuera de todo rango fisiológico y, en el caso de
    hs_CRP, hasta cero — donde el log de la Capa 1 deja de estar definido.
    """
    escenarios = list(escenarios)
    return {
        nombre: _clamp(nombre, valor + deriva_total(nombre, escenarios))
        for nombre, valor in estado.items()
    }


def trayectoria_estados(
    estado0: dict[str, float], escenarios: Iterable[str] = (), anios: int = 10
) -> list[dict[str, float]]:
    """Los `anios + 1` estados de biomarcadores, del año 0 al año `anios`."""
    escenarios = list(escenarios)
    estados = [dict(estado0)]
    for _ in range(anios):
        estados.append(evolucionar_un_paso(estados[-1], escenarios))
    return estados


def trayectoria_deterministica(
    estado0: dict[str, float],
    escenarios: Iterable[str] = (),
    edad0: float = 0.0,
    anios: int = 10,
) -> list[float]:
    """Edad biológica año por año, sin ruido — la firma de §5.

    Es la curva que hoy la app aproxima en local (ver API_CONTRACT.md) porque
    `/montecarlo` solo devuelve percentiles al horizonte. Ojo con el eje: en
    cada año la Capa 1 se evalúa con la edad *cronológica* de ese año
    (`edad0 + i`), no con la inicial — PhenoAge lleva la edad cronológica como
    predictor, así que dejarla fija aplanaría artificialmente la curva.
    """
    return [
        phenoage_years(to_formula_units(estado), edad0 + i)
        for i, estado in enumerate(trayectoria_estados(estado0, escenarios, anios))
    ]


def anios_ganados(
    estado0: dict[str, float],
    escenarios: Iterable[str],
    edad0: float,
    anios: int = 10,
) -> float:
    """Cuánta edad biológica se ahorra al horizonte frente a no hacer nada.

    Positivo = la intervención deja a la persona biológicamente más joven que
    la línea base. Determinista: mismo punto de partida, misma aritmética, la
    única variable que cambia son las intervenciones — el "detalle pareado"
    que pide la pantalla D de los mockups.
    """
    base = trayectoria_deterministica(estado0, [], edad0, anios)[-1]
    con = trayectoria_deterministica(estado0, escenarios, edad0, anios)[-1]
    return base - con


assert set(DYNAMICS) == set(PHENOAGE_BIOMARKERS)
