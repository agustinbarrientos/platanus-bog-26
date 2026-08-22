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

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
