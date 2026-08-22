"""Capa 3 del motor (MOIRAI_ENGINE_SPEC.md §6): Monte Carlo.

Los dos tests que manda la spec son:

    "El abanico P10-P90 debe ensancharse con los años (más incertidumbre a
     futuro). Un perfil con biomarcadores imputados debe tener banda más ancha
     que uno con datos completos."

Están en `test_la_banda_se_ensancha_con_los_anios` y
`test_perfil_imputado_tiene_banda_mas_ancha`.

Todo corre con `seed` fija: el Monte Carlo es estocástico, pero un test que
falla una de cada veinte corridas no sirve para nada.
"""

from __future__ import annotations

import numpy as np
import pytest

from app.health_metrics import montecarlo
from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.phenoage import phenoage_years, to_formula_units

#: El perfil de la spec §9 con los 9 biomarcadores medidos — nada imputado.
PERFIL_COMPLETO = {
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
#: Los 6 del núcleo mínimo de §1; los otros 3 se imputan.
PERFIL_NUCLEO = {
    k: v
    for k, v in PERFIL_COMPLETO.items()
    if k not in {"linfocitos_pct", "vcm", "fosfatasa_alcalina"}
}
EDAD = 34.0


def _correr(perfil, escenarios=("ninguna",), n=4000, anios=10, seed=11):
    return montecarlo.run(perfil, EDAD, "F", list(escenarios), n, anios, seed=seed)


def _ancho(resultado, año):
    return resultado.curva_p90[año] - resultado.curva_p10[año]


# --- (1) N trayectorias con ruido estocástico anual ---------------------------


def test_corre_n_trayectorias_con_ruido():
    """Con ruido, N trayectorias que parten del mismo estado divergen."""
    (r,), _ = _correr(PERFIL_COMPLETO)
    assert r.curva_p10[-1] < r.curva_mediana[-1] < r.curva_p90[-1]


def test_sin_ruido_no_hay_abanico(monkeypatch):
    """Control del test anterior: si el ruido es cero, las N trayectorias son
    idénticas y la banda colapsa. Confirma que el ancho viene del ruido y no
    de un artefacto del cálculo de percentiles."""
    monkeypatch.setattr(
        montecarlo,
        "DYNAMICS",
        {n: d._replace(ruido_anual_sd=0.0) for n, d in DYNAMICS.items()},
    )
    (r,), _ = _correr(PERFIL_COMPLETO)
    for año in r.curva_anios:
        assert _ancho(r, año) == pytest.approx(0.0, abs=1e-9)


def test_la_semilla_hace_la_corrida_reproducible():
    (a,), _ = _correr(PERFIL_COMPLETO, seed=5)
    (b,), _ = _correr(PERFIL_COMPLETO, seed=5)
    (c,), _ = _correr(PERFIL_COMPLETO, seed=6)
    assert a.curva_mediana == b.curva_mediana
    assert a.curva_mediana != c.curva_mediana


def test_mas_trayectorias_estabilizan_la_mediana():
    """La mediana converge: dos semillas distintas se parecen más con N grande
    que con N chico. Es lo que justifica el N=5000 por defecto."""
    def dispersion(n):
        medianas = [_correr(PERFIL_COMPLETO, n=n, seed=s)[0][0].curva_mediana[-1]
                    for s in (1, 2, 3, 4)]
        return max(medianas) - min(medianas)

    assert dispersion(4000) < dispersion(200)


def test_respeta_los_topes_de_n_y_anios():
    """Los topes existen para que un caller autenticado no convierta esto en un
    quemador de CPU."""
    (r,), _ = _correr(PERFIL_COMPLETO, n=montecarlo.MAX_TRAYECTORIAS + 5000, anios=999)
    assert len(r.curva_anios) == montecarlo.MAX_ANIOS + 1


# --- (2) Percentiles P10 / mediana / P90 por año ------------------------------


def test_devuelve_una_curva_por_anio():
    for anios in (1, 10, 30):
        (r,), _ = _correr(PERFIL_COMPLETO, anios=anios)
        assert r.curva_anios == list(range(anios + 1))
        for serie in (r.curva_p10, r.curva_mediana, r.curva_p90):
            assert len(serie) == anios + 1


def test_los_percentiles_estan_ordenados_en_cada_anio():
    (r,), _ = _correr(PERFIL_COMPLETO)
    for año in r.curva_anios:
        assert r.curva_p10[año] <= r.curva_mediana[año] <= r.curva_p90[año]


def test_el_ultimo_punto_de_la_curva_es_el_horizonte():
    """Los campos planos que la app usa para rankear palancas tienen que ser
    exactamente el final del abanico, no un cálculo aparte."""
    (r,), _ = _correr(PERFIL_COMPLETO)
    assert r.curva_p10[-1] == r.edad_biologica_p10
    assert r.curva_mediana[-1] == r.edad_biologica_mediana
    assert r.curva_p90[-1] == r.edad_biologica_p90


def test_el_anio_cero_es_el_estado_de_partida():
    """En el año 0 no se ha aplicado ruido ni deriva: las N trayectorias siguen
    siendo el mismo punto, así que la banda tiene ancho cero y la mediana
    coincide con la Capa 1 sobre el perfil de entrada."""
    (r,), _ = _correr(PERFIL_COMPLETO)
    hoy = phenoage_years(to_formula_units(PERFIL_COMPLETO), EDAD)
    assert r.curva_mediana[0] == pytest.approx(hoy)
    assert _ancho(r, 0) == pytest.approx(0.0, abs=1e-9)


def test_la_mediana_de_la_curva_sube_con_los_anios():
    (r,), _ = _correr(PERFIL_COMPLETO)
    assert all(a < b for a, b in zip(r.curva_mediana, r.curva_mediana[1:]))


def test_cada_escenario_trae_su_propia_curva():
    resultados, _ = _correr(PERFIL_COMPLETO, escenarios=list(SCENARIOS))
    base = next(r for r in resultados if r.escenario == "ninguna")
    comb = next(r for r in resultados if r.escenario == "combinada")
    # Las curvas parten del mismo punto y se separan.
    assert base.curva_mediana[0] == pytest.approx(comb.curva_mediana[0])
    assert base.curva_mediana[-1] > comb.curva_mediana[-1]


# --- (3) EL test de §6: la banda se ensancha con los años ---------------------


def test_la_banda_se_ensancha_con_los_anios():
    """"El abanico P10-P90 debe ensancharse con los años." Se comprueba año a
    año, no solo entre el principio y el final: una banda que se ensancha y
    después se cierra pasaría el test flojo."""
    (r,), _ = _correr(PERFIL_COMPLETO, anios=20)
    anchos = [_ancho(r, año) for año in r.curva_anios]

    assert anchos[0] == pytest.approx(0.0, abs=1e-9)
    for año in range(1, len(anchos)):
        assert anchos[año] > anchos[año - 1], (
            f"año {año}: la banda se cerró, {anchos[año]:.3f} <= {anchos[año-1]:.3f}"
        )


def test_la_banda_se_ensancha_en_todos_los_escenarios():
    """No es una propiedad de la línea base: ninguna intervención debería
    hacer el futuro *más* conocido con el tiempo."""
    resultados, _ = _correr(PERFIL_COMPLETO, escenarios=list(SCENARIOS))
    for r in resultados:
        assert _ancho(r, 10) > _ancho(r, 5) > _ancho(r, 1), r.escenario


# --- (4) EL otro test de §6: imputar ensancha la banda -----------------------


def test_perfil_imputado_tiene_banda_mas_ancha():
    """"Un perfil con biomarcadores imputados debe tener banda más ancha que
    uno con datos completos." Mismo punto de partida numérico en los 6 del
    núcleo, misma semilla; la única diferencia es que 3 valores vienen de la
    tabla de medianas en vez de un laboratorio."""
    (completo,), sin_imputar = _correr(PERFIL_COMPLETO)
    (nucleo,), imputados = _correr(PERFIL_NUCLEO)

    assert sin_imputar == []
    assert sorted(imputados) == ["fosfatasa_alcalina", "linfocitos_pct", "vcm"]
    assert _ancho(nucleo, 10) > _ancho(completo, 10)


def test_cuantos_mas_imputados_mas_ancha_la_banda():
    """Monotonía: medir un biomarcador más tiene que angostar el abanico. Es lo
    que hace que la pantalla "qué conviene medir" signifique algo."""
    anchos = []
    for faltantes in ([], ["vcm"], ["vcm", "linfocitos_pct"],
                      ["vcm", "linfocitos_pct", "fosfatasa_alcalina"]):
        perfil = {k: v for k, v in PERFIL_COMPLETO.items() if k not in faltantes}
        (r,), _ = _correr(perfil)
        anchos.append(_ancho(r, 10))
    assert all(a < b for a, b in zip(anchos, anchos[1:])), anchos


def test_imputar_ensancha_pero_no_desplaza_la_mediana():
    """El ruido extra es simétrico: imputar debe expresar *menos certeza*, no
    un pronóstico peor. Si imputar empeorara la mediana, el motor estaría
    castigando a quien no subió exámenes."""
    (completo,), _ = _correr(PERFIL_COMPLETO)
    (nucleo,), _ = _correr(PERFIL_NUCLEO)
    assert nucleo.curva_mediana[-1] == pytest.approx(completo.curva_mediana[-1], abs=1.0)


def test_el_factor_de_sigma_es_el_que_ensancha(monkeypatch):
    """Control: con el factor en 1.0 (imputado == medido) la diferencia de
    ancho desaparece. Ata el efecto a `SIGMA_IMPUTADO_FACTOR` y no a otra cosa
    del perfil recortado."""
    monkeypatch.setattr(montecarlo, "SIGMA_IMPUTADO_FACTOR", 1.0)
    (completo,), _ = _correr(PERFIL_COMPLETO)
    (nucleo,), _ = _correr(PERFIL_NUCLEO)
    assert _ancho(nucleo, 10) == pytest.approx(_ancho(completo, 10), abs=1e-9)


# --- El fast path vectorizado -------------------------------------------------


def test_phenoage_vectorizado_coincide_con_la_capa_1():
    """`_phenoage_vector` es una ruta rápida, no un modelo distinto: tiene que
    dar exactamente lo mismo que `phenoage_years`. Si alguien toca una
    conversión de unidades en la Capa 1 y esto no la sigue, el abanico y el
    número de hoy dejarían de ser la misma fórmula."""
    rng = np.random.default_rng(3)
    base = np.array([[PERFIL_COMPLETO[n]] for n in PHENOAGE_BIOMARKERS], dtype=float)
    estados = base * rng.uniform(0.5, 1.8, size=(len(PHENOAGE_BIOMARKERS), 300))

    for edad in (20.0, 47.0, 88.0):
        vectorizado = montecarlo._phenoage_vector(estados, edad)
        escalar = [
            phenoage_years(
                to_formula_units(
                    {n: estados[i, t] for i, n in enumerate(PHENOAGE_BIOMARKERS)}
                ),
                edad,
            )
            for t in range(estados.shape[1])
        ]
        assert np.allclose(vectorizado, escalar, rtol=0, atol=1e-9)


def test_las_conversiones_de_unidades_se_derivan_de_la_capa_1():
    """El fast path no copia constantes: las saca de sondear
    `to_formula_units`. Esto lo comprueba contra la función real."""
    valores = {n: 2.0 for n in PHENOAGE_BIOMARKERS}
    esperado = to_formula_units(valores)
    for nombre in PHENOAGE_BIOMARKERS:
        clave = montecarlo._FORMULA_KEY[nombre]
        if nombre == "hs_CRP":
            obtenido = np.log(2.0) + montecarlo._LN_CRP_OFFSET
        else:
            obtenido = montecarlo._ESCALA[nombre] * 2.0
        assert obtenido == pytest.approx(esperado[clave])


def test_los_biomarcadores_se_mantienen_en_rango():
    """El clamp por año sigue aplicándose: sin él una trayectoria con ruido
    puede empujar hs_CRP a cero y romper el log de la Capa 1."""
    resultados, _ = _correr(PERFIL_NUCLEO, escenarios=list(SCENARIOS), anios=30, n=2000)
    for r in resultados:
        assert all(
            np.isfinite(v) for v in r.curva_p10 + r.curva_mediana + r.curva_p90
        ), r.escenario
