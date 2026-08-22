"""Database tables."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

#: Kept as plain strings with a CHECK rather than a Postgres ENUM: adding a
#: value to an ENUM needs a migration and cannot run inside some transactions,
#: which is a bad trade during a weekend of schema churn.
SEX_AT_BIRTH = ("F", "M")
BLOOD_TYPES = ("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-")


class User(Base):
    """An account. This service owns it — Supabase is only the Postgres host.

    Email is stored already lower-cased and the unique index is on the plain
    column, so two accounts cannot differ by capitalisation alone. Normalising
    on the way in beats a functional index here, because every lookup then uses
    the same ordinary index without the caller having to remember `lower()`.
    """

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), nullable=False, unique=True)
    #: argon2id. Never logged, never serialised — it is absent from every
    #: response model on purpose.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuthToken(Base):
    """One signed-in device. Revoking a row signs that device out.

    The token itself is never stored, only its SHA-256, so this table is
    useless to anyone who manages to read it — including us. That is also why
    the value is shown to the client exactly once, at login: there is no way to
    look it up again afterwards, only to issue a new one.
    """

    __tablename__ = "auth_tokens"
    __table_args__ = (Index("auth_tokens_user_id_idx", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    #: Only so a user could recognise their own devices in a future "signed in
    #: on these devices" screen. Never used for any decision.
    device: Mapped[str | None] = mapped_column(String(200), nullable=True)

    user: Mapped[User] = relationship(lazy="raise")

    def is_usable(self, now: datetime) -> bool:
        return self.revoked_at is None and self.expires_at > now


class Profile(Base):
    """One row per user, created alongside the account.

    Every field except the id is nullable. The intake form is answered one
    question at a time and a user who abandons it must be able to resume, so a
    half-filled profile is a normal state, not a broken one.
    """

    __tablename__ = "profiles"
    __table_args__ = (
        CheckConstraint(
            "sex_at_birth is null or sex_at_birth in ('F','M')",
            name="profiles_sex_at_birth_valid",
        ),
        CheckConstraint(
            "blood_type is null or blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-')",
            name="profiles_blood_type_valid",
        ),
        CheckConstraint(
            "height_cm is null or (height_cm between 100 and 250)",
            name="profiles_height_plausible",
        ),
        CheckConstraint(
            "weight_kg is null or (weight_kg between 25 and 350)",
            name="profiles_weight_plausible",
        ),
        CheckConstraint(
            "date_of_birth is null or date_of_birth < current_date",
            name="profiles_dob_in_past",
        ),
    )

    #: Deleting the account deletes the health data with it. That is the
    #: behaviour you want automatic rather than remembered.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )

    full_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    #: Stored as a date, not an age. Age silently rots — a twin built today is
    #: wrong next birthday, and survival curves are very age-sensitive.
    date_of_birth: Mapped[date | None] = mapped_column(Date, nullable=True)
    height_cm: Mapped[float | None] = mapped_column(Numeric(5, 1), nullable=True)
    weight_kg: Mapped[float | None] = mapped_column(Numeric(5, 1), nullable=True)
    blood_type: Mapped[str | None] = mapped_column(String(3), nullable=True)
    sex_at_birth: Mapped[str | None] = mapped_column(String(10), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class HealthContext(Base):
    """One row per user: the longevity/risk-assessment intake — demographics,
    biomarkers, habits, family history and the caller's stated goals.

    Each field is a JSONB blob rather than its own table because the shape
    underneath (which biomarkers, which goals) is defined by whatever
    assessment produced it, not by this schema. A PATCH replaces a field
    wholesale — same "answer one question at a time" contract as `profiles`.
    """

    __tablename__ = "health_context"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )

    demografia: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    biomarcadores: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    habitos: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    historia_familiar: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    objetivos_usuario: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    #: What the assessment couldn't fill in — kept explicit rather than
    #: inferred from nulls, since a missing biomarker and one that came back
    #: normal-and-unmentioned are different things.
    datos_faltantes: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    notas_incertidumbre: Mapped[str | None] = mapped_column(Text, nullable=True)
    #: Set explicitly by the app when its onboarding flow finishes — not
    #: derived from field coverage, since onboarding covers app-only steps
    #: (nationality, alcohol, supplements, photo, genetic test) this schema
    #: doesn't track. The signal a new device/reinstall checks to skip
    #: onboarding for a user who already did it elsewhere.
    onboarding_completo: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
