"""FastAPI application factory."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.anthropic_client import dispose_anthropic_client
from app.config import Settings, get_settings
from app.db import dispose_engine
from app.routers import (
    auth, biological_age, health, health_chat, health_context, lab_upload, profile, report, voice,
)

log = logging.getLogger("app")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        log.info("api.starting environment=%s", settings.environment)
        try:
            yield
        finally:
            # Close database connections on shutdown; Supabase counts open
            # connections against the project ceiling even after the instance
            # stops serving.
            await dispose_engine()
            await dispose_anthropic_client()
            log.info("api.stopped")

    app = FastAPI(
        title=settings.app_name,
        version="0.2.0",
        lifespan=lifespan,
        docs_url="/docs",
        openapi_url="/openapi.json",
        # Keeps the token entered under **Authorize** across a page reload.
        # Without it every refresh of /docs signs you out, which makes testing
        # by hand needlessly painful.
        swagger_ui_parameters={"persistAuthorization": True},
    )

    # Only browsers enforce CORS, so none of this affects the Flutter app.
    # allow_credentials stays off: the token is a header the client sets
    # itself, never something the browser attaches on its own.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(profile.router)
    app.include_router(profile.profiles_router)
    app.include_router(health_context.router)
    app.include_router(biological_age.router)
    app.include_router(biological_age.catalogo_router)
    app.include_router(health_chat.router)
    app.include_router(lab_upload.router)
    app.include_router(report.router)
    app.include_router(voice.router)

    @app.get("/", tags=["meta"], summary="Service banner")
    async def root() -> dict[str, str]:
        return {"service": settings.app_name, "docs": "/docs"}

    return app


app = create_app()
