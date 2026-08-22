"""The user's own profile — page one of the intake form."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUser, CurrentUserDep
from app.db import get_db
from app.models import Profile

#: Two ways in to the same three handlers.
#:
#: `/me` is the one to use: the token already says who is calling, so the app
#: never has to store the id, thread it through screens, or get it wrong.
#:
#: `/profiles/{user_id}` exists for callers that would rather be explicit. It
#: is *not* a way to reach another user — the id is checked against the token
#: and a mismatch is a 403. Trusting an id from the client here would mean
#: anyone with any valid token could read and overwrite anyone else's medical
#: record by changing a number in the URL.
router = APIRouter(prefix="/me", tags=["profile"])
profiles_router = APIRouter(prefix="/profiles", tags=["profile"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]

BloodType = Literal["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
SexAtBirth = Literal["female", "male", "intersex"]

#: The fields page one asks for, in the order the form presents them. Progress
#: is computed from this list so the UI counter cannot drift from what is
#: actually stored.
PAGE_ONE_FIELDS = (
    "full_name",
    "date_of_birth",
    "height_cm",
    "weight_kg",
    "blood_type",
    "sex_at_birth",
)

MIN_AGE_YEARS = 18
MAX_AGE_YEARS = 120


def _age_on(born: date, today: date) -> int:
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


class ProfilePatch(BaseModel):
    """Every field optional: the form saves one answer at a time.

    `exclude_unset` at the call site is what separates "not sent" from "sent as
    null", so a user can genuinely clear a field without every other field
    being wiped alongside it.
    """

    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={"examples": [{"weight_kg": 71.5}, {"blood_type": "O+"}]},
    )

    full_name: str | None = Field(default=None, min_length=1, max_length=120)
    date_of_birth: date | None = None
    # float, not Decimal: these are human measurements at one decimal place, not
    # money. Decimal renders as a *string* in JSON Schema, which produced
    # unreadable docs and made the frontend parse "163.0" instead of 163.0.
    height_cm: float | None = Field(default=None, ge=100, le=250)
    weight_kg: float | None = Field(default=None, ge=25, le=350)
    blood_type: BloodType | None = None
    sex_at_birth: SexAtBirth | None = None

    @field_validator("full_name")
    @classmethod
    def _strip(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("full_name cannot be blank")
        return cleaned

    @field_validator("date_of_birth")
    @classmethod
    def _plausible_age(cls, value: date | None) -> date | None:
        if value is None:
            return None
        age = _age_on(value, date.today())
        if value >= date.today():
            raise ValueError("date_of_birth must be in the past")
        if age > MAX_AGE_YEARS:
            raise ValueError(f"date_of_birth implies an age over {MAX_AGE_YEARS}")
        if age < MIN_AGE_YEARS:
            raise ValueError(f"this service is for people aged {MIN_AGE_YEARS} and over")
        return value


class ProfileOut(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "user_id": "991d025c-8aae-4732-b350-e19535cd8f0b",
                "full_name": "Ana Rueda",
                "date_of_birth": "1991-11-02",
                "height_cm": 163.0,
                "weight_kg": 58.4,
                "blood_type": "A-",
                "sex_at_birth": "female",
                "age": 34,
            }
        },
    )

    user_id: uuid.UUID
    full_name: str | None
    date_of_birth: date | None
    height_cm: float | None
    weight_kg: float | None
    # The Literal types, not bare str, so the docs list the valid values.
    blood_type: BloodType | None
    sex_at_birth: SexAtBirth | None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def age(self) -> int | None:
        """Derived, never stored — see the note on Profile.date_of_birth."""
        return _age_on(self.date_of_birth, date.today()) if self.date_of_birth else None


class MeOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "email": "ana@moirai.test",
                "profile": {
                    "user_id": "991d025c-8aae-4732-b350-e19535cd8f0b",
                    "full_name": "Ana Rueda",
                    "date_of_birth": "1991-11-02",
                    "height_cm": 163.0,
                    "weight_kg": 58.4,
                    "blood_type": "A-",
                    "sex_at_birth": "female",
                    "age": 34,
                },
                "answered": ["full_name", "date_of_birth", "height_cm", "weight_kg",
                             "blood_type", "sex_at_birth"],
                "remaining": [],
                "total": 6,
                "complete": True,
            }
        }
    )

    email: str
    profile: ProfileOut
    answered: list[str]
    remaining: list[str]
    total: int
    complete: bool


def _progress(profile: Profile) -> tuple[list[str], list[str]]:
    answered = [f for f in PAGE_ONE_FIELDS if getattr(profile, f) is not None]
    remaining = [f for f in PAGE_ONE_FIELDS if getattr(profile, f) is None]
    return answered, remaining


async def _get_or_create(session: AsyncSession, user_id: uuid.UUID) -> Profile:
    """The row is created at signup; this is the safety net for accounts that
    predate that, and for anything that creates a user by another route.

    Done as an upsert rather than select-then-insert so two parallel requests
    from a freshly loaded page cannot race into a duplicate-key error.
    """
    await session.execute(
        insert(Profile).values(user_id=user_id).on_conflict_do_nothing(index_elements=["user_id"])
    )
    profile = await session.get(Profile, user_id)
    assert profile is not None
    return profile


def _me(user_email: str, profile: Profile) -> MeOut:
    answered, remaining = _progress(profile)
    return MeOut(
        email=user_email,
        profile=ProfileOut.model_validate(profile),
        answered=answered,
        remaining=remaining,
        total=len(PAGE_ONE_FIELDS),
        complete=not remaining,
    )


async def _read(user: CurrentUser, session: AsyncSession) -> MeOut:
    return _me(user.email, await _get_or_create(session, user.id))


async def _update(patch: ProfilePatch, user: CurrentUser, session: AsyncSession) -> MeOut:
    profile = await _get_or_create(session, user.id)
    # exclude_unset is what separates "not sent" from "sent as null", so a user
    # can genuinely clear one field without wiping every other one.
    for field, value in patch.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    await session.flush()
    await session.refresh(profile)
    return _me(user.email, profile)


async def _erase(user: CurrentUser, session: AsyncSession) -> None:
    profile = await session.get(Profile, user.id)
    if profile is not None:
        await session.delete(profile)


def _owner(user_id: uuid.UUID, user: CurrentUserDep) -> CurrentUser:
    """The id in the path must be the id in the token.

    404 rather than 403 on a mismatch, deliberately: a 403 would confirm that
    the id belongs to a real account, which is a membership check anyone could
    run against a list of guessed ids.
    """
    if user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="perfil no encontrado")
    return user


OwnerDep = Annotated[CurrentUser, Depends(_owner)]


# ---- /me — the token says who you are ----

@router.get("", summary="The signed-in user and their profile")
async def read_me(user: CurrentUserDep, session: SessionDep) -> MeOut:
    return await _read(user, session)


@router.patch("", summary="Save one or more profile answers")
async def update_me(patch: ProfilePatch, user: CurrentUserDep, session: SessionDep) -> MeOut:
    return await _update(patch, user, session)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT, summary="Erase this user's data")
async def delete_me(user: CurrentUserDep, session: SessionDep) -> None:
    await _erase(user, session)


# ---- /profiles/{user_id} — the same thing, said out loud ----

_NOT_YOURS = {404: {"description": "No profile with that id belongs to this token"}}


@profiles_router.get(
    "/{user_id}", summary="The user and their profile", responses=_NOT_YOURS
)
async def read_profile(user: OwnerDep, session: SessionDep) -> MeOut:
    return await _read(user, session)


@profiles_router.patch(
    "/{user_id}", summary="Save one or more profile answers", responses=_NOT_YOURS
)
async def update_profile(patch: ProfilePatch, user: OwnerDep, session: SessionDep) -> MeOut:
    return await _update(patch, user, session)


@profiles_router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Erase this user's data",
    responses=_NOT_YOURS,
)
async def delete_profile(user: OwnerDep, session: SessionDep) -> None:
    await _erase(user, session)
