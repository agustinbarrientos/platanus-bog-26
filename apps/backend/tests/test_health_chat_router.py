"""`POST /me/health-context/chat` through FastAPI's TestClient, with the
database session and the Anthropic client faked: what reaches the model
(system prompt, tools, tool_choice) and what comes back (`reply`, `history`,
`fuentes`), including the `buscar_mis_datos` round-trip."""

from __future__ import annotations

import uuid
from datetime import date
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.auth import CurrentUser, get_current_user
from app.chat_rag.prompt import REGISTROS
from app.db import get_db
from app.main import create_app
from app.models import HealthContext, Profile
from app.routers import health_chat
from tests.test_chat_rag import CONTEXT, RESULTADO

USER_ID = uuid.uuid4()


class FakeSession:
    def __init__(self) -> None:
        self.profile = Profile(
            user_id=USER_ID, full_name="Ana Rueda", date_of_birth=date(1992, 3, 1),
            height_cm=164.0, weight_kg=62.0, sex_at_birth="F",
        )
        self.health = HealthContext(user_id=USER_ID, **CONTEXT)

    async def get(self, model, key):
        if model is Profile:
            return self.profile
        if model is HealthContext:
            return self.health
        return None


def _text(text: str):
    return SimpleNamespace(
        stop_reason="end_turn",
        content=[SimpleNamespace(type="text", text=text)],
        usage=SimpleNamespace(input_tokens=100, output_tokens=20),
    )


def _tool_call(consulta: str, call_id: str = "toolu_1"):
    return SimpleNamespace(
        stop_reason="tool_use",
        content=[SimpleNamespace(type="tool_use", id=call_id, name="buscar_mis_datos", input={"consulta": consulta})],
        usage=SimpleNamespace(input_tokens=100, output_tokens=20),
    )


class FakeAnthropic:
    """Quacks like `AsyncAnthropic` for `client.messages.create(...)`."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls: list[dict] = []
        self.messages = self

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        return self._responses.pop(0)


@pytest.fixture
def client(monkeypatch):
    app = create_app()
    holder: dict = {"session": FakeSession()}

    async def fake_db():
        yield holder["session"]

    app.dependency_overrides[get_db] = fake_db
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id=USER_ID, email="ana@moirai.test", token_id=uuid.uuid4()
    )
    monkeypatch.setattr(health_chat, "get_anthropic_client", lambda: holder["fake"])
    with TestClient(app) as c:
        c.holder = holder  # type: ignore[attr-defined]
        yield c


def test_plain_turn_grounds_on_retrieved_fragments(client):
    fake = FakeAnthropic([_text("Tu glucosa en ayunas está en 92 mg/dL, medida en tu examen.")])
    client.holder["fake"] = fake

    r = client.post("/me/health-context/chat", json={"message": "¿Cómo está mi glucosa?", "resultado": RESULTADO})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["reply"].startswith("Tu glucosa")
    assert [m["role"] for m in body["history"]] == ["user", "assistant"]
    fuentes = {f["id"]: f for f in body["fuentes"]}
    assert "bio:glucosa" in fuentes and fuentes["bio:glucosa"]["grupo"] == "usuario"

    call = fake.calls[0]
    assert call["model"] == "claude-haiku-4-5"
    assert "[bio:glucosa]" in call["system"] and "Eres Moirai" in call["system"]
    assert "Ana Rueda" in call["system"]  # the core card knows who it is talking to
    assert "Ejercicio aeróbico regular" in call["system"]  # ...and the best lever from `resultado`
    assert [t["name"] for t in call["tools"]] == ["buscar_mis_datos"]
    assert call["tool_choice"] == {"type": "auto"}
    assert call["messages"] == [{"role": "user", "content": "¿Cómo está mi glucosa?"}]
    # a whole dump would be far bigger; the prompt stays compact
    assert len(call["system"]) < 12_000


def test_tool_round_trip_adds_sources(client):
    fake = FakeAnthropic([_tool_call("percentil poblacional"), _text("Estás en el percentil 68 de tu grupo.")])
    client.holder["fake"] = fake

    r = client.post(
        "/me/health-context/chat",
        json={"message": "dime algo que no esté en lo primero", "resultado": RESULTADO,
              "history": [{"role": "user", "content": "hola"}, {"role": "assistant", "content": "¡Hola!"}]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert len(fake.calls) == 2
    segunda = fake.calls[1]["messages"]
    assert segunda[-1]["role"] == "user"
    assert segunda[-1]["content"][0]["type"] == "tool_result"
    assert segunda[-1]["content"][0]["tool_use_id"] == "toolu_1"
    assert "[sim:poblacion]" in segunda[-1]["content"][0]["content"]
    assert "sim:poblacion" in {f["id"] for f in body["fuentes"]}
    # history stays plain text: no tool blocks leak to the client
    assert [m["role"] for m in body["history"]] == ["user", "assistant", "user", "assistant"]
    assert body["history"][-1]["content"] == "Estás en el percentil 68 de tu grupo."


def test_tool_rounds_are_bounded(client):
    fake = FakeAnthropic([_tool_call("a", "t1"), _tool_call("b", "t2"), _text("Con lo que tengo: ...")])
    client.holder["fake"] = fake
    r = client.post("/me/health-context/chat", json={"message": "¿qué sabes de mí?"})
    assert r.status_code == 200, r.text
    assert len(fake.calls) == 3
    assert fake.calls[0]["tool_choice"] == {"type": "auto"}
    assert fake.calls[1]["tool_choice"] == {"type": "auto"}
    assert fake.calls[2]["tool_choice"] == {"type": "none"}


def test_works_without_resultado_and_with_enfoque(client):
    fake = FakeAnthropic([_text("Eso lo explico así...")])
    client.holder["fake"] = fake
    r = client.post("/me/health-context/chat", json={"message": "¿qué significa esto?", "enfoque": "biomarcador:rdw"})
    assert r.status_code == 200, r.text
    assert r.json()["fuentes"][0]["id"] == "bio:rdw"
    assert "Todavía no hay una simulación" in fake.calls[0]["system"]


def test_unknown_fields_inside_resultado_are_ignored_but_not_at_top_level(client):
    client.holder["fake"] = FakeAnthropic([_text("ok")])
    tolerante = {**RESULTADO, "muestra_trayectorias": [[1, 2, 3]], "campo_nuevo": 1}
    assert client.post("/me/health-context/chat", json={"message": "hola", "resultado": tolerante}).status_code == 200
    assert client.post("/me/health-context/chat", json={"message": "hola", "otro": 1}).status_code == 422


def test_register_comes_from_body_then_stored_demografia_then_default(client):
    # Nothing stored, nothing sent → plain words.
    client.holder["fake"] = FakeAnthropic([_text("ok")])
    assert client.post("/me/health-context/chat", json={"message": "hola"}).status_code == 200
    assert REGISTROS["general"] in client.holder["fake"].calls[0]["system"]

    # Stored in the health context (what onboarding saves) → used.
    client.holder["session"].health.demografia = {**CONTEXT["demografia"], "perfil_conocimiento": "curioso"}
    client.holder["fake"] = FakeAnthropic([_text("ok")])
    assert client.post("/me/health-context/chat", json={"message": "hola"}).status_code == 200
    assert REGISTROS["curioso"] in client.holder["fake"].calls[0]["system"]

    # Sent on the request (what the app has locally) → wins over stored.
    client.holder["fake"] = FakeAnthropic([_text("ok")])
    r = client.post("/me/health-context/chat", json={"message": "hola", "perfil_conocimiento": "profesional"})
    assert r.status_code == 200
    system = client.holder["fake"].calls[0]["system"]
    assert REGISTROS["profesional"] in system and REGISTROS["curioso"] not in system

    # Closed vocabulary, like `demografia.perfil_conocimiento` itself.
    assert client.post("/me/health-context/chat", json={"message": "hola", "perfil_conocimiento": "experto"}).status_code == 422


def test_refusal_or_empty_reply_gets_a_safe_fallback(client):
    vacio = SimpleNamespace(stop_reason="refusal", content=[], usage=None)
    client.holder["fake"] = FakeAnthropic([vacio])
    r = client.post("/me/health-context/chat", json={"message": "recétame algo"})
    assert r.status_code == 200
    assert "profesional" in r.json()["reply"]


def test_503_when_the_api_key_is_missing(client, monkeypatch):
    def sin_clave():
        raise RuntimeError("ANTHROPIC_API_KEY is not set")

    monkeypatch.setattr(health_chat, "get_anthropic_client", sin_clave)
    r = client.post("/me/health-context/chat", json={"message": "hola"})
    assert r.status_code == 503
