"""Capa 2 del motor (MOIRAI_ENGINE_SPEC.md §5): la regla de deriva.

El test que manda la spec es el de signos: *"Una trayectoria sin intervención
debe envejecer más rápido que una con buenas intervenciones. Si dormir 8h no
mejora nada, hay error de signo."* Está en `test_sin_intervencion_envejece_mas_rapido`
y en `test_dormir_8h_mejora_de_verdad`.

Los coeficientes de esta capa son aproximados y derivados de literatura, no del
paper de PhenoAge — ver la advertencia de procedencia en `interventions.py`.
Por eso acá no se verifica ningún valor contra una fuente externa: se verifica
que los **signos** vayan en la dirección correcta, que el **acumulado a 10
años** caiga dentro del rango de efecto que reportan los ensayos citados, que
la deriva base sea coherente con la tabla de medianas del propio motor, y que
los **hábitos** entren como dice el docstring de `interventions.py` (brechas,
descomposición de mezcla, sublinealidad).
"""

from __future__ import annotations

import pytest

from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.evolution import (
    ajuste_por_habito,
    anios_ganados,
    contribuciones_habitos,
    deriva_base,
    deriva_total,
    evolucionar_un_paso,
    trayectoria_deterministica,
    trayectoria_estados,
)
from app.health_metrics.interventions import (
    BRECHA_DESCONOCIDA,
    DESCUENTO_COMBINACION,
    DYNAMICS,
    HABITOS,
    PALANCAS,
    SCENARIOS,
    aplica,
    brechas_desde_habitos,
    esfuerzo_de,
    etiqueta_de,
    expandir,
    palancas_de,
)
from app.health_metrics.nhanes_reference import BRACKET_MIDPOINTS, _MEDIANS

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

ESCENARIOS_CON_EFECTO = [key for key in SCENARIOS if key != "ninguna"]


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


@pytest.mark.parametrize("palanca", ESCENARIOS_CON_EFECTO)
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


def test_la_persona_de_referencia_envejece_un_anio_por_anio():
    """Por construcción de PhenoAge, la persona promedio de su edad marca ≈ su
    edad; con la tabla y las derivas recalibradas, diez años de deriva natural
    le suman ≈ 10 años de edad biológica (±1,5), no los 12 que sumaba antes."""
    from app.health_metrics.nhanes_reference import reference_person

    for edad in (25, 40, 55, 70):
        for sexo in ("F", "M"):
            ref = reference_person(edad, sexo)
            tray = trayectoria_deterministica(ref, [], edad, 10)
            assert 8.5 <= tray[-1] - tray[0] <= 11.5, (edad, sexo, tray[-1] - tray[0])


def test_combinada_gana_mas_que_cualquiera_de_sus_partes():
    combinada = anios_ganados(ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9)
    for parte in ("ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco"):
        assert combinada > anios_ganados(ESTADO_SPEC_9, [parte], EDAD_SPEC_9)


def test_combinar_palancas_es_sublineal():
    """Decisión de modelado documentada en `interventions.py`: dos o tres
    palancas que actúan sobre el mismo biomarcador no suman sus beneficios.
    La ganancia del combo es MENOR que la suma de las ganancias por separado."""
    partes = ["ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco"]
    suma_de_individuales = sum(anios_ganados(ESTADO_SPEC_9, [p], EDAD_SPEC_9) for p in partes)
    combo = anios_ganados(ESTADO_SPEC_9, partes, EDAD_SPEC_9)
    assert combo < suma_de_individuales
    # `combinada` es exactamente ese combo genérico (compatibilidad de clave).
    assert anios_ganados(ESTADO_SPEC_9, ["combinada"], EDAD_SPEC_9) == pytest.approx(combo)
    assert anios_ganados(
        ESTADO_SPEC_9, ["ejercicio_aerobico+dieta_mediterranea+cesacion_tabaco"], EDAD_SPEC_9
    ) == pytest.approx(combo)


# --- La regla de deriva -------------------------------------------------------


def test_deriva_total_suma_base_mas_efectos():
    base = DYNAMICS["hs_CRP"].deriva_anual
    efecto = SCENARIOS["ejercicio_aerobico"].efectos_anuales["hs_CRP"]
    assert deriva_total("hs_CRP", []) == pytest.approx(base)
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"]) == pytest.approx(base + efecto)


def test_deriva_total_acumula_varias_intervenciones_con_descuento():
    """Los efectos de varias palancas sobre el MISMO biomarcador se suman con
    el descuento de sublinealidad (8 % por palanca adicional)."""
    e1 = SCENARIOS["sueno_8h"].efectos_anuales["hs_CRP"]
    e2 = SCENARIOS["reducir_estres"].efectos_anuales["hs_CRP"]
    esperado = DYNAMICS["hs_CRP"].deriva_anual + (e1 + e2) * (1 - DESCUENTO_COMBINACION)
    assert deriva_total("hs_CRP", ["sueno_8h", "reducir_estres"]) == pytest.approx(esperado)
    assert deriva_total("hs_CRP", ["sueno_8h+reducir_estres"]) == pytest.approx(esperado)
    # Sobre un biomarcador que solo toca una de las dos no hay descuento.
    assert deriva_total("glucosa", ["sueno_8h", "reducir_estres"]) == pytest.approx(
        DYNAMICS["glucosa"].deriva_anual + SCENARIOS["sueno_8h"].efectos_anuales["glucosa"]
    )


def test_escenario_ninguna_no_mueve_nada():
    assert deriva_total("glucosa", ["ninguna"]) == pytest.approx(
        deriva_total("glucosa", [])
    )


def test_un_paso_avanza_exactamente_una_deriva():
    siguiente = evolucionar_un_paso(ESTADO_SPEC_9, ["ejercicio_aerobico"])
    for nombre, valor in ESTADO_SPEC_9.items():
        esperado = valor + deriva_total(nombre, ["ejercicio_aerobico"], valor=valor)
        assert siguiente[nombre] == pytest.approx(esperado)


def test_el_efecto_sobre_la_pcr_es_proporcional_al_valor_actual():
    """`EFECTO_RELATIVO_A`: el coeficiente de PCR está calibrado a 2,5 mg/L y
    escala con el valor: quien tiene el doble de PCR baja el doble; quien
    tiene la décima parte, la décima parte. El resto es absoluto."""
    e = SCENARIOS["ejercicio_aerobico"].efectos_anuales["hs_CRP"]
    d = DYNAMICS["hs_CRP"].deriva_anual
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"], valor=2.5) == pytest.approx(d + e)
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"], valor=5.0) == pytest.approx(d + 2 * e)
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"], valor=0.25) == pytest.approx(d + 0.1 * e)
    # Sin valor: el efecto a la referencia (lo que se publica en el catálogo).
    assert deriva_total("hs_CRP", ["ejercicio_aerobico"]) == pytest.approx(d + e)
    # La glucosa no es relativa.
    g = SCENARIOS["ejercicio_aerobico"].efectos_anuales["glucosa"]
    assert deriva_total("glucosa", ["ejercicio_aerobico"], valor=150.0) == pytest.approx(
        DYNAMICS["glucosa"].deriva_anual + g
    )
    # Y en la trayectoria: a más PCR de partida, más años gana la misma palanca.
    alta = anios_ganados({**ESTADO_SPEC_9, "hs_CRP": 6.0}, ["reducir_estres"], EDAD_SPEC_9)
    baja = anios_ganados({**ESTADO_SPEC_9, "hs_CRP": 0.5}, ["reducir_estres"], EDAD_SPEC_9)
    assert alta > baja > 0


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


# --- Escenarios compuestos ----------------------------------------------------


def test_expandir_escenarios():
    assert expandir("ninguna") == ()
    assert expandir("sueno_8h") == ("sueno_8h",)
    assert expandir("combinada") == ("ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco")
    assert expandir("ejercicio_aerobico+sueno_8h") == ("ejercicio_aerobico", "sueno_8h")
    assert palancas_de(["combinada", "sueno_8h+ejercicio_aerobico"]) == [
        "ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco", "sueno_8h",
    ]
    assert esfuerzo_de("ejercicio_aerobico+sueno_8h") == 3 + 2
    assert esfuerzo_de("combinada") == 10
    assert etiqueta_de("ejercicio_aerobico+sueno_8h") == "Ejercicio aeróbico regular + dormir 8 horas"


@pytest.mark.parametrize(
    "malo",
    [
        "yoga",
        "ejercicio_aerobico+yoga",
        "ejercicio_aerobico+ejercicio_aerobico",
        "ejercicio_aerobico+sueno_8h+reducir_estres+dieta_mediterranea",  # 4 > 3 (spec §12)
        "",
        "+",
    ],
)
def test_expandir_rechaza_escenarios_invalidos(malo):
    with pytest.raises(ValueError):
        expandir(malo)


# --- Hábitos: brechas y descomposición de mezcla --------------------------------


def test_brechas_desde_habitos():
    b = brechas_desde_habitos(
        {"actividad": "baja", "alimentacion": "alta", "estres": "medio", "tabaco": True,
         "sueno_h": 6, "alcohol": "moderado"}
    )
    assert b == {
        "actividad": 1.0, "alimentacion": 0.0, "estres": 0.5, "tabaco": 1.0,
        "sueno": 1.0, "alcohol": 0.5,
    }
    # Grafías alternativas de nivel, horas intermedias y desconocidos.
    b = brechas_desde_habitos({"actividad": "Media", "estres": "alta", "sueno_h": 6.75, "alcohol": "nunca"})
    assert b["actividad"] == 0.5 and b["estres"] == 1.0 and b["alcohol"] == 0.0
    assert b["sueno"] == pytest.approx(0.5)
    assert b["tabaco"] is None and b["alimentacion"] is None
    assert set(brechas_desde_habitos(None)) == set(HABITOS)
    assert all(v is None for v in brechas_desde_habitos({}).values())
    # ≥7,5 h cierra la brecha; un valor raro no revienta, queda como desconocido.
    assert brechas_desde_habitos({"sueno_h": 8})["sueno"] == 0.0
    assert brechas_desde_habitos({"actividad": "muchisima"})["actividad"] is None


def test_habito_bueno_anula_la_palanca():
    """A quien ya hace ejercicio no se le vende el ejercicio: efecto 0 y la
    palanca no aplica. Con la brecha a medias, la mitad del efecto."""
    activo = brechas_desde_habitos({"actividad": "alta"})
    medio = brechas_desde_habitos({"actividad": "media"})
    sedentario = brechas_desde_habitos({"actividad": "baja"})
    base_a = deriva_base("glucosa", activo)
    assert deriva_total("glucosa", ["ejercicio_aerobico"], activo) == pytest.approx(base_a)
    assert not aplica("ejercicio_aerobico", activo)
    assert aplica("ejercicio_aerobico", sedentario) and aplica("ejercicio_aerobico", medio)
    e = SCENARIOS["ejercicio_aerobico"].efectos_anuales["glucosa"]
    assert deriva_total("glucosa", ["ejercicio_aerobico"], medio) == pytest.approx(
        deriva_base("glucosa", medio) + 0.5 * e
    )
    assert deriva_total("glucosa", ["ejercicio_aerobico"], sedentario) == pytest.approx(
        deriva_base("glucosa", sedentario) + e
    )
    # Un combo en el que solo una parte aplica sigue aplicando.
    assert aplica("ejercicio_aerobico+sueno_8h", brechas_desde_habitos({"actividad": "alta", "sueno_h": 6}))
    assert not aplica("combinada", brechas_desde_habitos({"actividad": "alta", "alimentacion": "alta", "tabaco": False}))


def test_habito_desconocido_no_ajusta_la_base_pero_si_ofrece_las_universales():
    desconocido = brechas_desde_habitos({})
    for nombre in PHENOAGE_BIOMARKERS:
        assert deriva_base(nombre, desconocido) == pytest.approx(DYNAMICS[nombre].deriva_anual)
    # Universales: efecto completo. Las de "solo si lo haces": no se asumen.
    assert BRECHA_DESCONOCIDA["actividad"] == 1.0 and BRECHA_DESCONOCIDA["tabaco"] == 0.0
    assert aplica("ejercicio_aerobico", desconocido) and aplica("sueno_8h", desconocido)
    assert not aplica("cesacion_tabaco", desconocido) and not aplica("reducir_alcohol", desconocido)
    assert deriva_total("leucocitos", ["cesacion_tabaco"], desconocido) == pytest.approx(
        deriva_base("leucocitos", desconocido)
    )


def test_fumador_envejece_mas_rapido_que_la_poblacion_y_el_no_fumador_menos():
    """Descomposición de mezcla: brecha 1 → deriva por encima de la poblacional
    en (1−ḡ)·|E|; brecha 0 → por debajo en ḡ·|E|, acotado a no invertir la
    deriva por edad."""
    fuma = brechas_desde_habitos({"tabaco": True})
    no_fuma = brechas_desde_habitos({"tabaco": False})
    sc = SCENARIOS["cesacion_tabaco"]
    for nombre, e in sc.efectos_anuales.items():
        d = DYNAMICS[nombre].deriva_anual
        assert deriva_base(nombre, fuma) == pytest.approx(d + (1 - sc.brecha_promedio) * (-e))
        bono = -sc.brecha_promedio * (-e)  # negativo (o en dirección favorable)
        esperado = d + bono
        if abs(bono) > abs(d):
            esperado = 0.0  # el bono frena el reloj, no lo invierte
        assert deriva_base(nombre, no_fuma) == pytest.approx(esperado)
        assert deriva_base(nombre, no_fuma) <= deriva_base(nombre, {}) <= deriva_base(nombre, fuma)


def test_intervenir_no_deja_mejor_que_quien_ya_tenia_el_habito_salvo_por_el_tope():
    """Sedentario que empieza a hacer ejercicio ≤ activo de siempre ≤ población,
    en deriva de glucosa (la palanca cierra la brecha, el tope solo acota el
    bono del que ya lo tenía)."""
    activo = brechas_desde_habitos({"actividad": "alta"})
    sedentario = brechas_desde_habitos({"actividad": "baja"})
    assert (
        deriva_total("glucosa", ["ejercicio_aerobico"], sedentario)
        <= deriva_base("glucosa", activo)
        <= DYNAMICS["glucosa"].deriva_anual
    )
    # Y la trayectoria determinista lo refleja: sedentario > activo al horizonte.
    t_sed = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10, sedentario)[-1]
    t_act = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10, activo)[-1]
    t_pob = trayectoria_deterministica(ESTADO_SPEC_9, [], EDAD_SPEC_9, 10)[-1]
    assert t_act < t_pob < t_sed


def test_los_anios_ganados_no_dependen_de_la_prevalencia():
    """ḡ solo mueve dónde queda la línea base; la ganancia de cerrar una brecha
    completa es la misma con o sin hábitos registrados (salvo no linealidad
    del ln de la PCR, de ahí la tolerancia)."""
    con = anios_ganados(ESTADO_SPEC_9, ["ejercicio_aerobico"], EDAD_SPEC_9, brechas=brechas_desde_habitos({"actividad": "baja"}))
    sin = anios_ganados(ESTADO_SPEC_9, ["ejercicio_aerobico"], EDAD_SPEC_9)
    assert con == pytest.approx(sin, abs=0.15)


def test_ajuste_por_habito_es_cero_si_la_palanca_no_toca_el_biomarcador():
    assert ajuste_por_habito("rdw", "ejercicio_aerobico", 1.0) == 0.0
    assert ajuste_por_habito("glucosa", "reducir_estres", 1.0) == 0.0


def test_contribuciones_habitos_signos():
    brechas = brechas_desde_habitos({"tabaco": True, "actividad": "alta", "sueno_h": 7})
    filas = {c["habito"]: c for c in contribuciones_habitos(ESTADO_SPEC_9, EDAD_SPEC_9, brechas)}
    assert set(filas) == {"tabaco", "actividad", "sueno"}  # solo los registrados
    assert filas["tabaco"]["direccion"] == "empeora" and filas["tabaco"]["contribucion"] > 0
    assert filas["actividad"]["direccion"] == "mejora" and filas["actividad"]["contribucion"] < 0
    # Brecha parcial (7 h → 1/3): pequeña y positiva.
    assert 0 < filas["sueno"]["contribucion"] < filas["tabaco"]["contribucion"]
    assert contribuciones_habitos(ESTADO_SPEC_9, EDAD_SPEC_9, None) == []


# --- Procedencia de los coeficientes -----------------------------------------


def test_deriva_base_coherente_con_la_tabla_de_medianas():
    """`DYNAMICS[...].deriva_anual` dice reproducir el gradiente por edad de
    `nhanes_reference._MEDIANS`. Acá se comprueba, que es lo que convierte esos
    números en algo verificable y no en constantes sueltas.

    Tolerancia 2x en magnitud: son aproximaciones deliberadas.
    """
    for nombre in PHENOAGE_BIOMARKERS:
        edades, valores = [], []
        for tramo, edad in BRACKET_MIDPOINTS.items():
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
    ("reducir_alcohol", "vcm", -4.0, -1.0),          # macrocitosis del bebedor fuerte
    ("reducir_alcohol", "hs_CRP", -0.5, -0.2),       # relación en J alcohol–PCR
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
    """Sueño, estrés y alcohol tienen evidencia de ensayo más floja que
    ejercicio y dieta. El modelo tiene que reflejar eso en la magnitud, no
    solo en un comentario."""
    crp = lambda k: abs(SCENARIOS[k].efectos_anuales.get("hs_CRP", 0.0))  # noqa: E731
    assert crp("sueno_8h") < crp("ejercicio_aerobico")
    assert crp("reducir_estres") < crp("dieta_mediterranea")
    assert crp("reducir_alcohol") < crp("dieta_mediterranea")
    assert crp("sueno_8h") > 0 and crp("reducir_estres") > 0 and crp("reducir_alcohol") > 0


def test_las_palancas_de_la_spec_5_existen_y_cierran_un_habito():
    """La spec §5 nombra sueno_8h, reducir_estres y dejar_alcohol; el output de
    §8 se apoya en que el sueño pueda salir como palanca protagonista."""
    assert {"sueno_8h", "reducir_estres", "reducir_alcohol"} <= set(SCENARIOS)
    # Y las que ya existían siguen ahí: el contrato de /montecarlo no cambia.
    assert {
        "ninguna", "ejercicio_aerobico", "dieta_mediterranea",
        "cesacion_tabaco", "combinada",
    } <= set(SCENARIOS)
    for key in PALANCAS:
        sc = SCENARIOS[key]
        assert sc.habito in HABITOS, key
        assert 1 <= sc.esfuerzo <= 10 and sc.descripcion, key
        assert 0 < sc.brecha_promedio < 1, key


def test_capa_2_y_capa_3_aplican_la_misma_regla(monkeypatch):
    """La Capa 3 usa `deriva_base`/`efectos_palancas` de este módulo en vez de
    repetir la regla inline. Con el ruido y la heterogeneidad de respuesta en
    cero, el Monte Carlo tiene que reproducir exactamente la trayectoria
    determinista — si alguien vuelve a duplicar la regla en `montecarlo.py`,
    esto lo caza."""
    from app.health_metrics import interventions, montecarlo

    sin_ruido = {
        nombre: dyn._replace(ruido_anual_sd=0.0)
        for nombre, dyn in interventions.DYNAMICS.items()
    }
    monkeypatch.setattr(interventions, "DYNAMICS", sin_ruido)
    monkeypatch.setattr(montecarlo, "DYNAMICS", sin_ruido)
    monkeypatch.setattr(montecarlo, "HETEROGENEIDAD_RESPUESTA", 0.0)

    brechas = brechas_desde_habitos({"tabaco": True, "actividad": "baja", "sueno_h": 6})
    resultados, _ = montecarlo.run(
        ESTADO_SPEC_9, EDAD_SPEC_9, "F", ["combinada", "ejercicio_aerobico+sueno_8h"],
        n_trayectorias=100, anios=10, seed=0, brechas=brechas,
    )
    for mc in resultados:
        determinista = trayectoria_deterministica(
            ESTADO_SPEC_9, [mc.escenario], EDAD_SPEC_9, 10, brechas
        )
        assert mc.edad_biologica_mediana == pytest.approx(determinista[-1], abs=1e-9)
        assert mc.edad_biologica_p10 == pytest.approx(mc.edad_biologica_p90, abs=1e-9)
        assert mc.curva_mediana == pytest.approx(determinista, abs=1e-9)


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
    resultados, _ = montecarlo.run(
        todos_enteros, 40, "F", ["ninguna", "combinada"], n_trayectorias=200, anios=10, seed=1
    )
    base, combinada = resultados
    assert base.edad_biologica_mediana > combinada.edad_biologica_mediana


def test_ninguna_palanca_empeora_un_biomarcador_protector():
    """Albúmina y linfocitos% bajan la edad biológica cuando suben (coeficientes
    negativos en PhenoAge). Ninguna intervención debería empujarlos hacia
    abajo, ni ningún otro biomarcador hacia arriba."""
    protectores = {"albumina", "linfocitos_pct"}
    for key in ESCENARIOS_CON_EFECTO:
        for nombre, efecto in SCENARIOS[key].efectos_anuales.items():
            if nombre in protectores:
                assert efecto >= 0, f"{key} baja {nombre}"
            else:
                assert efecto <= 0, f"{key} sube {nombre}"
