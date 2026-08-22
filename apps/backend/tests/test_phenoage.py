"""Capa 1 del motor (MOIRAI_ENGINE_SPEC.md §4): el reloj PhenoAge.

Los coeficientes de `app/health_metrics/phenoage.py` se verificaron contra dos
fuentes independientes antes de escribir estos tests:

1. Levine et al. 2018 tal como lo reproduce la corrección publicada de Liu et al.
   (PMC6388911), con los coeficientes redondeados del paper:
       xb = -19.907 - 0.0336*Alb + 0.0095*Creat + 0.1953*Gluc + 0.0954*ln(CRP)
            - 0.0120*Linf% + 0.0268*VCM + 0.3306*RDW + 0.00188*FA
            + 0.0554*Leuco + 0.0804*Edad
       M  = 1 - exp(-1.51714 * exp(xb) / 0.0076927)
       PhenoAge = 141.50225 + ln(-0.0055305 * ln(1 - M)) / 0.090165
2. El paquete R `dayoonkwon/BioAge` (`phenoage_calc(..., orig = TRUE)`), mantenido
   por el grupo de investigación original, que trae los mismos coeficientes con
   todos sus decimales — que son los que usa el módulo.

Unidades canónicas del ajuste (NHANES III): albúmina g/L, creatinina µmol/L,
glucosa mmol/L, CRP en ln(mg/dL), linfocitos %, VCM fL, RDW %, fosfatasa
alcalina U/L, leucocitos 10^3/µL, edad años. La app guarda los valores como los
lee un laboratorio (g/dL, mg/dL, mg/L); `to_formula_units()` hace la conversión.

Nota sobre una errata: la corrección publicada imprime "/0.09165" en el paso
final. El valor correcto —y el que usan el suplemento original y la
implementación de referencia en R— es 0.090165.
"""

from __future__ import annotations

import math

import pytest

from app.health_metrics.phenoage import compute, phenoage_years, to_formula_units


# --- Caso de prueba de la spec §9 ---------------------------------------------

PERFIL_SPEC_9 = {
    "albumina": 4.4,
    "creatinina": 0.8,
    "glucosa": 92,
    "hs_CRP": 2.1,
    "rdw": 13.1,
    "leucocitos": 6.2,
}
IMPUTADOS_SPEC_9 = {"linfocitos_pct": 30, "vcm": 90, "fosfatasa_alcalina": 70}
EDAD_SPEC_9 = 34.0


def _phenoage_coeficientes_redondeados(v: dict[str, float], edad: float) -> float:
    """La fórmula tal cual está impresa en el paper, con los coeficientes
    redondeados. Implementación independiente de la del módulo: si las dos
    coinciden, no hay error de transcripción ni de orden de operaciones."""
    xb = (
        -19.907
        - 0.0336 * v["albumin_gL"]
        + 0.0095 * v["creatinine_umol"]
        + 0.1953 * v["glucose_mmol"]
        + 0.0954 * v["ln_crp_mgdL"]
        - 0.0120 * v["lymphocyte_pct"]
        + 0.0268 * v["mcv_fL"]
        + 0.3306 * v["rdw_pct"]
        + 0.00188 * v["alp_UL"]
        + 0.0554 * v["wbc_1000uL"]
        + 0.0804 * edad
    )
    mortalidad = 1 - math.exp(-1.51714 * math.exp(xb) / 0.0076927)
    return 141.50225 + math.log(-0.0055305 * math.log(1 - mortalidad)) / 0.090165


# --- Normalización de unidades ------------------------------------------------


def test_conversion_a_unidades_del_paper():
    """g/dL -> g/L, mg/dL -> µmol/L, mg/dL -> mmol/L, mg/L -> ln(mg/dL)."""
    convertido = to_formula_units({**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9})

    assert convertido["albumin_gL"] == pytest.approx(44.0)
    assert convertido["creatinine_umol"] == pytest.approx(70.72, abs=0.01)
    assert convertido["glucose_mmol"] == pytest.approx(5.106, abs=0.001)
    # 2.1 mg/L = 0.21 mg/dL; el modelo usa ln(mg/dL), no ln(mg/L).
    assert convertido["ln_crp_mgdL"] == pytest.approx(math.log(0.21))
    # Los que ya vienen en la unidad del paper pasan sin tocar.
    assert convertido["lymphocyte_pct"] == 30
    assert convertido["mcv_fL"] == 90
    assert convertido["rdw_pct"] == 13.1
    assert convertido["alp_UL"] == 70
    assert convertido["wbc_1000uL"] == 6.2


def test_crp_en_mg_por_litro_no_se_logaritma_directo():
    """Regresión: usar ln(mg/L) en vez de ln(mg/dL) infla la edad ~2.4 años.
    Es el error de unidades más fácil de cometer, así que queda anclado."""
    v = to_formula_units({**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9})
    correcto = phenoage_years(v, EDAD_SPEC_9)
    con_error = phenoage_years({**v, "ln_crp_mgdL": math.log(2.1)}, EDAD_SPEC_9)
    assert con_error - correcto > 2.0


# --- La fórmula ---------------------------------------------------------------


def test_formula_coincide_con_los_coeficientes_publicados():
    """El módulo usa los coeficientes con todos sus decimales (referencia R);
    el paper los imprime redondeados. Deben dar prácticamente lo mismo."""
    v = to_formula_units({**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9})
    del_modulo = phenoage_years(v, EDAD_SPEC_9)
    del_paper = _phenoage_coeficientes_redondeados(v, EDAD_SPEC_9)
    assert del_modulo == pytest.approx(del_paper, abs=0.2)


@pytest.mark.parametrize(
    "biomarcador, delta, direccion",
    [
        ("hs_CRP", +5.0, "sube"),      # más inflamación -> más viejo
        ("glucosa", +40.0, "sube"),    # más glucosa -> más viejo
        ("rdw", +2.0, "sube"),         # RDW alto es el driver de mayor peso
        ("leucocitos", +3.0, "sube"),
        ("albumina", +0.5, "baja"),    # albúmina alta protege
        ("linfocitos_pct", +10.0, "baja"),
    ],
)
def test_signos_de_cada_biomarcador(biomarcador, delta, direccion):
    """Test de signos: si alguno está invertido, el motor recomendaría al revés."""
    base = compute({**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9}, EDAD_SPEC_9, "F")
    movido = compute(
        {**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9, biomarcador: (
            {**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9}[biomarcador] + delta
        )},
        EDAD_SPEC_9,
        "F",
    )
    if direccion == "sube":
        assert movido.edad_biologica > base.edad_biologica
    else:
        assert movido.edad_biologica < base.edad_biologica


def test_edad_cronologica_empuja_la_biologica():
    fijos = {**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9}
    joven = phenoage_years(to_formula_units(fijos), 34)
    viejo = phenoage_years(to_formula_units(fijos), 54)
    assert viejo > joven


# --- Caso end-to-end de la spec §9 --------------------------------------------


def test_caso_spec_9_da_edad_biologica_plausible():
    """§4 "Test Capa 1": para población sana la edad fenotípica debe caer a
    ±10–15 años de la cronológica. Un 200 o un -30 es error de unidades.

    Valor observado: 28.5 años para una cronológica de 34 (aceleración -5.5).
    El comentario de §9 dice "30-45 aprox", pero ese rango es una estimación a
    ojo del documento, no un valor de referencia: este perfil (albúmina 4.4,
    glucosa 92, RDW 13.1) es genuinamente mejor que la mediana de su edad, y la
    fórmula verificada contra el paper devuelve 28.5. Manda la fórmula."""
    r = compute({**PERFIL_SPEC_9, **IMPUTADOS_SPEC_9}, EDAD_SPEC_9, "F")

    assert r.edad_cronologica == EDAD_SPEC_9
    assert abs(r.aceleracion) <= 15
    assert r.aceleracion == pytest.approx(r.edad_biologica - r.edad_cronologica)
    assert r.campos_inferidos == []  # aquí se pasaron los 9 completos


def test_caso_spec_9_con_los_tres_biomarcadores_imputados():
    """La forma real del input de §3: 6 medidos + 3 que faltan. Se imputan de
    la tabla de medianas y quedan marcados como inferidos."""
    r = compute(PERFIL_SPEC_9, EDAD_SPEC_9, "F")

    assert sorted(r.campos_inferidos) == [
        "fosfatasa_alcalina",
        "linfocitos_pct",
        "vcm",
    ]
    assert set(r.valores_usados) == {
        "albumina", "creatinina", "glucosa", "hs_CRP", "rdw", "leucocitos",
        "fosfatasa_alcalina", "linfocitos_pct", "vcm",
    }
    # Los medidos entran sin modificar.
    for nombre, valor in PERFIL_SPEC_9.items():
        assert r.valores_usados[nombre] == valor
    assert abs(r.aceleracion) <= 15


def test_perfil_sin_ningun_biomarcador_sigue_siendo_plausible():
    """Todo imputado = el caso de un usuario que aún no subió exámenes. Tiene
    que devolver un número usable (la banda ancha la pone la Capa 3, no esta)."""
    for edad in (25, 40, 55, 70, 85):
        for sexo in ("F", "M", None):
            r = compute({}, edad, sexo)
            assert len(r.campos_inferidos) == 9
            assert abs(r.aceleracion) <= 15, (edad, sexo, r.edad_biologica)


def test_perfil_deteriorado_envejece_frente_al_sano():
    sano = compute(PERFIL_SPEC_9, EDAD_SPEC_9, "F")
    deteriorado = compute(
        {
            "albumina": 3.6,
            "creatinina": 1.4,
            "glucosa": 145,
            "hs_CRP": 8.0,
            "rdw": 15.5,
            "leucocitos": 9.5,
        },
        EDAD_SPEC_9,
        "F",
    )
    assert deteriorado.edad_biologica > sano.edad_biologica + 5


PERFIL_MEJOR_CASO = {
    "albumina": 5.0, "creatinina": 0.6, "glucosa": 75, "hs_CRP": 0.2,
    "rdw": 11.5, "leucocitos": 4.5, "linfocitos_pct": 40, "vcm": 88,
    "fosfatasa_alcalina": 45,
}
PERFIL_PEOR_CASO = {
    "albumina": 2.5, "creatinina": 3.0, "glucosa": 300, "hs_CRP": 50.0,
    "rdw": 20.0, "leucocitos": 20.0, "linfocitos_pct": 8, "vcm": 105,
    "fosfatasa_alcalina": 200,
}


def test_valores_extremos_no_explotan():
    """En los bordes de `BIOMARKER_SPECS` la fórmula tiene que seguir siendo
    finita y mantener el orden mejor < peor.

    Regresión: escrita literal como en el paper (M = 1 - exp(k), después
    ln(1 - M)), el perfil malo hacía que exp(k) cayera bajo el epsilon del
    float, M quedara exactamente en 1.0 y ln(1 - M) = ln(0) lanzara
    `ValueError: math domain error`. Importa fuera de este test: `montecarlo.py`
    llama `phenoage_years()` miles de veces sobre estados con ruido, que es
    justo donde aparecen estos valores.
    """
    for edad in (18, 40, 90):
        mejor = compute(PERFIL_MEJOR_CASO, edad, "M").edad_biologica
        peor = compute(PERFIL_PEOR_CASO, edad, "M").edad_biologica
        assert math.isfinite(mejor) and math.isfinite(peor)
        assert mejor < peor, (edad, mejor, peor)


def test_extrapolacion_fuera_del_rango_de_ajuste():
    """LIMITACIÓN CONOCIDA, no un error de unidades.

    PhenoAge se ajustó sobre adultos de NHANES III (20–84 años) y el mapeo
    score-de-mortalidad -> edad no tiene ni piso ni techo: un perfil de
    laboratorio casi perfecto da edades muy por debajo de la cronológica
    (negativas antes de los ~22 años) y uno catastrófico se pasa de 130.
    Queda anclado aquí para que se vea: si la app muestra este número crudo,
    el piso y el techo van en la capa de presentación (decisión de producto,
    no de la fórmula).
    """
    assert compute(PERFIL_MEJOR_CASO, 18, "M").edad_biologica < 0
    assert compute(PERFIL_MEJOR_CASO, 22, "M").edad_biologica == pytest.approx(0, abs=1)
    # A los 40 el mismo perfil da una aceleración de ~-24 años.
    assert compute(PERFIL_MEJOR_CASO, 40, "M").aceleracion < -20
    # Y el peor caso a los 40 se va por encima de 130.
    assert compute(PERFIL_PEOR_CASO, 40, "M").edad_biologica > 130
