"""Liveness endpoints.

Render pings `healthCheckPath` to decide whether a deploy succeeded, so this
must stay dependency-free: it answers "the process is up", nothing more. When
you add a database, add a separate /health/ready that actually checks it —
don't make this one fail on a slow dependency or deploys start rolling back.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.config import Settings, get_settings

router = APIRouter(tags=["health"])


@router.get("/health", summary="Process is running")
async def health() -> dict[str, str]:
    settings: Settings = get_settings()
    return {"status": "ok", "environment": settings.environment}
