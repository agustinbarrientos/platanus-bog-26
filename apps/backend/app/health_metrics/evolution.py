"""Capa 2 — motor de evolución (MOIRAI_ENGINE_SPEC.md §5).

La regla es una sola: dado el estado de los biomarcadores en el año `t`, los
hábitos actuales de la persona y las intervenciones activas, produce el estado
en `t+1`. Aplicada 10 veces da una trayectoria de 10 años. Esto es lo que
*predice*; la Capa 1 (`phenoage.py`) solo mide el presente y la Capa 3
(`montecarlo.py`) solo le añade ruido.

Por qué existe este módulo por separado: la regla estaba escrita inline dentro
del bucle vectorizado de `montecarlo.py`, lo que hacía imposible correr el test
de signos de §5 —que exige comparar dos trayectorias *deterministas*— sin
mirarlo a través de 5.000 corridas con ruido. `deriva_total()` es la única
fuente de verdad de la regla y la usan las dos capas: el paso determinista de
acá y el paso con ruido de la Capa 3 (que la descompone con
`deriva_natural` / `ajuste_habitos` / `efectos_palancas` / `factor_combinacion`
/ `escala` para poder vectorizar y aplicar el multiplicador de respuesta).

Los coeficientes viven en `interventions.py`, cada uno anotado con el estudio
del que sale. Son aproximados y derivados de literatura, NO del paper de
PhenoAge. Ahí también está explicado cómo entran los hábitos (brechas y
descomposición de mezcla) y por qué los efectos sobre la PCR son relativos al
valor actual; acá solo se aplica.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import (
    DESCUENTO_COMBINACION,
    DYNAMICS,
    EFECTO_RELATIVO_A,
    PALANCAS,
    SCENARIOS,
    brecha_efectiva,
    palancas_de,
)
from app.health_metrics.phenoage import phenoage_years, to_formula_units

Brechas = Mapping[str, float | None]


def deriva_natural(nombre: str) -> float:
    """Deriva anual por edad sola (`DYNAMICS`), en unidades de almacenamiento."""
    return DYNAMICS[nombre].deriva_anual


def escala(nombre: str, valor: float | None) -> float:
    """Factor por el que se multiplican los efectos de palanca/hábito sobre
    `nombre`: 1 salvo para los biomarcadores de `EFECTO_RELATIVO_A`, donde es
    valor actual / valor de referencia (efecto proporcional). Sin `valor`
    (p. ej. al inspeccionar coeficientes) se devuelve 1: el efecto a la
    referencia."""
    ref = EFECTO_RELATIVO_A.get(nombre)
    if ref is None or valor is None:
        return 1.0
    return float(valor) / ref


def ajuste_por_habito(nombre: str, palanca: str, brecha: float) -> float:
    """Cuánto mueve la deriva de `nombre` (a escala de referencia) el hábito
    ACTUAL que cierra `palanca`, dada la brecha conocida de la persona (0–1):
    `(brecha − brecha_promedio) · |efecto|` en la dirección adversa. Positivo
    (o en la dirección adversa del biomarcador) = la persona envejece más rápido
    que la población en ese biomarcador; negativo = más lento. El ajuste
    favorable se acota a como mucho neutralizar la deriva por edad."""
    sc = SCENARIOS[palanca]
    efecto = sc.efectos_anuales.get(nombre, 0.0)
    if efecto == 0.0:
        return 0.0
    ajuste = (brecha - sc.brecha_promedio) * (-efecto)
    if brecha < sc.brecha_promedio:
        deriva = deriva_natural(nombre)
        if deriva == 0.0:
            return 0.0
        # El "bono" va siempre contra la deriva adversa; nunca más allá de cero.
        if abs(ajuste) > abs(deriva) and ajuste * deriva < 0:
            ajuste = -deriva
    return ajuste


def ajuste_habitos(nombre: str, brechas: Brechas | None) -> float:
    """Suma de `ajuste_por_habito` sobre todos los hábitos REGISTRADOS (a
    escala de referencia). 0 en modo legado (`brechas=None`) y para hábitos
    desconocidos."""
    if brechas is None:
        return 0.0
    total = 0.0
    for palanca in PALANCAS:
        habito = SCENARIOS[palanca].habito
        if habito is None:
            continue
        g = brechas.get(habito)
        if g is None:
            continue
        total += ajuste_por_habito(nombre, palanca, float(g))
    return total


def deriva_base(nombre: str, brechas: Brechas | None = None, valor: float | None = None) -> float:
    """Deriva anual de un biomarcador SIN intervenciones: la natural por edad
    más el ajuste por los hábitos ACTUALES de la persona (escalado al valor
    actual si el biomarcador es relativo). `brechas=None` es el modo legado:
    solo la deriva poblacional."""
    return deriva_natural(nombre) + ajuste_habitos(nombre, brechas) * escala(nombre, valor)


def efectos_palancas(
    nombre: str, escenarios: Iterable[str], brechas: Brechas | None = None
) -> list[tuple[str, float]]:
    """Efecto anual a escala de referencia (ya escalado por la brecha que le
    queda a la persona) de cada palanca activa que toca `nombre`:
    `[(palanca, efecto), ...]`. Vacío si ninguna lo toca. Sin el descuento de
    combinación ni la escala al valor actual — eso lo ponen
    `combinar_efectos`/`escala`, porque la Capa 3 necesita aplicar antes el
    multiplicador de respuesta de cada palanca."""
    out: list[tuple[str, float]] = []
    for palanca in palancas_de(escenarios):
        efecto = SCENARIOS[palanca].efectos_anuales.get(nombre, 0.0)
        if efecto == 0.0:
            continue
        g = brecha_efectiva(brechas, SCENARIOS[palanca].habito)
        if g == 0.0:
            continue
        out.append((palanca, g * efecto))
    return out


def factor_combinacion(n_palancas: int) -> float:
    """Descuento de sublinealidad cuando `n_palancas` tocan el mismo
    biomarcador: 1 → ×1; 2 → ×0,92; 3 → ×0,84 (`DESCUENTO_COMBINACION`)."""
    return 1.0 - DESCUENTO_COMBINACION * max(0, n_palancas - 1)


def combinar_efectos(efectos: Iterable[float]) -> float:
    efectos = list(efectos)
    if not efectos:
        return 0.0
    return sum(efectos) * factor_combinacion(len(efectos))


def deriva_total(
    nombre: str,
    escenarios: Iterable[str],
    brechas: Brechas | None = None,
    valor: float | None = None,
) -> float:
    """Cambio anual de un biomarcador: su deriva natural por edad, más el
    ajuste por los hábitos ACTUALES de la persona (si se conocen), más el
    efecto de cada intervención activa escalado por la brecha que le queda;
    para los biomarcadores relativos (`EFECTO_RELATIVO_A`, la PCR) esas dos
    últimas partes se escalan al `valor` actual.

    `escenarios` admite claves simples (`"ejercicio_aerobico"`), compuestas
    (`"ejercicio_aerobico+sueno_8h"`, `"combinada"`) o una lista de ellas.
    Los efectos de varias palancas sobre el MISMO biomarcador se suman con el
    descuento de sublinealidad de `interventions.DESCUENTO_COMBINACION` (dos
    palancas que actúan sobre la misma vía inflamatoria no suman sus
    beneficios en la realidad).

    `brechas=None` es el modo legado (sin hábitos): efectos completos, línea
    base poblacional. Es lo que usan los tests de signos de la spec.
    """
    relativo = ajuste_habitos(nombre, brechas) + combinar_efectos(
        efecto for _, efecto in efectos_palancas(nombre, escenarios, brechas)
    )
    return deriva_natural(nombre) + relativo * escala(nombre, valor)


def _clamp(nombre: str, valor: float) -> float:
    spec = BIOMARKER_SPECS[nombre]
    return min(max(valor, spec.valor_min), spec.valor_max)


def evolucionar_un_paso(
    estado: dict[str, float], escenarios: Iterable[str] = (), brechas: Brechas | None = None
) -> dict[str, float]:
    """estado(t) + hábitos + intervenciones -> estado(t+1). La regla de §5.

    Acota cada valor a los límites clínicos de `BIOMARKER_SPECS` en cada paso,
    igual que hace la Capa 3: sin eso una deriva sostenida a 10 o 30 años
    empuja biomarcadores fuera de todo rango fisiológico y, en el caso de
    hs_CRP, hasta cero — donde el log de la Capa 1 deja de estar definido.
    """
    escenarios = list(escenarios)
    return {
        nombre: _clamp(nombre, valor + deriva_total(nombre, escenarios, brechas, valor))
        for nombre, valor in estado.items()
    }


def trayectoria_estados(
    estado0: dict[str, float],
    escenarios: Iterable[str] = (),
    anios: int = 10,
    brechas: Brechas | None = None,
) -> list[dict[str, float]]:
    """Los `anios + 1` estados de biomarcadores, del año 0 al año `anios`."""
    escenarios = list(escenarios)
    estados = [dict(estado0)]
    for _ in range(anios):
        estados.append(evolucionar_un_paso(estados[-1], escenarios, brechas))
    return estados


def trayectoria_deterministica(
    estado0: dict[str, float],
    escenarios: Iterable[str] = (),
    edad0: float = 0.0,
    anios: int = 10,
    brechas: Brechas | None = None,
) -> list[float]:
    """Edad biológica año por año, sin ruido — la firma de §5.

    Ojo con el eje: en cada año la Capa 1 se evalúa con la edad *cronológica*
    de ese año (`edad0 + i`), no con la inicial — PhenoAge lleva la edad
    cronológica como predictor, así que dejarla fija aplanaría artificialmente
    la curva.
    """
    return [
        phenoage_years(to_formula_units(estado), edad0 + i)
        for i, estado in enumerate(trayectoria_estados(estado0, escenarios, anios, brechas))
    ]


def anios_ganados(
    estado0: dict[str, float],
    escenarios: Iterable[str],
    edad0: float,
    anios: int = 10,
    brechas: Brechas | None = None,
) -> float:
    """Cuánta edad biológica se ahorra al horizonte frente a no hacer nada.

    Positivo = la intervención deja a la persona biológicamente más joven que
    la línea base. Determinista: mismo punto de partida, misma aritmética, la
    única variable que cambia son las intervenciones — el "detalle pareado"
    que pide la pantalla D de los mockups.
    """
    base = trayectoria_deterministica(estado0, [], edad0, anios, brechas)[-1]
    con = trayectoria_deterministica(estado0, escenarios, edad0, anios, brechas)[-1]
    return base - con


def contribuciones_habitos(
    estado0: dict[str, float], edad0: float, brechas: Brechas | None, anios: int = 10
) -> list[dict[str, object]]:
    """El "por qué" de los hábitos, a `anios` años y determinista: para cada
    hábito REGISTRADO, cuántos años de edad biológica le cuesta tenerlo (brecha
    abierta: edad biológica con su brecha actual menos con la brecha cerrada,
    ≥ 0, `empeora`) o cuántos le está ahorrando tenerlo bueno (brecha 0: edad
    biológica si tuviera el hábito malo menos la actual, como negativo,
    `mejora`). Es el mismo cálculo que los años ganados de la palanca, mirado
    desde el hábito — por eso un buen hábito también aparece en el resultado
    en vez de ser invisible."""
    if not brechas:
        return []
    out: list[dict[str, object]] = []
    actual = trayectoria_deterministica(estado0, [], edad0, anios, brechas)[-1]
    for palanca in PALANCAS:
        habito = SCENARIOS[palanca].habito
        if habito is None or brechas.get(habito) is None:
            continue
        g = float(brechas[habito])  # type: ignore[arg-type]
        if g > 0.0:
            cerrada = dict(brechas)
            cerrada[habito] = 0.0
            contrib = actual - trayectoria_deterministica(estado0, [], edad0, anios, cerrada)[-1]
        else:
            abierta = dict(brechas)
            abierta[habito] = 1.0
            contrib = -(trayectoria_deterministica(estado0, [], edad0, anios, abierta)[-1] - actual)
        out.append(
            {
                "habito": habito,
                "palanca": palanca,
                "brecha": g,
                "contribucion": contrib,
                "direccion": "empeora" if contrib > 0 else "mejora",
            }
        )
    return out


assert set(DYNAMICS) == set(PHENOAGE_BIOMARKERS)
