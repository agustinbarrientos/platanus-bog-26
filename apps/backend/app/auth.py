"""Who is calling.

The client sends one header:

    Authorization: Bearer <token>

That is the whole scheme. The token is looked up in `auth_tokens` on every
request, which costs one indexed row read and buys two things a self-contained
token cannot give you: signing out takes effect immediately, and an account
deleted a second ago stops answering at once.

There is nothing here about cookies, CSRF or CORS. Those exist because a
browser attaches cookies to requests it was tricked into making; a native app
never does, and a header is not attached to anything the app did not send
itself.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.db import get_db
from app.models import AuthToken
from app.security import hash_token

_UNAUTHENTICATED = {"WWW-Authenticate": "Bearer"}


@dataclass(frozen=True)
class CurrentUser:
    id: uuid.UUID
    email: str
    #: The token this request arrived with, so logout can revoke exactly the
    #: one device that asked and leave the user's other devices signed in.
    token_id: uuid.UUID


def _presented_token(request: Request) -> str | None:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    return token.strip() if scheme.lower() == "bearer" and token.strip() else None


async def get_current_user(
    request: Request,
    session: Annotated[AsyncSession, Depends(get_db)],
) -> CurrentUser:
    token = _presented_token(request)
    if not token:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            detail="falta el token de acceso",
            headers=_UNAUTHENTICATED,
        )

    record = await session.scalar(
        select(AuthToken)
        .where(AuthToken.token_hash == hash_token(token))
        # The user comes back in the same query. Loading it separately would
        # double the round trips on the single hottest path in the API.
        .options(joinedload(AuthToken.user))
    )

    # One message for every failure — not found, revoked, expired. Which of
    # them it was is not something a caller should be able to probe for.
    if record is None or not record.is_usable(datetime.now(UTC)) or record.user is None:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            detail="sesión inválida o expirada",
            headers=_UNAUTHENTICATED,
        )

    return CurrentUser(id=record.user.id, email=record.user.email, token_id=record.id)


CurrentUserDep = Annotated[CurrentUser, Depends(get_current_user)]
