"""Settings, read once from the environment.

Render injects PORT and whatever you set in the dashboard. Everything here has
a working default so the app boots locally with no .env at all.
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

    #: Comma-separated list. Set this in Render to your frontend's URL once you
    #: have one; "*" is fine while nothing is authenticated with cookies.
    cors_origins: str = "*"

    # ---- supabase auth ----
    #: e.g. https://<project-ref>.supabase.co — used to locate the JWKS endpoint
    #: that verifies user tokens. No API key is needed: the backend reaches
    #: Postgres directly and only ever verifies already-signed JWTs.
    supabase_url: str = ""
    supabase_jwt_audience: str = "authenticated"
    #: How long a fetched signing key is trusted before it is re-fetched.
    jwks_cache_seconds: int = 3600

    # ---- database ----
    #: Supabase → Project Settings → Database → Connection string → Transaction
    #: pooler (port 6543). Either the postgresql:// or postgresql+asyncpg://
    #: form works; app.db normalizes it.
    database_url: str = ""
    #: Held separately so the password can be rotated without rewriting the URL.
    database_password: str = ""
    db_echo: bool = False

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
