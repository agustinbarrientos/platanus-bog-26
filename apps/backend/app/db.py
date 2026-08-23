"""Database engine, session, and the URL fix-ups Supabase needs.

Two things about connecting to Supabase from a host like Render trip everyone
up, so they are handled here rather than left to whoever writes the env var:

  1. Supabase hands you a `postgresql://` URL. SQLAlchemy needs the driver
     named — `postgresql+asyncpg://` — or it reaches for psycopg2 and fails on
     an import error that says nothing about the real problem.
  2. That URL often carries `?sslmode=require`. That is a libpq parameter;
     asyncpg does not accept it and raises `TypeError: connect() got an
     unexpected keyword argument 'sslmode'`. asyncpg negotiates TLS with
     Supabase on its own, so the parameter is dropped.

The pooler matters too. Use Supabase's *transaction pooler* (port 6543), not
the direct connection: the direct host is IPv6-only and Render dials out over
IPv4, so it fails to resolve. pgbouncer in transaction mode cannot hold
server-side prepared statements, which is why the statement cache is switched
off below — without that you get random `prepared statement "__asyncpg_..."
already exists` errors under concurrency.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import TypeVar
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.config import Settings, get_settings

#: libpq query parameters that asyncpg rejects outright.
_LIBPQ_ONLY_PARAMS = {"sslmode", "channel_binding", "target_session_attrs"}


class Base(DeclarativeBase):
    pass


_Row = TypeVar("_Row", bound=Base)


async def get_or_create(
    session: AsyncSession, model: type[_Row], user_id, *, with_for_update: bool = False
) -> _Row:
    """Upsert-then-get, keyed by `user_id` as the primary key — the one
    lazy-row-per-user pattern `profiles` and `health_context` both need,
    written once instead of duplicated per router. Done as an upsert rather
    than select-then-insert so two parallel requests from a freshly loaded
    page cannot race into a duplicate-key error.

    `with_for_update` additionally locks the row until the caller's
    transaction ends. Needed by any read-modify-write that merges a JSONB
    column in Python (read the array, build a new full array, write it back)
    — without the lock, two concurrent writers both read the same starting
    array and each write back their own full copy; whichever commits last
    silently overwrites the other's, dropping data neither request was ever
    told about. A plain column update (no read-your-own-write merge step)
    doesn't need it: SQLAlchemy's unit of work only ever issues an UPDATE for
    the columns actually changed in that transaction, so two requests
    touching different columns already can't clobber each other.
    """
    await session.execute(
        insert(model).values(user_id=user_id).on_conflict_do_nothing(index_elements=["user_id"])
    )
    row = await session.get(model, user_id, with_for_update=with_for_update)
    assert row is not None
    return row


def normalize_database_url(url: str) -> str:
    """Make a copy-pasted Supabase URL usable by SQLAlchemy + asyncpg."""
    if not url:
        return url

    parts = urlsplit(url)
    scheme = parts.scheme
    if scheme in ("postgres", "postgresql"):
        scheme = "postgresql+asyncpg"

    query = [(k, v) for k, v in parse_qsl(parts.query) if k not in _LIBPQ_ONLY_PARAMS]
    return urlunsplit((scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))


_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine(settings: Settings | None = None) -> AsyncEngine:
    """Build the engine on first use, so the app still boots without a database."""
    global _engine
    if _engine is None:
        settings = settings or get_settings()
        if not settings.database_url:
            raise RuntimeError(
                "DATABASE_URL is not set. Put the Supabase transaction-pooler "
                "connection string (port 6543) in apps/backend/.env locally, and "
                "in the Render dashboard for the deployed service."
            )
        _engine = create_async_engine(
            normalize_database_url(settings.database_url),
            echo=settings.db_echo,
            # NullPool: pgbouncer already pools. A second pool on top of it just
            # holds connections open against Supabase's per-project ceiling.
            poolclass=NullPool,
            connect_args={"statement_cache_size": 0},
        )
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(get_engine(), expire_on_commit=False)
    return _session_factory


async def get_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency. Commits on success, rolls back on any exception."""
    async with get_session_factory()() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def dispose_engine() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None
