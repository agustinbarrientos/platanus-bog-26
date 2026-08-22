"""Verifying Supabase user tokens.

The frontend signs users in against Supabase directly, so no password ever
reaches this service — it only ever sees an already-signed JWT and checks four
things: the signature is Supabase's, the token has not expired, it was issued
for this project, and it was meant for an authenticated user.

That last pair matters more than it looks. Without an issuer check, a token
minted by *any* Supabase project would be accepted, and anyone can create a
free project. The signature alone proves the token is genuine, not that it is
genuinely yours.

Keys are fetched from the project's JWKS endpoint and cached. Verification is
then offline: no network call to Supabase per request.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from typing import Annotated, Any

import httpx
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

_UNAUTHENTICATED = {"WWW-Authenticate": "Bearer"}

# auto_error=False so a missing header produces our 401 with a useful message
# rather than FastAPI's bare 403.
_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class CurrentUser:
    id: uuid.UUID
    email: str | None
    is_anonymous: bool


class _JwksCache:
    """Caches the project's signing keys, refreshing on an unknown `kid`.

    Supabase rotates keys. A rotation publishes a new `kid`, so a token we
    cannot match is the signal to re-fetch — but only once per token, or an
    attacker could force a fetch per request just by sending junk.
    """

    def __init__(self) -> None:
        self._keys: dict[str, jwt.PyJWK] = {}
        self._fetched_at: float = 0.0

    async def get(self, kid: str, settings: Settings) -> jwt.PyJWK:
        fresh = time.monotonic() - self._fetched_at < settings.jwks_cache_seconds
        if kid in self._keys and fresh:
            return self._keys[kid]

        await self._refresh(settings)
        if kid not in self._keys:
            raise HTTPException(
                status.HTTP_401_UNAUTHORIZED,
                detail="token was signed with an unknown key",
                headers=_UNAUTHENTICATED,
            )
        return self._keys[kid]

    async def _refresh(self, settings: Settings) -> None:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(settings.jwks_url)
                response.raise_for_status()
                document = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            # 503, not 401: the caller's token may be perfectly valid — we are
            # the ones who cannot check it right now.
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"could not fetch signing keys: {type(exc).__name__}",
            ) from exc

        self._keys = {key["kid"]: jwt.PyJWK(key) for key in document.get("keys", []) if "kid" in key}
        self._fetched_at = time.monotonic()

    def clear(self) -> None:
        self._keys = {}
        self._fetched_at = 0.0


_jwks = _JwksCache()


async def _decode(token: str, settings: Settings) -> dict[str, Any]:
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, detail="malformed token", headers=_UNAUTHENTICATED
        ) from exc

    kid = header.get("kid")
    if not kid:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, detail="token has no key id", headers=_UNAUTHENTICATED
        )

    key = await _jwks.get(kid, settings)
    try:
        return jwt.decode(
            token,
            key.key,
            algorithms=[header.get("alg", "ES256")],
            audience=settings.supabase_jwt_audience,
            issuer=settings.jwt_issuer,
            options={"require": ["exp", "sub", "aud", "iss"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, detail="token has expired", headers=_UNAUTHENTICATED
        ) from exc
    except jwt.PyJWTError as exc:
        # Deliberately vague to the caller; the specific reason (bad signature,
        # wrong issuer, wrong audience) is not something an attacker should be
        # able to probe for.
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, detail="invalid token", headers=_UNAUTHENTICATED
        ) from exc


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> CurrentUser:
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            detail="missing bearer token",
            headers=_UNAUTHENTICATED,
        )
    if not settings.supabase_url:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SUPABASE_URL is not set, so tokens cannot be verified",
        )

    claims = await _decode(credentials.credentials, settings)

    try:
        user_id = uuid.UUID(claims["sub"])
    except (KeyError, ValueError) as exc:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            detail="token subject is not a user id",
            headers=_UNAUTHENTICATED,
        ) from exc

    return CurrentUser(
        id=user_id,
        email=claims.get("email"),
        is_anonymous=bool(claims.get("is_anonymous", False)),
    )


CurrentUserDep = Annotated[CurrentUser, Depends(get_current_user)]
