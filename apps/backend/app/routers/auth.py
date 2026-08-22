"""Accounts and sessions.

The Flutter app talks only to this service. It holds no database key and no
identity-provider SDK — signing up, signing in and signing out are three
ordinary POSTs.

Sign in, keep the `token` from the response, and send it on everything after
that:

    Authorization: Bearer <token>

There is no refresh dance. The token is long-lived and revocable, which for an
app that stores it in the keychain is both simpler and no weaker: a refresh
token sitting in the same keychain protects against nothing extra.
"""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated

from email_validator import EmailNotValidError, validate_email
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import AfterValidator, BaseModel, ConfigDict, Field
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUserDep
from app.config import Settings, get_settings
from app.db import get_db
from app.models import AuthToken, Profile, User
from app.security import (
    burn_time,
    hash_password,
    hash_token,
    needs_rehash,
    new_token,
    verify_password,
)

log = logging.getLogger("app.auth")

router = APIRouter(prefix="/auth", tags=["auth"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]
SettingsDep = Annotated[Settings, Depends(get_settings)]

#: argon2 reads the whole input, so an unbounded password is a free way to make
#: the server do a lot of work. Long passphrases still fit comfortably.
MAX_PASSWORD_LENGTH = 128

_BAD_CREDENTIALS = "correo o contraseña incorrectos"


def _clean_email(value: str) -> str:
    """Validate and normalise in one place, so what is stored is what is
    looked up.

    Lower-cased whole, not just the domain. Local parts are case-sensitive by
    the letter of the spec and by the practice of nobody at all, and treating
    them otherwise would let Ana@ and ana@ become two accounts.

    `test_environment` keeps `.test`, `.example` and `.invalid` valid. RFC 2606
    reserves them for exactly this purpose and the project's own fixtures use
    them; rejecting them only breaks testing.
    """
    try:
        parsed = validate_email(value, check_deliverability=False, test_environment=True)
    except EmailNotValidError as exc:
        raise ValueError(str(exc)) from exc
    return parsed.normalized.lower()


Email = Annotated[str, AfterValidator(_clean_email)]


# ---- request and response models ----

class Credentials(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "examples": [{"email": "ana@moirai.test", "password": "una-clave-larga-123"}]
        },
    )

    email: Email
    password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)


class PasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    current_password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)
    new_password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)


class AccountDeletion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    created_at: datetime


class SessionOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "user": {
                    "id": "991d025c-8aae-4732-b350-e19535cd8f0b",
                    "email": "ana@moirai.test",
                    "created_at": "2026-08-22T14:03:11Z",
                },
                "token": "IrX3Zq…",
                "expires_at": "2026-11-20T14:03:11Z",
            }
        }
    )

    user: UserOut
    #: Store this. It is shown once and cannot be retrieved again — only a
    #: hash of it is kept, so a new one means signing in again.
    token: str
    token_type: str = "bearer"
    expires_at: datetime


# ---- helpers ----

def _check_password_length(password: str, settings: Settings) -> None:
    if len(password) < settings.min_password_length:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"la contraseña debe tener al menos {settings.min_password_length} caracteres",
        )


async def _issue_token(
    session: AsyncSession, settings: Settings, user: User, device: str | None
) -> SessionOut:
    token = new_token()
    expires_at = datetime.now(UTC) + timedelta(days=settings.token_days)
    session.add(
        AuthToken(
            user_id=user.id,
            token_hash=hash_token(token),
            expires_at=expires_at,
            device=(device or "")[:200] or None,
        )
    )
    return SessionOut(user=UserOut.model_validate(user), token=token, expires_at=expires_at)


async def _revoke_all(session: AsyncSession, user_id: uuid.UUID) -> None:
    for row in await session.scalars(
        select(AuthToken).where(AuthToken.user_id == user_id, AuthToken.revoked_at.is_(None))
    ):
        row.revoked_at = datetime.now(UTC)


async def _drop_expired(session: AsyncSession, user_id: uuid.UUID) -> None:
    """Housekeeping on the way through, so the table does not grow forever."""
    await session.execute(
        delete(AuthToken).where(
            AuthToken.user_id == user_id, AuthToken.expires_at < datetime.now(UTC)
        )
    )


# ---- endpoints ----

@router.post(
    "/signup",
    status_code=status.HTTP_201_CREATED,
    summary="Create an account and sign in",
    responses={409: {"description": "That email already has an account"}},
)
async def signup(
    body: Credentials,
    session: SessionDep,
    settings: SettingsDep,
    user_agent: Annotated[str | None, Header()] = None,
) -> SessionOut:
    _check_password_length(body.password, settings)

    user = User(email=body.email, password_hash=hash_password(body.password))
    session.add(user)
    try:
        # Flush rather than commit: the session dependency commits once the
        # response is built, so a later failure rolls the account back instead
        # of leaving a half-created one.
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        # The unique index is what decides this, not a prior SELECT — two
        # simultaneous signups with the same email would both pass a SELECT.
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="ya existe una cuenta con ese correo"
        ) from exc

    # The profile row exists from the start, so the first GET /me is a plain
    # read and the app never has to special-case a missing profile.
    await session.execute(
        insert(Profile).values(user_id=user.id).on_conflict_do_nothing(index_elements=["user_id"])
    )
    user.last_login_at = datetime.now(UTC)
    # created_at comes from a server default, so it is only on the object once
    # it has been read back.
    await session.refresh(user)

    log.info("auth.signup user_id=%s", user.id)
    return await _issue_token(session, settings, user, user_agent)


@router.post(
    "/login",
    summary="Sign in",
    responses={401: {"description": "Wrong email or password"}},
)
async def login(
    body: Credentials,
    session: SessionDep,
    settings: SettingsDep,
    user_agent: Annotated[str | None, Header()] = None,
) -> SessionOut:
    user = await session.scalar(select(User).where(User.email == body.email))

    if user is None:
        # Same work, same message, same status as a wrong password: otherwise
        # this endpoint answers "does this person have an account here?", which
        # for a health service is itself sensitive.
        burn_time()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=_BAD_CREDENTIALS)

    if not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=_BAD_CREDENTIALS)

    # argon2's recommended parameters get heavier over time. A successful login
    # is the only moment the plaintext is available to re-hash with them.
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)

    user.last_login_at = datetime.now(UTC)
    await _drop_expired(session, user.id)

    log.info("auth.login user_id=%s", user.id)
    return await _issue_token(session, settings, user, user_agent)


@router.get("/session", summary="Is this token still valid?")
async def read_session(user: CurrentUserDep, session: SessionDep) -> UserOut:
    """A cheap check for an app deciding whether to show the login screen."""
    row = await session.get(User, user.id)
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="la cuenta ya no existe")
    return UserOut.model_validate(row)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Sign out of this device",
)
async def logout(user: CurrentUserDep, session: SessionDep) -> None:
    row = await session.get(AuthToken, user.token_id)
    if row is not None and row.revoked_at is None:
        row.revoked_at = datetime.now(UTC)


@router.post(
    "/logout-all",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Sign out of every device",
)
async def logout_all(user: CurrentUserDep, session: SessionDep) -> None:
    await _revoke_all(session, user.id)
    log.info("auth.logout_all user_id=%s", user.id)


@router.post(
    "/password",
    summary="Change the password",
    responses={401: {"description": "The current password is wrong"}},
)
async def change_password(
    body: PasswordChange,
    user: CurrentUserDep,
    session: SessionDep,
    settings: SettingsDep,
    user_agent: Annotated[str | None, Header()] = None,
) -> SessionOut:
    _check_password_length(body.new_password, settings)

    row = await session.get(User, user.id)
    if row is None or not verify_password(body.current_password, row.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="la contraseña actual no coincide")

    row.password_hash = hash_password(body.new_password)

    # Every device is signed out, including this one, and a fresh token comes
    # back in the response. A password change is what someone does when they
    # think their account is compromised, and it is worth nothing if the
    # intruder's token keeps working.
    await _revoke_all(session, row.id)

    log.info("auth.password_changed user_id=%s", row.id)
    return await _issue_token(session, settings, row, user_agent)


@router.post(
    "/delete-account",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete the account and everything attached to it",
    responses={401: {"description": "The password is wrong"}},
)
async def delete_account(
    body: AccountDeletion,
    user: CurrentUserDep,
    session: SessionDep,
) -> None:
    row = await session.get(User, user.id)
    if row is None or not verify_password(body.password, row.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="la contraseña no coincide")

    # The profile and every token go with it, by ON DELETE CASCADE.
    await session.delete(row)
    log.info("auth.account_deleted user_id=%s", user.id)
