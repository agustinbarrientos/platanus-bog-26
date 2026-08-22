"""Lazy singleton for the Anthropic client, so the app still boots without an
API key — only `POST /me/health-context/chat` needs one, same spirit as
`app/db.py`'s `get_engine()` not requiring DATABASE_URL until something
actually queries the database.
"""

from __future__ import annotations

from anthropic import AsyncAnthropic

from app.config import Settings, get_settings

_client: AsyncAnthropic | None = None


def get_anthropic_client(settings: Settings | None = None) -> AsyncAnthropic:
    global _client
    if _client is None:
        settings = settings or get_settings()
        if not settings.anthropic_api_key:
            raise RuntimeError(
                "ANTHROPIC_API_KEY is not set. Put it in apps/backend/.env locally, "
                "and in the Render dashboard for the deployed service."
            )
        _client = AsyncAnthropic(api_key=settings.anthropic_api_key)
    return _client


async def dispose_anthropic_client() -> None:
    global _client
    if _client is not None:
        await _client.close()
    _client = None
