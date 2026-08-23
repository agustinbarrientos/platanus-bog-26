"""`POST /me/health-context/phenoage`, `POST /me/health-context/montecarlo` y
`GET /engine/catalogo` a través del TestClient de FastAPI con la base de datos
falsa: la forma de la respuesta que la app consume (curvas, años ganados
pareados, palancas que aplican según hábitos, valor de información) y las
validaciones (claves inválidas, más de 3 palancas)."""

from __future__ import annotations

import uuid
from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.auth import CurrentUser, get_current_user
from app.db import get_db
from app.main import create_app
from app.models import HealthContext, Profile
from tests.test_chat_rag import CONTEXT

USER_ID = uuid.uuid4()


class FakeSession:
    def __init__(self, context: dict | None = None, profile: Profile | None = None) -> None:
        self.profile = profile or Profile(
            user_id=USER_ID, full_name="Ana Rueda", date_of_birth=date(1992, 3, 1),
            height_cm=164.0, weight_kg=62.0, sex_at_birth="F",
        )
        self.health = HealthContext(user_id=USER_ID, **(CONTEXT if context is None else context))

    async def get(self, model, key):
        if model is Profile:
            return self.profile
        if model is HealthContext:
            return self.health
        return None


def _client(session: FakeSession) -> TestClient:
    app = create_app()

    async def fake_db():
        yield session

    app.dependency_overrides[get_db] = fake_db
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id=USER_ID, email="ana@moirai.test", token_id=uuid.uuid4()
    )
    return TestClient(app)


@pytest.fixture
def client() -> TestClient:
    return _client(FakeSession())


def test_phenoage_trae_contribuciones_y_percentil(client):
    r = client.post("/me/health-context/phenoage")
    assert r.status_code == 200, r.text
    j = r.json()
    assert sorted(j["campos_inferidos"]) == ["fosfatasa_alcalina", "linfocitos_pct", "vcm"]
    assert abs(j["aceleracion_referencia"]) < 2.2
    assert 1 <= j["percentil_poblacional"] <= 99
    assert set(j["contribuciones"]) == set(j["valores_usados"])
    for n in j["campos_inferidos"]:
        assert j["contribuciones"][n] == 0.0
    assert sum(j["contribuciones"].values()) == pytest.approx(j["aceleracion"] - j["aceleracion_referencia"], abs=0.05)


def test_montecarlo_por_defecto_ofrece_solo_lo_que_aplica_y_sus_combos(client):
    """CONTEXT: sueño 6 h, no fuma, actividad baja, alimentación media, estrés
    alto, alcohol sin registrar → aplican ejercicio, dieta (0,5), sueño y
    estrés; no tabaco ni alcohol. 4 sueltas + 6 pares + 4 tríos + la base = 15."""
    r = client.post("/me/health-context/montecarlo", json={"n_trayectorias": 300})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["escenarios"][0]["escenario"] == "ninguna"
    assert len(j["escenarios"]) == 15
    sueltas = {e["escenario"] for e in j["escenarios"] if len(e["intervenciones"]) == 1}
    assert sueltas == {"ejercicio_aerobico", "dieta_mediterranea", "sueno_8h", "reducir_estres"}
    assert all(len(e["intervenciones"]) <= 3 for e in j["escenarios"])
    assert j["brechas"] == {"actividad": 1.0, "alimentacion": 0.5, "tabaco": 0.0, "sueno": 1.0, "estres": 1.0, "alcohol": None}
    palancas = {p["id"]: p for p in j["palancas"]}
    assert palancas["cesacion_tabaco"]["aplica"] is False and palancas["reducir_alcohol"]["aplica"] is False
    assert palancas["dieta_mediterranea"]["brecha"] == 0.5 and palancas["dieta_mediterranea"]["aplica"] is True
    assert j["habitos_usados"] == CONTEXT["habitos"]
    assert j["semilla"] == 20260822 and j["horizonte_anios"] == 10 and j["trayectorias_por_escenario"] == 300

    base, *resto = j["escenarios"]
    assert base["anios_ganados"] == 0 and base["curva"]["anios"] == list(range(11))
    assert len(base["curva"]["mediana"]) == 11 and base["curva"]["p10"][10] < base["curva"]["mediana"][10] < base["curva"]["p90"][10]
    assert j["ancho_banda_hoy"] > 0  # 3 imputados → hoy ya hay banda
    assert base["curva"]["p90"][0] - base["curva"]["p10"][0] == pytest.approx(j["ancho_banda_hoy"], abs=0.02)
    for e in resto:
        assert e["aplica"] is True and e["anios_ganados"] > 0
        assert e["anios_ganados_p10"] < e["anios_ganados"] < e["anios_ganados_p90"]
        assert 80 < e["pct_futuros_que_mejoran"] <= 100
        assert e["esfuerzo"] == sum({"ejercicio_aerobico": 3, "dieta_mediterranea": 3, "sueno_8h": 2, "reducir_estres": 2}[k] for k in e["intervenciones"])
        assert e["ratio_impacto_esfuerzo"] == pytest.approx(e["anios_ganados"] / e["esfuerzo"], abs=0.01)
        assert e["descripcion"]
    assert len(j["muestra_trayectorias"]) == 40 and all(len(t) == 11 for t in j["muestra_trayectorias"])
    assert [v["nombre"] for v in j["valor_de_informacion"]][0] == "vcm"
    assert {c["habito"] for c in j["contribuciones_habitos"]} == {"actividad", "alimentacion", "tabaco", "sueno", "estres"}
    tab = next(c for c in j["contribuciones_habitos"] if c["habito"] == "tabaco")
    assert tab["direccion"] == "mejora" and tab["contribucion"] < 0


def test_montecarlo_escenarios_explicitos_y_combinaciones_off(client):
    r = client.post("/me/health-context/montecarlo", json={"escenarios": ["ejercicio_aerobico+sueno_8h", "combinada", "cesacion_tabaco"], "n_trayectorias": 200, "semilla": 7})
    assert r.status_code == 200, r.text
    j = r.json()
    assert [e["escenario"] for e in j["escenarios"]] == ["ninguna", "ejercicio_aerobico+sueno_8h", "combinada", "cesacion_tabaco"]
    assert j["semilla"] == 7
    combo = j["escenarios"][1]
    assert combo["intervenciones"] == ["ejercicio_aerobico", "sueno_8h"] and combo["esfuerzo"] == 5
    # No fuma: el tabaco se puede pedir, pero no aplica y no gana nada.
    tab = j["escenarios"][3]
    assert tab["aplica"] is False and tab["anios_ganados"] == 0
    # `combinada` incluye tabaco pero también ejercicio y dieta: aplica por esas.
    assert j["escenarios"][2]["aplica"] is True

    r = client.post("/me/health-context/montecarlo", json={"combinaciones": False, "n_trayectorias": 200})
    assert r.status_code == 200
    assert len(r.json()["escenarios"]) == 5  # base + 4 sueltas


@pytest.mark.parametrize(
    "malo",
    [["yoga"], ["ejercicio_aerobico+yoga"], ["ejercicio_aerobico+dieta_mediterranea+sueno_8h+reducir_estres"], ["ejercicio_aerobico+ejercicio_aerobico"]],
)
def test_montecarlo_rechaza_escenarios_invalidos(client, malo):
    r = client.post("/me/health-context/montecarlo", json={"escenarios": malo, "n_trayectorias": 100})
    assert r.status_code == 422
    assert "inválido" in r.json()["detail"]


def test_montecarlo_sin_habitos_ni_examenes():
    """Usuario recién registrado: todo imputado, sin hábitos. Se ofrecen las
    universales (brecha asumida 1), no tabaco/alcohol; la banda de hoy es ancha
    y el valor de información cubre los 9."""
    contexto = {**CONTEXT, "biomarcadores": [], "habitos": None}
    c = _client(FakeSession(contexto))
    r = c.post("/me/health-context/montecarlo", json={"combinaciones": False, "n_trayectorias": 300})
    assert r.status_code == 200, r.text
    j = r.json()
    assert {e["escenario"] for e in j["escenarios"]} == {"ninguna", "ejercicio_aerobico", "dieta_mediterranea", "sueno_8h", "reducir_estres"}
    assert all(v is None for v in j["brechas"].values())
    assert len(j["campos_inferidos"]) == 9 and len(j["valor_de_informacion"]) == 9
    assert j["ancho_banda_hoy"] > 8
    assert j["contribuciones_habitos"] == []


def test_montecarlo_422_sin_perfil():
    c = _client(FakeSession(profile=Profile(user_id=USER_ID)))
    assert c.post("/me/health-context/montecarlo", json={}).status_code == 422
    assert c.post("/me/health-context/phenoage").status_code == 422


def test_catalogo_del_motor_es_publico_y_coherente(client):
    r = client.get("/engine/catalogo")
    assert r.status_code == 200
    j = r.json()
    assert j["version"]
    assert {b["nombre"] for b in j["biomarcadores"] if b["phenoage"]} == {
        "hs_CRP", "glucosa", "albumina", "creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos",
    }
    crp = next(b for b in j["biomarcadores"] if b["nombre"] == "hs_CRP")
    assert crp["valor_min"] == 0.1 and crp["deriva_anual"] == 0.012 and crp["dispersion"] == {"tipo": "lognormal", "sigma": 1.0}
    assert [p["id"] for p in j["palancas"]] == ["ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco", "sueno_8h", "reducir_estres", "reducir_alcohol"]
    for p in j["palancas"]:
        assert p["habito"] and p["descripcion"] and 1 <= p["esfuerzo"] <= 10 and p["efectos_anuales"]
    assert j["combinacion"]["max_intervenciones"] == 3 and j["defaults"]["n_trayectorias"] == 5000
    # Sin token también responde (constantes, nada personal).
    assert TestClient(create_app()).get("/engine/catalogo").status_code == 200
