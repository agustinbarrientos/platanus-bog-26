"""Moirai's voice: a thin, authenticated proxy in front of ElevenLabs.

Why a proxy and not a direct call from the app: the ElevenLabs key would have
to ship inside the APK to do it client-side, and a `--dart-define` is plain
text in the bundle — anyone can pull it out and spend the account's credits.
The key lives here, in the Render environment, exactly like ANTHROPIC_API_KEY,
and the app authenticates against *us* with the token it already has.

Three endpoints:

- `GET  /me/voice/estado` — is voice configured on this deployment? The app
  asks once and hides the speaker/microphone if not, instead of discovering a
  503 in the middle of a demo.
- `POST /me/voice/tts` — text (a chat reply) → streamed MP3. The text goes
  through `app.voice_text.para_voz` first so es-CO numbers and engine
  shorthand are *spoken* right; see that module for the rules.
- `POST /me/voice/stt` — recorded audio → transcript, to feed the chat's
  `message`.

Nothing is persisted: audio in, audio out, same request.
"""

from __future__ import annotations

import logging
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field
from starlette.background import BackgroundTask

from app.auth import CurrentUserDep
from app.config import Settings, get_settings
from app.voice_text import para_voz

log = logging.getLogger("app")

router = APIRouter(prefix="/me/voice", tags=["voice"])

SettingsDep = Annotated[Settings, Depends(get_settings)]

API_BASE = "https://api.elevenlabs.io/v1"

#: MP3 a 44,1 kHz / 128 kbps: se reproduce en Android e iOS sin transcodificar
#: y pesa ~1 KB por 60 ms de audio.
OUTPUT_FORMAT = "mp3_44100_128"

#: Connect corto (si ElevenLabs no responde, mejor fallar rápido y que la app
#: use su TTS local); read largo porque el cuerpo llega por streaming.
TIMEOUT = httpx.Timeout(connect=10.0, read=60.0, write=30.0, pool=10.0)

#: Ajustes de voz de Moirai. Coherentes con la regla de motion del producto
#: ("suave, nada parpadea"): estabilidad alta y estilo bajo dan una lectura
#: pareja y tranquila en vez de una locución con inflexiones; la velocidad
#: apenas por debajo de 1 porque las cifras necesitan aire para entenderse.
VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.75,
    "style": 0.0,
    "speed": 0.95,
    "use_speaker_boost": True,
}

#: Formatos que manda el paquete `record` en Android/iOS, más los que puede
#: traer un archivo adjunto. ElevenLabs acepta bastante más; esta lista existe
#: para rechazar temprano lo que claramente no es audio.
AUDIO_CONTENT_TYPES = {
    "audio/mpeg", "audio/mp3", "audio/mp4", "audio/m4a", "audio/x-m4a",
    "audio/aac", "audio/wav", "audio/x-wav", "audio/webm", "audio/ogg",
    "audio/opus", "audio/flac", "video/mp4", "application/octet-stream",
}


def _credenciales(settings: Settings) -> tuple[str, str]:
    """(api_key, voice_id) o 503. Se comprueban juntas a propósito: una key
    sin voz produciría audio con una voz que no es la de Moirai."""
    if not settings.elevenlabs_api_key:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ELEVENLABS_API_KEY no está configurada en este despliegue",
        )
    if not settings.elevenlabs_voice_id:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ELEVENLABS_VOICE_ID no está configurada en este despliegue",
        )
    return settings.elevenlabs_api_key, settings.elevenlabs_voice_id


def _error_upstream(codigo: int, cuerpo: str) -> HTTPException:
    """Traduce el error de ElevenLabs a algo que la app pueda mostrar sin
    filtrar detalles de la cuenta. El cuerpo solo va al log."""
    log.error("voice.upstream_error status=%s body=%s", codigo, cuerpo[:400])
    if codigo in (401, 403):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY, detail="la voz no está configurada correctamente"
        )
    if codigo == 429:
        return HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="demasiadas solicitudes de voz, intenta de nuevo en un momento",
        )
    # 402: sin créditos. Es lo más probable que pase en un plan gratis, y la
    # app debe poder distinguirlo para caer a su TTS local sin ruido.
    if codigo == 402:
        return HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED, detail="se acabaron los créditos de voz"
        )
    return HTTPException(status.HTTP_502_BAD_GATEWAY, detail="la voz no respondió correctamente")


class EstadoVozOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {"disponible": True, "modelo_tts": "eleven_flash_v2_5",
                        "modelo_stt": "scribe_v2", "max_caracteres": 1500}
        }
    )

    #: `false` → la app esconde el altavoz y el micrófono (o usa su TTS local).
    disponible: bool
    modelo_tts: str
    modelo_stt: str
    #: Techo de `texto` en `/tts`; por encima se recorta en la última frase
    #: que quepa, no a mitad de palabra.
    max_caracteres: int


class TtsIn(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {"texto": "Ejercicio es tu palanca #1: +2,4 años a 10 años (1,1–3,7)."}
        },
    )

    #: El `reply` del chat, tal cual. La normalización para voz la hace el
    #: servidor: la app no tiene que saber cómo se pronuncian sus propios
    #: formatos.
    texto: str = Field(min_length=1, max_length=8000)
    #: Voz distinta a la del despliegue. Solo para probar voces desde /docs
    #: antes de fijar ELEVENLABS_VOICE_ID; la app no lo manda.
    voice_id: str | None = Field(default=None, max_length=64)


class SttOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {"texto": "¿Por qué el ejercicio es mi primera palanca?",
                        "idioma": "spa", "confianza_idioma": 0.98}
        }
    )

    #: Listo para mandarlo como `message` a `/me/health-context/chat`.
    texto: str
    idioma: str | None
    confianza_idioma: float | None


@router.get("/estado", summary="Whether this deployment can speak and listen")
async def estado(user: CurrentUserDep, settings: SettingsDep) -> EstadoVozOut:
    return EstadoVozOut(
        disponible=bool(settings.elevenlabs_api_key and settings.elevenlabs_voice_id),
        modelo_tts=settings.tts_model,
        modelo_stt=settings.stt_model,
        max_caracteres=settings.tts_max_chars,
    )


@router.post(
    "/tts",
    summary="Speak a chat reply in Moirai's voice",
    response_class=StreamingResponse,
    responses={
        200: {"content": {"audio/mpeg": {}}, "description": "MP3 en streaming"},
        402: {"description": "La cuenta de ElevenLabs se quedó sin créditos"},
        502: {"description": "ElevenLabs rechazó la petición o no respondió"},
        503: {"description": "La voz no está configurada en este despliegue"},
    },
)
async def tts(body: TtsIn, user: CurrentUserDep, settings: SettingsDep) -> StreamingResponse:
    api_key, voz_default = _credenciales(settings)
    voz = body.voice_id or voz_default

    texto = para_voz(body.texto, max_chars=settings.tts_max_chars)
    if not texto:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="no queda nada que leer después de limpiar el texto",
        )

    payload = {
        "text": texto,
        "model_id": settings.tts_model,
        "language_code": "es",
        "voice_settings": VOICE_SETTINGS,
    }

    # El cliente y la respuesta se cierran en un BackgroundTask, no con `async
    # with`: la respuesta se va consumiendo mientras FastAPI ya devolvió el
    # StreamingResponse, así que cerrarlos aquí cortaría el audio a la mitad.
    client = httpx.AsyncClient(timeout=TIMEOUT)
    try:
        request = client.build_request(
            "POST",
            f"{API_BASE}/text-to-speech/{voz}/stream",
            headers={"xi-api-key": api_key, "accept": "audio/mpeg"},
            params={"output_format": OUTPUT_FORMAT},
            json=payload,
        )
        response = await client.send(request, stream=True)
    except httpx.RequestError as exc:
        await client.aclose()
        log.error("voice.tts_unreachable %s", exc)
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="no se pudo contactar la voz"
        ) from exc

    # El estado se revisa ANTES de devolver el StreamingResponse: una vez
    # empiezan a salir bytes ya no se puede cambiar el código HTTP.
    if response.status_code >= 400:
        cuerpo = (await response.aread()).decode("utf-8", "replace")
        await response.aclose()
        await client.aclose()
        raise _error_upstream(response.status_code, cuerpo)

    log.info(
        "voice.tts user_id=%s modelo=%s caracteres=%d", user.id, settings.tts_model, len(texto)
    )

    async def cerrar() -> None:
        await response.aclose()
        await client.aclose()

    return StreamingResponse(
        response.aiter_bytes(),
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store", "X-Caracteres": str(len(texto))},
        background=BackgroundTask(cerrar),
    )


@router.post(
    "/stt",
    summary="Transcribe what the user said, to send as a chat message",
    responses={
        402: {"description": "La cuenta de ElevenLabs se quedó sin créditos"},
        413: {"description": "El audio pesa más de MAX_AUDIO_MB"},
        502: {"description": "ElevenLabs rechazó la petición o no respondió"},
        503: {"description": "La voz no está configurada en este despliegue"},
    },
)
async def stt(
    user: CurrentUserDep,
    settings: SettingsDep,
    audio: Annotated[UploadFile, File(description="Grabación del micrófono (m4a, wav, webm, mp3…)")],
) -> SttOut:
    api_key, _ = _credenciales(settings)

    if audio.content_type and audio.content_type.split(";")[0] not in AUDIO_CONTENT_TYPES:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"tipo de archivo no soportado: {audio.content_type}",
        )

    contenido = await audio.read()
    limite = settings.max_audio_mb * 1024 * 1024
    if len(contenido) > limite:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"el audio supera {settings.max_audio_mb} MB",
        )
    if not contenido:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="el audio está vacío")

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                f"{API_BASE}/speech-to-text",
                headers={"xi-api-key": api_key},
                files={"file": (audio.filename or "audio.m4a", contenido, audio.content_type or "audio/m4a")},
                data={"model_id": settings.stt_model, "language_code": "es"},
            )
    except httpx.RequestError as exc:
        log.error("voice.stt_unreachable %s", exc)
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="no se pudo contactar la transcripción"
        ) from exc

    if response.status_code >= 400:
        raise _error_upstream(response.status_code, response.text)

    datos = response.json()
    texto = str(datos.get("text") or "").strip()
    log.info("voice.stt user_id=%s bytes=%d caracteres=%d", user.id, len(contenido), len(texto))

    return SttOut(
        texto=texto,
        idioma=datos.get("language_code"),
        confianza_idioma=datos.get("language_probability"),
    )
