"""FastAPI application factory."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings, get_settings
from app.routers import health, items

log = logging.getLogger("app")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        # Open shared clients / pools here and close them after the yield, so a
        # deploy tears them down cleanly instead of leaking sockets.
        log.info("api.starting environment=%s", settings.environment)
        yield
        log.info("api.stopped")

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs",
        openapi_url="/openapi.json",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        # Starlette rejects credentials + "*" at runtime; keep them consistent.
        allow_credentials="*" not in settings.cors_origin_list,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(items.router)

    @app.get("/", tags=["meta"], summary="Service banner")
    async def root() -> dict[str, str]:
        return {"service": settings.app_name, "docs": "/docs"}

    return app


app = create_app()
