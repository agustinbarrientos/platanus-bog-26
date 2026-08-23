"""`app.voice_text.para_voz` and the three `/me/voice` endpoints, with the
ElevenLabs calls faked through `httpx.MockTransport` — no network, no key,
no credits spent. What is asserted upstream is the payload that would have
been sent (normalized text, model, voice id), which is the part that is easy
to break silently."""

from __future__ import annotations

import json
import uuid

import httpx
import pytest
from fastapi.testclient import TestClient

from app.auth import CurrentUser, get_current_user
from app.config import Settings, get_settings
from app.main import create_app
from app.routers import voice
from app.voice_text import para_voz

USER_ID = uuid.uuid4()
KEY = "sk_test"
VOZ = "voz_moirai"


# ── para_voz ────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "entrada, esperado",
    [
        ("Simulé 8.240 futuros", "Simulé 8240 futuros"),
        ("Simulé 1.234.567 futuros", "Simulé 1234567 futuros"),
        # La coma decimal de es-CO se queda: "6,4" ya se lee bien en español.
        ("tu edad es 6,4", "tu edad es 6,4"),
        ("+2,4 años", "más 2,4 años"),
        ("-1,2 años", "menos 1,2 años"),
        ("rango 1,1–3,7", "rango 1,1 a 3,7"),
        ("rango P10–P90", "rango percentil 10 a percentil 90"),
        ("el 79% mejora", "el 79 por ciento mejora"),
        ("palanca #1", "palanca número 1"),
        ("tu hs-CRP", "tu proteína C reactiva ultrasensible"),
        ("tu hs_CRP", "tu proteína C reactiva ultrasensible"),
        ("IMC 23,4 kg/m2", "índice de masa corporal 23,4 kilogramos por metro cuadrado"),
        ("glucosa 92 mg/dL", "glucosa 92 miligramos por decilitro"),
        ("**Ejercicio** es _tu_ palanca", "Ejercicio es tu palanca"),
        ("- primera\n- segunda", "primera\nsegunda"),
        ("mira [esto](https://x.com)", "mira esto"),
        ("usa `glucosa` aquí", "usa glucosa aquí"),
        ("## Título", "Título"),
    ],
)
def test_para_voz(entrada, esperado):
    assert para_voz(entrada) == esperado


def test_para_voz_es_idempotente():
    """Aplicarla dos veces no debe volver a transformar lo ya transformado
    (p. ej. convertir el "más" de "+2,4" otra vez)."""
    texto = "**Ejercicio** #1: +2,4 años (1,1–3,7), 79% de 8.240 futuros. hs-CRP 2,1 mg/L."
    una = para_voz(texto)
    assert para_voz(una) == una


def test_para_voz_vacio():
    assert para_voz("") == ""
    assert para_voz("   ") == ""


def test_para_voz_recorta_en_la_ultima_frase():
    texto = "Primera frase corta. Segunda frase que ya no cabe en el presupuesto."
    salida = para_voz(texto, max_chars=30)
    assert salida == "Primera frase corta."


def test_para_voz_recorta_sin_partir_palabras():
    """Sin un punto en la primera mitad, corta en el último espacio."""
    salida = para_voz("palabra " * 20, max_chars=25)
    assert salida.endswith("…")
    assert "palabr…" not in salida


# ── endpoints ───────────────────────────────────────────────────────────────


def _app(handler, *, api_key: str = KEY, voice_id: str = VOZ) -> TestClient:
    """TestClient con auth falsa, settings inyectados y todo httpx saliente
    redirigido a `handler`."""
    app = create_app()
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id=USER_ID, email="ana@example.com", token_id=uuid.uuid4()
    )
    app.dependency_overrides[get_settings] = lambda: Settings(
        elevenlabs_api_key=api_key, elevenlabs_voice_id=voice_id, database_url=""
    )

    real = httpx.AsyncClient

    def factory(**kwargs):
        kwargs.pop("transport", None)
        return real(transport=httpx.MockTransport(handler), **kwargs)

    voice.httpx.AsyncClient = factory  # type: ignore[assignment]
    client = TestClient(app)
    client._restaurar = lambda: setattr(voice.httpx, "AsyncClient", real)  # type: ignore[attr-defined]
    return client


@pytest.fixture
def restaurar_httpx():
    real = httpx.AsyncClient
    yield
    voice.httpx.AsyncClient = real  # type: ignore[assignment]


pytestmark = pytest.mark.usefixtures("restaurar_httpx")


def test_estado_disponible():
    c = _app(lambda r: httpx.Response(200))
    r = c.get("/me/voice/estado")
    assert r.status_code == 200
    assert r.json() == {
        "disponible": True,
        "modelo_tts": "eleven_flash_v2_5",
        "modelo_stt": "scribe_v2",
        "max_caracteres": 1500,
    }


def test_estado_sin_configurar():
    c = _app(lambda r: httpx.Response(200), api_key="", voice_id="")
    assert c.get("/me/voice/estado").json()["disponible"] is False


def test_tts_normaliza_y_devuelve_audio():
    visto: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        visto["url"] = str(request.url)
        visto["key"] = request.headers.get("xi-api-key")
        visto["body"] = json.loads(request.content)
        return httpx.Response(200, content=b"ID3fake-mp3-bytes")

    c = _app(handler)
    r = c.post("/me/voice/tts", json={"texto": "**Ejercicio**: +2,4 años de 8.240 futuros."})

    assert r.status_code == 200
    assert r.headers["content-type"] == "audio/mpeg"
    assert r.content == b"ID3fake-mp3-bytes"

    assert f"/text-to-speech/{VOZ}/stream" in visto["url"]
    assert "output_format=mp3_44100_128" in visto["url"]
    assert visto["key"] == KEY
    # Lo que se manda a la voz es el texto ya hablable, no el de pantalla.
    assert visto["body"]["text"] == "Ejercicio: más 2,4 años de 8240 futuros."
    assert visto["body"]["model_id"] == "eleven_flash_v2_5"
    assert visto["body"]["language_code"] == "es"


def test_tts_acepta_voice_id_explicito():
    visto: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        visto["url"] = str(request.url)
        return httpx.Response(200, content=b"x")

    c = _app(handler)
    r = c.post("/me/voice/tts", json={"texto": "hola", "voice_id": "otra_voz"})
    assert r.status_code == 200
    assert "/text-to-speech/otra_voz/stream" in visto["url"]


def test_tts_503_sin_credenciales():
    c = _app(lambda r: httpx.Response(200), api_key="")
    assert c.post("/me/voice/tts", json={"texto": "hola"}).status_code == 503

    c = _app(lambda r: httpx.Response(200), voice_id="")
    r = c.post("/me/voice/tts", json={"texto": "hola"})
    assert r.status_code == 503
    assert "VOICE_ID" in r.json()["detail"]


@pytest.mark.parametrize(
    "arriba, abajo",
    [(401, 502), (403, 502), (402, 402), (429, 429), (500, 502)],
)
def test_tts_traduce_errores_de_elevenlabs(arriba, abajo):
    c = _app(lambda r: httpx.Response(arriba, json={"detail": "nope"}))
    assert c.post("/me/voice/tts", json={"texto": "hola"}).status_code == abajo


def test_tts_503_si_no_hay_red():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("sin red", request=request)

    c = _app(handler)
    assert c.post("/me/voice/tts", json={"texto": "hola"}).status_code == 503


def test_tts_422_si_no_queda_nada_que_leer():
    c = _app(lambda r: httpx.Response(200))
    assert c.post("/me/voice/tts", json={"texto": "**``**"}).status_code == 422


def test_stt_transcribe():
    visto: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        visto["url"] = str(request.url)
        visto["cuerpo"] = request.content
        return httpx.Response(
            200,
            json={"text": "  ¿Por qué el ejercicio?  ", "language_code": "spa", "language_probability": 0.98},
        )

    c = _app(handler)
    r = c.post("/me/voice/stt", files={"audio": ("a.m4a", b"RIFFfake", "audio/m4a")})

    assert r.status_code == 200
    assert r.json() == {"texto": "¿Por qué el ejercicio?", "idioma": "spa", "confianza_idioma": 0.98}
    assert visto["url"].endswith("/speech-to-text")
    assert b"scribe_v2" in visto["cuerpo"]


def test_stt_rechaza_tipo_no_audio():
    c = _app(lambda r: httpx.Response(200))
    r = c.post("/me/voice/stt", files={"audio": ("x.pdf", b"%PDF", "application/pdf")})
    assert r.status_code == 415


def test_stt_413_si_pesa_demasiado():
    c = _app(lambda r: httpx.Response(200))
    grande = b"0" * (9 * 1024 * 1024)  # max_audio_mb = 8
    r = c.post("/me/voice/stt", files={"audio": ("a.m4a", grande, "audio/m4a")})
    assert r.status_code == 413


def test_stt_422_si_el_audio_esta_vacio():
    c = _app(lambda r: httpx.Response(200))
    r = c.post("/me/voice/stt", files={"audio": ("a.m4a", b"", "audio/m4a")})
    assert r.status_code == 422
