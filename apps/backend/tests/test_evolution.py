"""Capa 2 del motor (MOIRAI_ENGINE_SPEC.md §5): la regla de deriva.

El test que manda la spec es el de signos: *"Una trayectoria sin intervención
debe envejecer más rápido que una con buenas intervenciones. Si dormir 8h no
mejora nada, hay error de signo."* Está en `test_sin_intervencion_envejece_mas_rapido`
y en `test_dormir_8h_mejora_de_verdad`.

Los coeficientes de esta capa son aproximados y derivados de literatura, no del
paper de PhenoAge — ver la advertencia de procedencia en `interventions.py`.
Por eso acá no se verifica ningún valor contra una fuente externa: se verifica
que los **signos** vayan en la dirección correcta, que el **acumulado a 10
años** caiga dentro del rango de efecto que reportan los ensayos citados, y que
la deriva base sea coherente con la tabla de medianas del propio motor.
"""

from __future__ import annotations

import pytest

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.evolution import (
    anios_ganados,
    deriva_total,
    evolucionar_un_paso,
    trayectoria_deterministica,
    trayectoria_estados,
)
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.nhanes_reference import _MEDIANS

#: El perfil de la spec §9, con los 3 imputados ya resueltos.
ESTADO_SPEC_9 = {
    "albumina": 4.4,
    "creatinina": 0.8,
    "glucosa": 92.0,
    "hs_CRP": 2.1,
    "rdw": 13.1,
    "leucocitos": 6.2,
    "linfocitos_pct": 30.0,
    "vcm": 90.0,
    "fosfatasa_alcalina": 70.0,
}
EDAD_SPEC_9 = 34.0

PALANCAS = [key for key in SCENARIOS if key != "ninguna"]


# --- El test de signos de §5 --------------------------------------------------


def test_sin_intervencion_envejece_mas_rapido():
    """EL test de la spec §5. Misma persona, mismo punto de partida, misma
    aritmética; la única variable que cambia son las intervenciones."""
    base = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10)
    buena = trayectoria_deterministica(ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9, 10)

    # Parten del mismo estado -> año 0 idéntico.
    assert base[0] == pytest.approx(buena[0])
    # Y al horizonte la línea base quedó biológicamente más vieja.
    assert base[-1] > buena[-1]
    # No solo al final: envejece más rápido en cada año a partir del primero.
    for año in range(1, 11):
        assert base[año] > buena[año], f"año {año}: {base[año]} !> {buena[año]}"


def test_dormir_8h_mejora_de_verdad():
    """Textual de la spec: "si dormir 8h no mejora nada, hay error de signo"."""
    base = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10)[-1]
    durmiendo = trayectoria_deterministica(
        ESTADO_SPEC_9, ["sueno_8h"], EDAD_SPEC_9, 10
    )[-1]
    assert durmiendo < base
    assert anios_ganados(ESTADO_SPEC_9, ["sueno_8h"], EDAD_SPEC_9) > 0


@pytest.mark.parametrize("palanca", PALANCAS)
def test_cada_palanca_gana_anios(palanca):
    """Ninguna de las palancas puede empeorar la trayectoria. Un signo
    invertido en un solo biomarcador de `interventions.py` haría que el motor
    recomendara exactamente lo contrario de lo que debería."""
    assert anios_ganados(ESTADO_SPEC_9, [palanca], EDAD_SPEC_9) > 0


def test_la_linea_base_envejece():
    """Sin hacer nada la edad biológica sube año a año: la deriva natural más
    la edad cronológica que entra como predictor en la Capa 1."""
    base = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10)
    assert all(b < a for b, a in zip(base, base[1:]))
    assert base[-1] > base[0]


def test_combinada_gana_mas_que_cualquiera_de_sus_partes():
    combinada = anios_ganados(ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9)
    for parte in ("ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco"):
        assert combinada > anios_ganados(ESTADO_SPEC_9, [parte], EDAD_SPEC_9)


def test_combinada_es_sublineal_frente_a_sumar_sus_partes():
    """Decisión de modelado documentada en `interventions.py`, anclada acá: el
    escenario precocinado es deliberadamente MENOS bueno que apilar las tres
    palancas por separado, porque actúan sobre vías que se solapan."""
    partes = ["ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco"]
    suma_lineal = anios_ganados(ESTADO_SPEC_9, partes, EDAD_SPEC_9)
    precocinada = anios_ganados(ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9)
    assert precocinada < suma_lineal


# --- La regla de deriva -------------------------------------------------------


def test_deriva_total_suma_base_mas_efectos():
    base = DYNAMICS["hs_CRP"].deriva_anual
    efecto = SCENARIOS["ejercicio_aerobico"].efectos_anuales["hs_CRP"]
    assert deriva_total("hs_CRP", []) == pytest.approx(base)
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"]) == pytest.approx(base + efecto)


def test_deriva_total_acumula_varias_intervenciones():
    """Los efectos de varias palancas se suman (convención de §5)."""
    esperado = (
        DYNAMICS["hs_CRP"].deriva_anual
        + SCENARIOS["sueno_8h"].efectos_anuales["hs_CRP"]
        + SCENARIOS["reducir_estres"].efectos_anuales["hs_CRP"]
    )
    assert deriva_total("hs_CRP", ["sueno_8h", "reducir_estres"]) == pytest.approx(esperado)


def test_escenario_ninguna_no_mueve_nada():
    assert deriva_total("glucosa", ["ninguna"]) == pytest.approx(
        deriva_total("glucosa", [])
    )


def test_un_paso_avanza_exactamente_una_deriva():
    siguiente = evolucionar_un_paso(ESTADO_SPEC_9, ["ejercicio_aerobico"])
    for nombre, valor in ESTADO_SPEC_9.items():
        esperado = valor + deriva_total(nombre, ["ejercicio_aerobico"])
        assert siguiente[nombre] == pytest.approx(esperado)


def test_trayectoria_tiene_anios_mas_uno_estados():
    for anios in (1, 10, 30):
        assert len(trayectoria_estados(ESTADO_SPEC_9, [], anios)) == anios + 1
        assert len(trayectoria_deterministica(ESTADO_SPEC_9, [], 40, anios)) == anios + 1


def test_el_estado_inicial_no_se_muta():
    copia = dict(ESTADO_SPEC_9)
    trayectoria_estados(ESTADO_SPEC_9, ["combinada"], 10)
    assert ESTADO_SPEC_9 == copia


def test_clamp_mantiene_todo_en_rango_clinico():
    """A 30 años una deriva sostenida se sale de rango si no se acota; sin el
    clamp, hs_CRP llega a cero y el log de la Capa 1 deja de estar definido."""
    for escenarios in ([], ["combinada"], ["ejercicio_aerobico", "sueno_8h"]):
        for estado in trayectoria_estados(ESTADO_SPEC_9, escenarios, 30):
            for nombre, valor in estado.items():
                spec = BIOMARKER_SPECS[nombre]
                assert spec.valor_min <= valor <= spec.valor_max, (nombre, valor)


def test_la_edad_cronologica_avanza_con_la_trayectoria():
    """La Capa 1 se evalúa con la edad de cada año, no con la inicial: dejarla
    fija aplanaría la curva artificialmente."""
    movil = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10)
    congelada = [
        trayectoria_deterministica(estado, [], EDAD_SPEC_9, 0)[0]
        for estado in trayectoria_estados(ESTADO_SPEC_9, [], 10)
    ]
    assert movil[-1] > congelada[-1]


# --- Procedencia de los coeficientes -----------------------------------------


def test_deriva_base_coherente_con_la_tabla_de_medianas():
    """`DYNAMICS[...].deriva_anual` dice reproducir el gradiente por edad de
    `nhanes_reference._MEDIANS`. Acá se comprueba, que es lo que convierte esos
    números en algo verificable y no en constantes sueltas.

    Tolerancia 2x en magnitud: son aproximaciones deliberadas. `glucosa` era el
    que más se desviaba (0,5 declarado vs 0,293 implícito, ~1,7x) y ya fue
    recalibrado a 0,29; los que más se alejan ahora son `creatinina`, `vcm` y
    `leucocitos`, en torno a 1,4x.
    """
    edad_media_del_tramo = {"<30": 25, "30-44": 37, "45-59": 52, "60-74": 67, "75+": 80}

    for nombre in PHENOAGE_BIOMARKERS:
        edades, valores = [], []
        for tramo, edad in edad_media_del_tramo.items():
            f, m = _MEDIANS[tramo]["F"][nombre], _MEDIANS[tramo]["M"][nombre]
            edades.append(edad)
            valores.append((f + m) / 2)

        media_edad = sum(edades) / len(edades)
        media_valor = sum(valores) / len(valores)
        pendiente = sum(
            (e - media_edad) * (v - media_valor) for e, v in zip(edades, valores)
        ) / sum((e - media_edad) ** 2 for e in edades)

        declarada = DYNAMICS[nombre].deriva_anual
        assert declarada * pendiente > 0, f"{nombre}: signo opuesto a la tabla"
        assert 0.5 <= declarada / pendiente <= 2.0, (
            f"{nombre}: deriva {declarada} vs pendiente implícita {pendiente:.4f}"
        )


#: Acumulado a 10 años que debe producir cada efecto anual, con la banda que
#: reportan los ensayos citados en `interventions.py`. Es la regla de
#: calibración del módulo hecha test: si alguien toca un coeficiente y el
#: acumulado se sale del rango publicado, esto lo detiene.
ACUMULADOS_ESPERADOS = [
    # (escenario, biomarcador, mínimo, máximo)  -- todo negativo = mejora
    ("ejercicio_aerobico", "hs_CRP", -1.0, -0.3),    # metaanálisis RCT ejercicio
    ("ejercicio_aerobico", "glucosa", -10.0, -5.0),  # idem, glucosa en ayunas
    ("dieta_mediterranea", "hs_CRP", -0.71, -0.54),  # PREDIMED / revisión paraguas
    ("dieta_mediterranea", "glucosa", -7.0, -3.8),   # PREDIMED / Estruch 2006
    ("cesacion_tabaco", "leucocitos", -1.2, -0.6),   # cese confirmado, dosis alta
    ("cesacion_tabaco", "vcm", -3.0, -1.0),          # VCM de fumador vs no fumador
]


@pytest.mark.parametrize("escenario, biomarcador, minimo, maximo", ACUMULADOS_ESPERADOS)
def test_acumulado_a_10_anios_dentro_del_rango_publicado(
    escenario, biomarcador, minimo, maximo
):
    acumulado = SCENARIOS[escenario].efectos_anuales[biomarcador] * 10
    assert minimo <= acumulado <= maximo, (
        f"{escenario}/{biomarcador}: {acumulado} fuera de [{minimo}, {maximo}]"
    )


def test_palancas_de_evidencia_debil_son_mas_conservadoras():
    """Sueño y estrés tienen evidencia de ensayo más floja que ejercicio y
    dieta (los ensayos de extensión de sueño no mueven PCR ni glucosa en
    jóvenes sanos; mindfulness solo baja PCR en subgrupos de riesgo). El modelo
    tiene que reflejar eso en la magnitud, no solo en un comentario."""
    crp = lambda k: abs(SCENARIOS[k].efectos_anuales.get("hs_CRP", 0.0))  # noqa: E731
    assert crp("sueno_8h") < crp("ejercicio_aerobico")
    assert crp("reducir_estres") < crp("dieta_mediterranea")
    assert crp("sueno_8h") > 0 and crp("reducir_estres") > 0


def test_las_palancas_de_la_spec_5_existen():
    """La spec §5 nombra sueno_8h y reducir_estres; el output de §8 se apoya en
    que el sueño pueda salir como palanca protagonista."""
    assert {"sueno_8h", "reducir_estres"} <= set(SCENARIOS)
    # Y las que ya existían siguen ahí: el contrato de /montecarlo no cambia.
    assert {
        "ninguna", "ejercicio_aerobico", "dieta_mediterranea",
        "cesacion_tabaco", "combinada",
    } <= set(SCENARIOS)


def test_capa_2_y_capa_3_aplican_la_misma_regla(monkeypatch):
    """La Capa 3 usa `deriva_total()` de este módulo en vez de repetir la regla
    inline, que era el problema original. Con el ruido en cero, el Monte Carlo
    tiene que reproducir exactamente la trayectoria determinista — si alguien
    vuelve a duplicar la regla en `montecarlo.py`, esto lo caza."""
    from app.health_metrics import interventions, montecarlo

    sin_ruido = {
        nombre: dyn._replace(ruido_anual_sd=0.0)
        for nombre, dyn in interventions.DYNAMICS.items()
    }
    monkeypatch.setattr(interventions, "DYNAMICS", sin_ruido)
    monkeypatch.setattr(montecarlo, "DYNAMICS", sin_ruido)

    resultados = montecarlo.run(
        ESTADO_SPEC_9, EDAD_SPEC_9, "F", ["combinada"], n_trayectorias=100, anios=10, seed=0
    ).resultados
    determinista = trayectoria_deterministica(
        ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9, 10
    )[-1]

    mc = resultados[0]
    assert mc.edad_biologica_mediana == pytest.approx(determinista, abs=1e-9)
    assert mc.edad_biologica_p10 == pytest.approx(mc.edad_biologica_p90, abs=1e-9)


def test_montecarlo_tolera_un_estado_inicial_de_enteros():
    """Regresión del bug de dtype: con los 9 valores iniciales enteros, el
    array de estado se inferían `int64` y cada asignación truncaba las derivas
    fraccionarias, hasta que hs_CRP llegaba a 0 y `log(0)` tumbaba el endpoint.
    No es alcanzable por el router (pydantic coacciona `valor` a float), pero
    `montecarlo.run()` es una función pública de un paquete sin FastAPI."""
    from app.health_metrics import montecarlo

    todos_enteros = {
        "hs_CRP": 2, "glucosa": 92, "albumina": 4, "creatinina": 1,
        "fosfatasa_alcalina": 70, "linfocitos_pct": 30, "vcm": 90,
        "rdw": 13, "leucocitos": 6,
    }
    resultados = montecarlo.run(
        todos_enteros, 40, "F", ["ninguna", "combinada"], n_trayectorias=200, anios=10, seed=1
    ).resultados
    base, combinada = resultados
    assert base.edad_biologica_mediana > combinada.edad_biologica_mediana


def test_ninguna_palanca_empeora_un_biomarcador_protector():
    """Albúmina y linfocitos% bajan la edad biológica cuando suben (coeficientes
    negativos en PhenoAge). Ninguna intervención debería empujarlos hacia
    abajo, ni ningún otro biomarcador hacia arriba."""
    protectores = {"albumina", "linfocitos_pct"}
    for key in PALANCAS:
        for nombre, efecto in SCENARIOS[key].efectos_anuales.items():
            if nombre in protectores:
                assert efecto >= 0, f"{key} baja {nombre}"
            else:
                assert efecto <= 0, f"{key} sube {nombre}"
