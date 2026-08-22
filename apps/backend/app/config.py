"""Settings, read once from the environment.

Render injects PORT and whatever you set in the dashboard. Everything here has
a working default, so the app boots locally with no .env at all and the only
thing you genuinely have to set anywhere is DATABASE_URL.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_name: str = "Platanus Bog 26 API"
    environment: Literal["development", "production"] = "development"
    log_level: str = "INFO"

    #: Comma-separated origins allowed to call the API. Only browsers enforce
    #: this, so it does nothing at all for the Flutter app; it matters the day
    #: something runs in a browser. "*" is safe here because no credentials
    #: ride along automatically — the token is a header the client sets itself.
    cors_origins: str = "*"

    # ---- auth ----
    #: How long an issued token stays valid. Long, because the app keeps it in
    #: the keychain and there is no refresh flow to paper over an expiry.
    #: Signing out revokes immediately regardless.
    token_days: int = 90
    #: Minimum accepted at signup. Length is the only rule worth enforcing;
    #: composition rules push people towards "Password1!" and nothing else.
    min_password_length: int = 8

    # ---- health-context chat agent ----
    #: console.anthropic.com → API Keys. Only needed for POST
    #: /me/health-context/chat and /me/health-context/biomarkers/extract;
    #: every other endpoint boots and runs without it.
    anthropic_api_key: str = ""
    #: Model behind POST /me/health-context/chat. Haiku by explicit choice:
    #: the answers are grounded Q&A over retrieved fragments, not open-ended
    #: reasoning, and this project optimizes cost over accuracy. Swap via the
    #: CHAT_MODEL env var (e.g. claude-sonnet-5) without a code change.
    chat_model: str = "claude-haiku-4-5"

    # ---- lab-exam upload ----
    #: Read into memory before base64-encoding for the Anthropic request, so
    #: this is a real ceiling on this process's memory use per upload, not
    #: just a courtesy limit — the first endpoint in this API that accepts
    #: raw file bytes.
    max_upload_mb: int = 10

    # ---- database ----
    #: Supabase → Project Settings → Database → Connection string → Transaction
    #: pooler (port 6543). Either the postgresql:// or postgresql+asyncpg://
    #: form works; app.db normalizes it.
    database_url: str = ""
    #: Held separately so the password can be rotated without rewriting the URL.
    database_password: str = ""
    db_echo: bool = False

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
