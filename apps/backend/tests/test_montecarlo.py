"""Capa 3 del motor (MOIRAI_ENGINE_SPEC.md §6): el abanico.

Lo que manda la spec: *"El abanico P10–P90 debe ensancharse con los años. Un
perfil con biomarcadores imputados debe tener banda más ancha que uno con
datos completos."* Y lo que promete la app encima: futuros pareados (mismos
arranques y mismos ruidos con y sin la palanca), un rango honesto para los
años ganados, y que medir lo imputado angosta la banda (valor de información).
"""

from __future__ import annotations

import numpy as np
import pytest

from app.health_metrics import montecarlo
from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import PALANCAS, brechas_desde_habitos
from app.health_metrics.nhanes_reference import impute_missing

SEIS_MEDIDOS = {
    "albumina": 4.4, "creatinina": 0.8, "glucosa": 92.0, "hs_CRP": 2.1, "rdw": 13.1, "leucocitos": 6.2,
}
EDAD = 34.0


def _sim(bm, escenarios, brechas=None, n=2000, seed=1, **kw):
    return montecarlo.simular(bm, EDAD, "F", escenarios, n, 10, seed=seed, brechas=brechas, **kw)


# --- Lo que pide la spec §6 ----------------------------------------------------


def test_el_abanico_se_ensancha_con_los_anios():
    r = _sim(SEIS_MEDIDOS, ["ninguna"])
    b = r.escenarios[0]
    anchos = [p90 - p10 for p10, p90 in zip(b.curva_p10, b.curva_p90)]
    assert anchos[1] < anchos[5] < anchos[10]
    assert len(b.curva_anios) == 11 and b.curva_anios[-1] == 10
    assert b.edad_biologica_mediana == pytest.approx(b.curva_mediana[-1])


def test_los_imputados_ensanchan_la_banda_y_medir_la_angosta():
    """Antes la banda medía lo mismo con 0 o con 9 medidos (bug): el ruido era
    solo de deriva. Ahora un imputado arranca muestreado de la dispersión
    poblacional, así que la banda — hoy y al horizonte — se angosta al medir."""
    todo = impute_missing({}, EDAD, "F")[0]
    nueve = _sim(todo, ["ninguna"])
    seis = _sim(SEIS_MEDIDOS, ["ninguna"])
    cero = _sim({}, ["ninguna"])
    ancho = lambda r: r.escenarios[0].edad_biologica_p90 - r.escenarios[0].edad_biologica_p10  # noqa: E731
    assert ancho(cero) > ancho(seis) > ancho(nueve)
    assert nueve.ancho_banda_hoy == 0.0
    assert 0 < seis.ancho_banda_hoy < cero.ancho_banda_hoy
    assert seis.campos_inferidos == ["fosfatasa_alcalina", "linfocitos_pct", "vcm"]
    assert nueve.campos_inferidos == []


def test_valor_de_informacion_ordena_lo_imputado():
    r = _sim({}, ["ninguna"])
    assert [v.nombre for v in r.valor_de_informacion][0] == "rdw"  # el de más peso en la fórmula
    assert set(v.nombre for v in r.valor_de_informacion) == set(PHENOAGE_BIOMARKERS)
    reducciones = [v.reduccion_banda_anios for v in r.valor_de_informacion]
    assert reducciones == sorted(reducciones, reverse=True)
    assert all(v.reduccion_banda_anios >= 0 for v in r.valor_de_informacion)
    assert sum(v.fraccion for v in r.valor_de_informacion) == pytest.approx(1.0)
    # Con los 9 medidos no hay nada que medir.
    assert _sim(impute_missing({}, EDAD, "F")[0], ["ninguna"]).valor_de_informacion == []


# --- Pareado, reproducible, rango honesto --------------------------------------


def test_misma_semilla_mismo_abanico_y_ninguna_siempre_es_la_base():
    a = _sim(SEIS_MEDIDOS, ["ninguna", "ejercicio_aerobico"], seed=5)
    b = _sim(SEIS_MEDIDOS, ["ninguna", "ejercicio_aerobico"], seed=5)
    c = _sim(SEIS_MEDIDOS, ["ninguna", "ejercicio_aerobico"], seed=6)
    assert a.escenarios[1].curva_mediana == b.escenarios[1].curva_mediana
    assert a.escenarios[1].curva_mediana != c.escenarios[1].curva_mediana
    assert a.semilla == 5 and _sim(SEIS_MEDIDOS, ["ninguna"], seed=None).semilla == montecarlo.DEFAULT_SEED
    base = a.escenarios[0]
    assert base.escenario == "ninguna" and base.anios_ganados == 0 and base.pct_futuros_que_mejoran == 0
    # Aunque no se pida, la base se simula para parear; si se pide, va tal cual.
    solo = _sim(SEIS_MEDIDOS, ["ejercicio_aerobico"], seed=5)
    assert solo.escenarios[0].anios_ganados == pytest.approx(a.escenarios[1].anios_ganados)


def test_anios_ganados_pareados_tienen_rango_y_casi_todos_los_futuros_mejoran():
    r = _sim(SEIS_MEDIDOS, ["ninguna", "ejercicio_aerobico"], n=4000)
    base, ej = r.escenarios
    assert ej.anios_ganados > 0
    assert ej.anios_ganados_p10 < ej.anios_ganados < ej.anios_ganados_p90
    # La heterogeneidad de respuesta (N(1, 0,5) truncada) da un rango real…
    assert ej.anios_ganados_p90 - ej.anios_ganados_p10 > 0.5 * ej.anios_ganados
    # …y un ~2 % de no respondedores: mejora en casi todos, no en todos.
    assert 90 < ej.pct_futuros_que_mejoran < 100
    # La mediana pareada y la diferencia de medianas cuentan la misma historia.
    assert ej.anios_ganados == pytest.approx(base.edad_biologica_mediana - ej.edad_biologica_mediana, abs=0.5)
    assert ej.ratio_impacto_esfuerzo == pytest.approx(ej.anios_ganados / 3)
    assert ej.intervenciones == ("ejercicio_aerobico",) and ej.esfuerzo == 3


def test_escenarios_compuestos_y_claves_invalidas():
    r = _sim(SEIS_MEDIDOS, ["ejercicio_aerobico", "sueno_8h", "ejercicio_aerobico+sueno_8h", "combinada"])
    por = {e.escenario: e for e in r.escenarios}
    combo = por["ejercicio_aerobico+sueno_8h"]
    assert combo.intervenciones == ("ejercicio_aerobico", "sueno_8h") and combo.esfuerzo == 5
    assert combo.anios_ganados > por["ejercicio_aerobico"].anios_ganados
    assert combo.anios_ganados < por["ejercicio_aerobico"].anios_ganados + por["sueno_8h"].anios_ganados
    assert por["combinada"].intervenciones == ("ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco")
    with pytest.raises(ValueError):
        _sim(SEIS_MEDIDOS, ["yoga"])
    with pytest.raises(ValueError):
        _sim(SEIS_MEDIDOS, ["ejercicio_aerobico+dieta_mediterranea+sueno_8h+reducir_estres"])


# --- Hábitos -------------------------------------------------------------------


def test_habito_bueno_colapsa_la_palanca_sobre_la_base():
    activo = brechas_desde_habitos({"actividad": "alta", "tabaco": False})
    r = _sim(SEIS_MEDIDOS, ["ninguna", "ejercicio_aerobico", "cesacion_tabaco"], brechas=activo)
    base, ej, tab = r.escenarios
    for e in (ej, tab):
        assert not e.aplica
        assert e.anios_ganados == pytest.approx(0.0, abs=1e-9)
        assert e.curva_mediana == pytest.approx(base.curva_mediana)


def test_los_habitos_mueven_la_linea_base():
    malo = brechas_desde_habitos({"tabaco": True, "actividad": "baja", "alimentacion": "baja", "sueno_h": 5, "estres": "alto", "alcohol": "alto"})
    bueno = brechas_desde_habitos({"tabaco": False, "actividad": "alta", "alimentacion": "alta", "sueno_h": 8, "estres": "bajo", "alcohol": "nunca"})
    rm = _sim(SEIS_MEDIDOS, ["ninguna"], brechas=malo).escenarios[0]
    rb = _sim(SEIS_MEDIDOS, ["ninguna"], brechas=bueno).escenarios[0]
    rp = _sim(SEIS_MEDIDOS, ["ninguna"]).escenarios[0]
    assert rm.edad_biologica_mediana > rp.edad_biologica_mediana > rb.edad_biologica_mediana
    # Arrancan del mismo punto: el año 0 es idéntico.
    assert rm.curva_mediana[0] == pytest.approx(rb.curva_mediana[0])


def test_contribuciones_habitos_y_muestra_en_el_resultado():
    brechas = brechas_desde_habitos({"tabaco": True, "actividad": "alta"})
    r = _sim(SEIS_MEDIDOS, ["ninguna"], brechas=brechas, n=300)
    habitos = {c["habito"]: c for c in r.contribuciones_habitos}
    assert habitos["tabaco"]["direccion"] == "empeora" and habitos["actividad"]["direccion"] == "mejora"
    assert len(r.muestra_trayectorias) == montecarlo.MUESTRA_TRAYECTORIAS
    assert all(len(t) == 11 for t in r.muestra_trayectorias)
    base = r.escenarios[0]
    # Son trayectorias reales de la simulación: finitas, y la mayoría (≈80 %)
    # arranca dentro de la banda P10–P90 de hoy (no todas — por definición).
    assert all(np.isfinite(t).all() for t in r.muestra_trayectorias)
    dentro = sum(base.curva_p10[0] - 1e-9 <= t[0] <= base.curva_p90[0] + 1e-9 for t in r.muestra_trayectorias)
    assert dentro >= 0.6 * len(r.muestra_trayectorias)


def test_run_conserva_la_firma_anterior():
    resultados, imputados = montecarlo.run(SEIS_MEDIDOS, EDAD, "F", ["ninguna", "combinada"], n_trayectorias=200, anios=10, seed=1)
    assert [e.escenario for e in resultados] == ["ninguna", "combinada"]
    assert imputados == ["fosfatasa_alcalina", "linfocitos_pct", "vcm"]
    assert resultados[0].edad_biologica_mediana > resultados[1].edad_biologica_mediana


def test_todas_las_palancas_sueltas_ganan_en_el_monte_carlo():
    r = _sim(SEIS_MEDIDOS, list(PALANCAS), n=1500)
    for e in r.escenarios:
        assert e.anios_ganados > 0, e.escenario
        assert e.pct_futuros_que_mejoran > 85, e.escenario


def test_es_rapido_con_el_barrido_completo():
    """41 escenarios × 5.000 trayectorias × 10 años en bien menos de lo que
    tarda Render en despertar: el endpoint no puede bloquearse segundos."""
    import time
    from itertools import combinations

    escenarios = ["ninguna", *PALANCAS]
    for k in (2, 3):
        escenarios += ["+".join(c) for c in combinations(PALANCAS, k)]
    t0 = time.perf_counter()
    r = montecarlo.simular({}, 50, "M", escenarios, 5000, 10, brechas=brechas_desde_habitos({}))
    assert len(r.escenarios) == len(escenarios)
    assert time.perf_counter() - t0 < 5.0
