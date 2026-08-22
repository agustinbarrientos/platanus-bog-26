"""Liveness and readiness.

`/health` answers "the process is up" and nothing else — Render pings it to
decide whether a deploy succeeded, so a slow database must never be able to
fail it and trigger a rollback. `/health/ready` is the one that actually
touches Postgres, and it returns 503 when it cannot.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.config import get_settings
from app.db import get_engine

router = APIRouter(tags=["health"])


@router.get("/health", summary="Process is running")
async def health() -> dict[str, str]:
    return {"status": "ok", "environment": get_settings().environment}


@router.get("/health/ready", summary="Database is reachable")
async def ready(response: Response) -> dict[str, Any]:
    settings = get_settings()
    if not settings.database_url:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "degraded", "database": {"ok": False, "detail": "DATABASE_URL is not set"}}

    try:
        async with get_engine().connect() as connection:
            result = await connection.execute(text("SELECT current_database(), version()"))
            database, version = result.one()
        return {
            "status": "ok",
            "database": {"ok": True, "name": database, "server": version.split(" on ")[0]},
        }
    except Exception as exc:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            "status": "degraded",
            "database": {"ok": False, "detail": f"{type(exc).__name__}: {exc}"},
        }
