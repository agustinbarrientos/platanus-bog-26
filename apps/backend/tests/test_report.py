"""El reporte de salud descargable (docs/MOIRAI_REPORTE_SPEC.md): el builder
sobre el motor real, las reglas de rangos/ejes/triage, las barreras de
seguridad (ninguna frase nombra una enfermedad ni prescribe) y los dos
endpoints (`/reporte` JSON, `/reporte.pdf`) con la base de datos falsa."""

from __future__ import annotations

import re

import pytest

from app.health_metrics.ejes import evaluar_ejes, triage
from app.health_metrics.reference_ranges import clasificar
from app.report.builder import construir_reporte, fmt, fmt_delta, textos_del_reporte
from app.report.pdf import render_pdf
from app.report.schema import ReporteOut
from tests.test_biological_age_router import FakeSession, _client
from tests.test_chat_rag import CONTEXT

#: Spec §0 y §4: el reporte NUNCA nombra una enfermedad como diagnóstico, ni
#: prescribe, ni promete, ni afirma cobertura estadística. Si una plantilla
#: nueva cae en esto, este test la atrapa.
PROHIBIDAS = [
    r"\bdiabetes\b", r"\bprediabetes\b", r"\bhipertensi[oó]n\b", r"\banemia\b", r"\bc[aá]ncer\b",
    r"insuficiencia renal", r"h[ií]gado graso", r"\bobesidad\b", r"\bdemencia\b", r"\balzheimer\b",
    r"\btienes [a-záéíóú]+itis\b", r"\bpadeces\b", r"\bdiagn[oó]stico de\b",
    r"\btoma\b \d", r"\bmg al d[ií]a\b", r"\bdosis\b", r"\bmedicamento\b", r"\bsuplemento\b",
    r"\bvas a vivir\b", r"\btendr[aá]s\b", r"\bsufrir[aá]s\b", r"\b88 ?%", r"\bacierto\b",
    r"\banormal\b", r"\bcr[ií]tico\b", r"\briesgo alto\b", r"\brisk score\b", r"\bno vayas al m[eé]dico\b",
]


def _reporte(**kw):
    base = dict(
        nombre="Ana Rueda", edad=34, sexo="F", biomarcadores_guardados=CONTEXT["biomarcadores"],
        habitos=CONTEXT["habitos"], ancestria="mixta_latam", version_motor="0.3.0", n_trayectorias=400,
    )
    base.update(kw)
    return construir_reporte(**base)


# ---- Reglas ------------------------------------------------------------------------


def test_clasificar_rangos_con_banda_explicita_y_generica():
    assert clasificar("glucosa", 92, "F").estado == "en_rango"
    assert clasificar("glucosa", 110, "F").estado == "borde" and clasificar("glucosa", 110, "F").lado == "alto"
    assert clasificar("glucosa", 130, "F").estado == "fuera"
    assert clasificar("colesterol_total", 210, None).estado == "borde"
    assert clasificar("colesterol_total", 250, None).estado == "fuera"
    # Sin banda explícita: 10 % del ancho del rango por fuera = borde.
    assert clasificar("vcm", 101, None).estado == "borde"
    assert clasificar("vcm", 104, None).estado == "fuera"
    assert clasificar("albumina", 3.4, None).estado == "borde" and clasificar("albumina", 3.4, None).lado == "bajo"
    # Por sexo.
    assert clasificar("creatinina", 1.15, "F").estado == "borde" and clasificar("creatinina", 1.2, "F").estado == "fuera"
    assert clasificar("creatinina", 1.2, "M").estado == "en_rango"
    assert clasificar("hs_CRP", 2.9, None).estado == "en_rango" and clasificar("hs_CRP", 3.2, None).estado == "borde"
    assert clasificar("hs_CRP", 12, None).estado == "fuera"


def test_ejes_solo_cuentan_lo_medido_y_triage_por_reglas():
    ejes = evaluar_ejes({"glucosa": 118, "hs_CRP": 1.2, "colesterol_total": 262, "presion_sistolica": 146}, "M", {"glucosa": 0.9, "hs_CRP": -0.2})
    por_id = {e.id: e for e in ejes}
    assert por_id["metabolico"].nivel == "a_vigilar" and "Glucosa en ayunas" in por_id["metabolico"].senales
    assert por_id["inflamacion"].nivel == "optimo"
    assert por_id["cardio_metabolico"].nivel == "atencion"
    assert por_id["renal_hepatico"].nivel == "sin_datos" and por_id["hematologico"].nivel == "sin_datos"
    assert por_id["metabolico"].aporte_anios == pytest.approx(0.9)
    sug = triage(ejes)
    assert [s.eje for s in sug] == ["cardio_metabolico", "metabolico"]  # atención primero
    assert "cardiolog" in sug[0].profesional and all(("para que" in x.texto or "evalúe" in x.texto) for x in sug)
    # Todo en rango → control de rutina.
    assert triage(evaluar_ejes({"glucosa": 90}, "F"))[0].eje == "ninguno"


def test_formato_es_co():
    assert fmt(6.44) == "6,4" and fmt(8240, 0) == "8.240" and fmt(1234.5) == "1.234,5"
    assert fmt_delta(2.4) == "+2,4" and fmt_delta(-0.3) == "−0,3" and fmt_delta(0.01) == "0"


# ---- Builder sobre el motor real ----------------------------------------------------------


def test_reporte_sale_del_motor_y_tiene_las_seis_secciones():
    r = _reporte()
    ReporteOut.model_validate(r)  # la forma que documenta API.md
    assert r["meta"]["semilla"] == 20260822 and r["meta"]["trayectorias_por_escenario"] == 400 and r["meta"]["horizonte_anios"] == 10
    assert r["persona"] == {"nombre": "Ana Rueda", "edad": 34, "sexo": "F", "ancestria": "mixta_latam"}
    # §1: 9 de PhenoAge siempre; 3 inferidos en CONTEXT; los otros 3 no medidos no aparecen.
    foto = r["foto_hoy"]
    assert [b["nombre"] for b in foto["biomarcadores"]] == ["hs_CRP", "glucosa", "albumina", "creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"]
    assert foto["n_medidos"] == 6 and foto["n_inferidos"] == 3
    inferidos = {b["nombre"] for b in foto["biomarcadores"] if b["estado"] == "inferido"}
    assert inferidos == {"fosfatasa_alcalina", "linfocitos_pct", "vcm"}
    assert all(b["fuente"] == "inferido" and b["contribucion_anios"] == 0.0 for b in foto["biomarcadores"] if b["estado"] == "inferido")
    assert all(b["rango_referencia"] for b in foto["biomarcadores"])
    assert foto["rango_hoy"]["p10"] < foto["edad_biologica"] < foto["rango_hoy"]["p90"]
    assert "Estimación" in r["meta"]["disclaimer"] or "no diagnóstico" in r["meta"]["disclaimer"]
    # §2: cinco ejes; cardio-metabólico sin datos (no hay presión/colesterol/IMC en CONTEXT).
    assert [e["id"] for e in r["ejes"]] == ["inflamacion", "metabolico", "renal_hepatico", "hematologico", "cardio_metabolico"]
    assert {e["nivel"] for e in r["ejes"]} == {"optimo", "sin_datos"}
    # §3: curva base del motor, tres escenarios, ranking de todo lo que aplica.
    fu = r["futuros"]
    assert fu["curva_base"]["anios"] == list(range(11)) and len(fu["curva_base"]["mediana"]) == 11
    assert fu["sigues_igual"]["al_horizonte"]["mediana"] == fu["curva_base"]["mediana"][-1]
    assert fu["si_mejoras"]["anios_ganados"] > 0 and fu["si_mejoras"]["rango_ganados"][0] < fu["si_mejoras"]["anios_ganados"] < fu["si_mejoras"]["rango_ganados"][1]
    assert fu["si_te_descuidas"]["al_horizonte"]["mediana"] > fu["sigues_igual"]["al_horizonte"]["mediana"]
    assert len(fu["ranking"]) == 14  # 4 sueltas + 6 pares + 4 tríos que aplican en CONTEXT
    assert fu["ranking"] == sorted(fu["ranking"], key=lambda x: -x["anios_ganados"])
    assert all(x["fuentes"] for x in fu["ranking"])
    # §4: 2–3 palancas sueltas, con evidencia y con brecha.
    assert 2 <= len(r["recomendaciones"]) <= 3
    assert r["recomendaciones"][0]["id"] == "ejercicio_aerobico"
    for rec in r["recomendaciones"]:
        assert rec["evidencia"] and rec["rango_ganados"][0] <= rec["anios_ganados"] <= rec["rango_ganados"][1]
        assert rec["habito"] and 0 < rec["brecha"] <= 1
    # §5: todo en rango → control de rutina, siempre con disclaimer.
    assert r["consulta"]["sugerencias"][0]["eje"] == "ninguno" and "no una conclusión" in r["consulta"]["disclaimer"]
    # §6: los 3 imputados con su valor de información, del mayor al menor.
    assert [f["nombre"] for f in r["afinar"]["faltantes"]][0] == "vcm"
    assert r["afinar"]["ancho_banda_hoy"] > 0


def test_reporte_marca_fuera_de_rango_y_sugiere_profesional_sin_diagnosticar():
    bms = [
        {"nombre": "glucosa", "valor": 118, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "hs_CRP", "valor": 4.2, "unidad": "mg/L", "fuente": "documento"},
        {"nombre": "colesterol_total", "valor": 262, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "presion_sistolica", "valor": 146, "unidad": "mmHg", "fuente": "reportado"},
        {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"},
    ]
    r = _reporte(nombre="Ricardo", edad=52, sexo="M", biomarcadores_guardados=bms, habitos={"tabaco": True, "actividad": "baja"})
    estados = {b["nombre"]: b["estado"] for b in r["foto_hoy"]["biomarcadores"]}
    assert estados["glucosa"] == "borde" and estados["hs_CRP"] == "fuera" and estados["colesterol_total"] == "fuera" and estados["presion_sistolica"] == "fuera" and estados["imc"] == "fuera"
    fuentes = {b["nombre"]: b["fuente"] for b in r["foto_hoy"]["biomarcadores"]}
    assert fuentes["presion_sistolica"] == "reportado" and fuentes["imc"] == "calculado" and fuentes["albumina"] == "inferido"
    niveles = {e["id"]: e["nivel"] for e in r["ejes"]}
    assert niveles["inflamacion"] == "atencion" and niveles["cardio_metabolico"] == "atencion" and niveles["metabolico"] == "atencion"
    ejes_sugeridos = [s["eje"] for s in r["consulta"]["sugerencias"]]
    assert set(ejes_sugeridos) == {"inflamacion", "cardio_metabolico", "metabolico"}
    assert all("para que" in s["texto"] or "evalúe" in s["texto"] for s in r["consulta"]["sugerencias"])
    # Fuma y es sedentario: la cesación y el ejercicio están en las recomendaciones.
    ids = {x["id"] for x in r["recomendaciones"]}
    assert "cesacion_tabaco" in ids and "ejercicio_aerobico" in ids
    # Nota de hs-CRP > 10 no aplica (4,2); la nota de presión sí.
    notas = {b["nombre"]: b["nota"] for b in r["foto_hoy"]["biomarcadores"]}
    assert notas["presion_sistolica"] and notas["hs_CRP"] is None


def test_sin_biomarcadores_ni_habitos_es_honesto():
    r = _reporte(biomarcadores_guardados=[], habitos={})
    assert r["foto_hoy"]["n_medidos"] == 0 and r["foto_hoy"]["n_inferidos"] == 9
    assert all(e["nivel"] == "sin_datos" for e in r["ejes"])
    assert r["consulta"]["sugerencias"][0]["eje"] == "ninguno"
    # Hábitos desconocidos → las universales se ofrecen, tabaco/alcohol no.
    ids = {x["escenario"] for x in r["futuros"]["ranking"] if len(x["intervenciones"]) == 1}
    assert ids == {"ejercicio_aerobico", "dieta_mediterranea", "sueno_8h", "reducir_estres"}
    assert len(r["afinar"]["faltantes"]) == 9


def test_ya_en_el_peor_escenario_lo_dice():
    r = _reporte(habitos={"sueno_h": 5, "tabaco": True, "actividad": "baja", "alimentacion": "baja", "estres": "alto", "alcohol": "alto"})
    d = r["futuros"]["si_te_descuidas"]
    assert d["anios_ganados"] is None and "coincide con tu línea base" in d["texto"]
    assert d["al_horizonte"] == r["futuros"]["sigues_igual"]["al_horizonte"]
    assert len(r["recomendaciones"]) == 3


@pytest.mark.parametrize("kw", [
    {},
    {"biomarcadores_guardados": [], "habitos": {}},
    {"nombre": None, "edad": 52, "sexo": "M", "biomarcadores_guardados": [
        {"nombre": "glucosa", "valor": 130, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "hs_CRP", "valor": 12, "unidad": "mg/L", "fuente": "documento"},
        {"nombre": "colesterol_total", "valor": 262, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "presion_sistolica", "valor": 146, "unidad": "mmHg", "fuente": "reportado"},
        {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"},
        {"nombre": "albumina", "valor": 3.2, "unidad": "g/dL", "fuente": "documento"},
        {"nombre": "vcm", "valor": 104, "unidad": "fL", "fuente": "documento"},
    ], "habitos": {"tabaco": True, "alcohol": "alto"}},
])
def test_ninguna_frase_diagnostica_ni_prescribe(kw):
    r = _reporte(**kw)
    textos = textos_del_reporte(r)
    assert len(textos) > 100
    todo = "\n".join(textos).lower()
    for pat in PROHIBIDAS:
        assert not re.search(pat, todo), f"frase prohibida {pat!r} en el reporte"
    # Y lo que SÍ debe estar: disclaimer y "no diagnóstico" en portada y triage.
    assert "no diagnóstico" in r["meta"]["disclaimer"].lower()
    assert "no una conclusión" in r["consulta"]["disclaimer"]


# ---- PDF ---------------------------------------------------------------------------------------


def test_pdf_completo_y_resumen():
    r = _reporte()
    pdf = render_pdf(r)
    assert pdf[:5] == b"%PDF-" and len(pdf) > 20_000
    assert pdf.count(b"/Type /Page\n") >= 5 or pdf.count(b"/Type /Page") >= 5
    resumen = render_pdf(r, resumen=True)
    assert resumen[:5] == b"%PDF-" and len(resumen) < len(pdf)
    # El PDF incrusta las fuentes de la app.
    assert b"Nunito" in pdf and b"Fredoka" in pdf


def test_pdf_no_se_cae_con_casos_extremos():
    r = _reporte(biomarcadores_guardados=[], habitos={}, nombre=None)
    assert render_pdf(r)[:5] == b"%PDF-"
    r = _reporte(habitos={"sueno_h": 5, "tabaco": True, "actividad": "baja", "alimentacion": "baja", "estres": "alto", "alcohol": "alto"})
    assert render_pdf(r, resumen=True)[:5] == b"%PDF-"


# ---- Endpoints ---------------------------------------------------------------------------------


@pytest.fixture
def client():
    return _client(FakeSession())


def test_endpoint_json(client):
    r = client.post("/me/health-context/reporte", json={"n_trayectorias": 300})
    assert r.status_code == 200, r.text
    j = r.json()
    assert set(j) == {"meta", "persona", "resumen", "foto_hoy", "ejes", "futuros", "recomendaciones", "consulta", "afinar"}
    assert j["persona"]["nombre"] == "Ana Rueda" and j["meta"]["trayectorias_por_escenario"] == 300 and j["meta"]["version_motor"]
    assert j["meta"]["id"].startswith("rep_")
    # Sin cuerpo también funciona (defaults del motor, lo que la app usa).
    r2 = client.post("/me/health-context/reporte")
    assert r2.status_code == 200 and r2.json()["meta"]["trayectorias_por_escenario"] == 5000


def test_endpoint_pdf(client):
    r = client.post("/me/health-context/reporte.pdf", json={"n_trayectorias": 300})
    assert r.status_code == 200, r.text
    assert r.headers["content-type"].startswith("application/pdf")
    assert "attachment" in r.headers["content-disposition"] and "moirai-reporte-Ana-Rueda-" in r.headers["content-disposition"]
    assert r.headers["x-moirai-reporte-id"].startswith("rep_") and r.headers["cache-control"] == "no-store"
    assert r.content[:5] == b"%PDF-"
    r = client.post("/me/health-context/reporte.pdf", json={"n_trayectorias": 300, "resumen": True})
    assert r.status_code == 200 and "moirai-resumen-" in r.headers["content-disposition"]


def test_endpoint_422_sin_perfil():
    from datetime import date

    from app.models import Profile
    from tests.test_biological_age_router import USER_ID

    c = _client(FakeSession(profile=Profile(user_id=USER_ID, full_name="X", date_of_birth=date(1990, 1, 1), sex_at_birth=None)))
    r = c.post("/me/health-context/reporte")
    assert r.status_code == 422 and "sex_at_birth" in r.json()["detail"]
    r = c.post("/me/health-context/reporte", json={"n_trayectorias": 5, "otra": 1})
    assert r.status_code == 422
