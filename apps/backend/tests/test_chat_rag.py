"""The chat retriever, end to end but offline: documents built from a demo
user + the spec §9 result, then the questions a real user asks and the chunks
each one must surface. No network, no database."""

from __future__ import annotations

import pytest

from app.chat_rag.chunks import estimate_tokens, fmt_delta, fmt_num, fmt_rango_delta
from app.chat_rag.documents import build_documents
from app.chat_rag.knowledge import KNOWLEDGE
from app.chat_rag.prompt import TOOL_BUSCAR, TOOL_NAME, build_system, render_tool_result
from app.chat_rag.retriever import buscar, retrieve, stem, tokenize
from app.health_metrics import phenoage

PERFIL = {
    "nombre": "Ana", "edad": 34, "sexo_biologico": "F",
    "estatura_cm": 164.0, "peso_kg": 62.0, "imc": 23.1,
}

#: The spec §3 / §9 demo case, as `/me/health-context` stores it.
CONTEXT = {
    "demografia": {"ancestria_reportada": "mixta_latam"},
    "biomarcadores": [
        {"nombre": "albumina", "valor": 4.4, "unidad": "g/dL", "fuente": "documento"},
        {"nombre": "creatinina", "valor": 0.8, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "glucosa", "valor": 92, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "hs_CRP", "valor": 2.1, "unidad": "mg/L", "fuente": "documento"},
        {"nombre": "rdw", "valor": 13.1, "unidad": "%", "fuente": "documento"},
        {"nombre": "leucocitos", "valor": 6.2, "unidad": "10^3/uL", "fuente": "documento"},
    ],
    "habitos": {"sueno_h": 6, "tabaco": False, "actividad": "baja", "alimentacion": "media", "estres": "alto"},
    "historia_familiar": ["diabetes_t2", "cardiovascular:madre"],
    "objetivos_usuario": ["energia", "prevencion", "longevidad"],
    "datos_faltantes": ["fosfatasa_alcalina", "linfocitos_pct", "vcm"],
    "notas_incertidumbre": "3 biomarcadores imputados de medianas NHANES por edad/sexo",
}


def _curva(hoy: float, fin: float, ancho: float) -> dict:
    anios = list(range(11))
    med = [hoy + (fin - hoy) * t / 10 for t in anios]
    return {
        "anios": anios,
        "mediana": med,
        "p10": [m - ancho * (t / 10) ** 0.5 for m, t in zip(med, anios, strict=True)],
        "p90": [m + ancho * (t / 10) ** 0.5 for m, t in zip(med, anios, strict=True)],
    }


#: Spec §8 result as `SimulacionResultado.toChatJson()` sends it.
RESULTADO = {
    "id": "sim_demo",
    "creado_en": "2026-08-22T10:00:00",
    "edad_cronologica": 34,
    "edad_biologica_hoy": 37.8,
    "trayectoria_baseline": _curva(37.8, 47.2, 4.1),
    "mejor_decision": {"intervenciones": ["ejercicio_aerobico"], "anios_ganados": 2.4,
                       "rango": [1.1, 3.7], "esfuerzo": 3, "ratio_impacto_esfuerzo": 0.8},
    "veredicto_gemelo": "Tu gemelo empezaría por ejercicio aeróbico regular antes que por cualquier otra cosa.",
    "porque": "Es la combinación con más años ganados por unidad de esfuerzo. Actúa sobre la inflamación (hs-CRP).",
    "shap_top_drivers": [
        {"variable": "hs_CRP", "contribucion": 1.2, "direccion": "empeora"},
        {"variable": "sueno_h", "contribucion": 0.6, "direccion": "empeora"},
        {"variable": "albumina", "contribucion": -0.8, "direccion": "mejora"},
    ],
    "comparacion_poblacional": {"fuente": "NHANES", "percentil_edad_biologica": 68,
                                "mensaje": "Tu edad biológica está por encima del promedio de tu grupo."},
    "incertidumbre": "3 de 9 biomarcadores fueron imputados; la banda es más ancha en consecuencia.",
    "descargo": "Estimación de riesgo poblacional, no diagnóstico.",
    "escenarios": [
        {"intervenciones": ["ejercicio_aerobico"], "etiqueta": "Ejercicio aeróbico regular",
         "anios_ganados": 2.4, "rango": [1.1, 3.7], "esfuerzo": 3, "ratio_impacto_esfuerzo": 0.8,
         "pct_futuros_que_mejoran": 79, "curva": _curva(37.8, 44.8, 3.9)},
        {"intervenciones": ["dieta_mediterranea"], "etiqueta": "Dieta mediterránea",
         "anios_ganados": 1.7, "rango": [0.5, 2.9], "esfuerzo": 3, "ratio_impacto_esfuerzo": 0.57,
         "pct_futuros_que_mejoran": 71, "curva": _curva(37.8, 45.5, 4.0)},
        {"intervenciones": ["ejercicio_aerobico", "dieta_mediterranea"],
         "etiqueta": "Ejercicio + dieta mediterránea",
         "anios_ganados": 3.6, "rango": [2.1, 5.1], "esfuerzo": 10, "ratio_impacto_esfuerzo": 0.36,
         "pct_futuros_que_mejoran": 86, "curva": _curva(37.8, 43.6, 3.8)},
    ],
    "intervenciones_catalogo": [
        {"id": "ejercicio_aerobico", "etiqueta": "Ejercicio aeróbico regular", "esfuerzo": 3,
         "icono": "directions_walk", "descripcion": "150 minutos a la semana de algo que te suba el pulso."},
        {"id": "dieta_mediterranea", "etiqueta": "Dieta mediterránea", "esfuerzo": 3,
         "icono": "restaurant", "descripcion": "Más verduras, legumbres, pescado y aceite de oliva."},
    ],
    "biomarcadores_usados": [
        {"nombre": "glucosa", "valor": 92, "unidad": "mg/dL", "fuente": "documento"},
        {"nombre": "vcm", "valor": 90, "unidad": "fL", "fuente": "inferido"},
    ],
    # The app never sends this (it is the bulk of the payload); if an old
    # client does, the router's `ResultadoIn` drops it before we get here.
}


def _pheno():
    return phenoage.compute({b["nombre"]: b["valor"] for b in CONTEXT["biomarcadores"]}, 34, "F")


@pytest.fixture(scope="module")
def docs():
    return build_documents(PERFIL, CONTEXT, _pheno(), RESULTADO)


def ids(chunks) -> list[str]:
    return [c.id for c in chunks]


# ---- formatting ----

def test_fmt_es_co():
    assert fmt_num(8240) == "8.240"
    assert fmt_num(6.43) == "6,4"
    assert fmt_num(4.0) == "4"
    assert fmt_num(0.75, 2) == "0,75"
    assert fmt_num(None) == "—"
    assert fmt_delta(2.4) == "+2,4"
    assert fmt_delta(-0.3) == "−0,3"
    assert fmt_delta(0.01) == "0"
    assert fmt_rango_delta(1.1, 3.7) == "entre +1,1 y +3,7"
    assert estimate_tokens("a" * 30) == 10


# ---- documents ----

def test_documents_cover_every_topic_with_unique_ids(docs):
    core, chunks = docs
    all_ids = ids(chunks)
    assert len(all_ids) == len(set(all_ids)), "chunk ids must be unique"
    for esperado in (
        "perfil", "habitos", "historia_familiar", "objetivos", "phenoage", "faltantes",
        "bio:glucosa", "bio:creatinina", "bio:vcm", "bio:imc",
        "sim:resumen", "sim:mejor_decision", "sim:escenario:0", "sim:escenario:2",
        "sim:baseline", "sim:porque", "sim:poblacion", "sim:incertidumbre", "sim:catalogo",
        "kb:phenoage", "kb:simulacion", "kb:banda", "kb:biomarcador:rdw",
        "kb:intervencion:ejercicio_aerobico", "kb:intervencion:cesacion_tabaco",
    ):
        assert esperado in all_ids, esperado
    assert core.grupo == "core"
    assert len(KNOWLEDGE) >= 12 + 4 + 10


def test_core_card_has_the_headline_numbers(docs):
    core, _ = docs
    assert "Ana" in core.texto and "34 años" in core.texto
    assert "Ejercicio aeróbico regular" in core.texto
    assert "+2,4" in core.texto and "entre +1,1 y +3,7" in core.texto
    assert "47,2" in core.texto  # baseline median at the horizon
    assert core.tokens < 260


def test_biomarker_chunks_distinguish_measured_from_imputed(docs):
    _, chunks = docs
    by_id = {c.id: c for c in chunks}
    assert "92 mg/dL" in by_id["bio:glucosa"].texto and "medido" in by_id["bio:glucosa"].texto
    assert "NO está medido" in by_id["bio:vcm"].texto and "imputo" in by_id["bio:vcm"].texto
    assert "no está registrado" in by_id["bio:colesterol_total"].texto
    # the fresh PhenoAge chunk names what was imputed
    assert "fosfatasa alcalina" in by_id["phenoage"].texto
    assert "imputado" in by_id["phenoage"].texto.lower()


def test_result_chunks_carry_rank_effort_and_band(docs):
    _, chunks = docs
    by_id = {c.id: c for c in chunks}
    mejor = by_id["sim:mejor_decision"].texto
    assert "Palanca #1" in mejor and "+2,4" in mejor and "entre +1,1 y +3,7" in mejor
    assert "Esfuerzo: 3 de 10" in mejor and "79 %" in mejor
    assert "44,8" in mejor and "47,2" in mejor  # with vs without
    tercera = by_id["sim:escenario:2"].texto
    assert "Palanca #3" in tercera and "10 de 10" in tercera
    assert "año 10: 47,2" in by_id["sim:baseline"].texto
    assert "la inflamación (hs-CRP) +1,2" in by_id["sim:porque"].texto
    assert "Percentil 68" in by_id["sim:poblacion"].texto


def test_without_result_or_phenoage():
    core, chunks = build_documents({"nombre": None, "edad": None, "sexo_biologico": None}, {}, None, None)
    assert not any(c.id.startswith("sim:") for c in chunks)
    assert "Todavía no hay una simulación" in core.texto
    assert "sin registrar" in core.texto
    by_id = {c.id: c for c in chunks}
    assert "no puedo calcularlo" in by_id["phenoage"].texto
    assert "Falta fecha de nacimiento y sexo al nacer" in by_id["perfil"].texto
    # it still answers "what can you do" from the fallback set
    assert ids(retrieve(chunks, "hola, ¿qué sabes hacer?"))


# ---- retrieval ----

def test_tokenize_and_stem():
    toks = tokenize("¿Por qué mi rango es tan ancho? ¡Explícame las palancas!")
    assert "porque" in toks and "rango" in toks and "ancho" in toks and "palancas" in toks
    assert "que" not in toks and "mi" not in toks
    assert stem("palancas") == stem("palanca")
    assert stem("intervenciones") == stem("intervención".replace("ó", "o"))
    assert stem("hs_crp") == "hs_crp"


def test_question_about_a_biomarker_finds_the_users_value_first(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿Cómo está mi glucosa?"))
    assert got[0] == "bio:glucosa"
    assert "kb:biomarcador:glucosa" in got


def test_synonyms_bridge_everyday_words(docs):
    _, chunks = docs
    assert "bio:glucosa" in ids(retrieve(chunks, "¿Y el azúcar en sangre cómo anda?"))
    assert "kb:intervencion:cesacion_tabaco" in ids(retrieve(chunks, "¿Qué pasa si dejo de fumar?"))
    assert "bio:hs_CRP" in ids(retrieve(chunks, "¿Tengo inflamación?"))
    assert "sim:poblacion" in ids(retrieve(chunks, "¿Cómo estoy frente al promedio de la gente de mi edad?"))


def test_question_about_the_best_lever(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿Por qué el ejercicio es mi primera palanca?"))
    assert "sim:mejor_decision" in got[:3]
    assert "kb:intervencion:ejercicio_aerobico" in got or "kb:esfuerzo_ratio" in got


def test_question_about_the_band(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿Qué tan seguro estás de ese rango tan ancho?"))
    assert "kb:banda" in got
    assert "sim:incertidumbre" in got


def test_question_about_what_to_measure(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿Qué examen me conviene hacerme primero?"))
    assert "kb:que_medir" in got
    assert "faltantes" in got or any(g.startswith("bio:") for g in got)


def test_greeting_falls_back_to_overview(docs):
    _, chunks = docs
    got = retrieve(chunks, "hola")
    assert got and all(c.respaldo for c in got)
    assert "sim:resumen" in ids(got)


def test_follow_up_keeps_previous_topic(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿y por qué?", contexto_previo=["¿Cómo está mi glucosa?"]))
    assert "bio:glucosa" in got or "kb:biomarcador:glucosa" in got
    assert "sim:porque" in got


def test_enfoque_pins_the_lever_the_user_is_looking_at(docs):
    _, chunks = docs
    assert ids(retrieve(chunks, "¿por qué esta?", enfoque="escenario:2"))[0] == "sim:escenario:2"
    assert ids(retrieve(chunks, "¿qué significa esto?", enfoque="porque"))[0] == "sim:porque"
    assert ids(retrieve(chunks, "háblame de este dato", enfoque="biomarcador:rdw"))[0] == "bio:rdw"


def test_budget_is_respected_and_small_chunks_still_fit(docs):
    _, chunks = docs
    got = retrieve(
        chunks, "cuéntame todo: exámenes, biomarcadores, palancas, rango, percentil, por qué",
        presupuesto_tokens=300,
    )
    assert got and sum(c.tokens for c in got) <= 300
    amplio = retrieve(chunks, "cuéntame todo: exámenes, biomarcadores, palancas, rango, percentil, por qué")
    assert sum(c.tokens for c in amplio) <= 1600 and len(amplio) <= 8


def test_diversity_one_family_does_not_crowd_out_the_rest(docs):
    _, chunks = docs
    got = ids(retrieve(chunks, "¿Cómo están mis exámenes de sangre?"))
    assert sum(g.startswith("bio:") for g in got) >= 2
    assert len({g.split(":")[0] for g in got}) >= 2


def test_buscar_tool_excludes_what_was_shown(docs):
    _, chunks = docs
    got = ids(buscar(chunks, "glucosa", excluir={"bio:glucosa"}))
    assert got and "bio:glucosa" not in got and len(got) <= 3
    assert buscar(chunks, "xyzzy criptomonedas") == []


# ---- prompt ----

def test_system_prompt_is_moirai_and_lists_fragments(docs):
    core, chunks = docs
    frags = retrieve(chunks, "¿Cómo está mi glucosa?")
    system = build_system("Ana", core, frags)
    assert "Eres Moirai" in system and "Ana" in system
    assert "[bio:glucosa]" in system and core.texto in system
    assert TOOL_NAME in system and "nosotros" in system  # the rule that forbids it
    assert TOOL_BUSCAR["input_schema"]["required"] == ["consulta"]
    assert "No encontré nada" in render_tool_result([])
    assert "[kb:banda]" in render_tool_result(buscar(chunks, "rango"))
