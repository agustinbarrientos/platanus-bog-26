"""Database tables."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import CheckConstraint, Date, DateTime, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

#: Kept as plain strings with a CHECK rather than a Postgres ENUM: adding a
#: value to an ENUM needs a migration and cannot run inside some transactions,
#: which is a bad trade during a weekend of schema churn.
SEX_AT_BIRTH = ("female", "male", "intersex")
BLOOD_TYPES = ("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-")


class Profile(Base):
    """One row per authenticated user, created on first sight.

    Every field except the id is nullable. The intake form is answered one
    question at a time and a user who abandons it must be able to resume, so a
    half-filled profile is a normal state, not a broken one.
    """

    __tablename__ = "profiles"
    __table_args__ = (
        CheckConstraint(
            "sex_at_birth is null or sex_at_birth in ('female','male','intersex')",
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

    #: Matches auth.users.id. The foreign key is declared in schema.sql rather
    #: than here, because SQLAlchemy's create_all does not know about Supabase's
    #: auth schema and would try to create it.
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)

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


class Item(Base):
    """Scratch table from the Supabase connection test. Safe to drop."""

    __tablename__ = "items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(String(2000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
