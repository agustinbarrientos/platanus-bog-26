"""Prove the Supabase connection end to end.

    python scripts/check_db.py

Connects, creates the `items` table if it is missing, writes a row, reads it
back, deletes it, and reports what happened at each step. Run it before
touching the API — if this passes, any remaining failure is in the app, not the
database.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select, text  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.db import Base, get_engine, get_session_factory, normalize_database_url  # noqa: E402
from app.models import Item  # noqa: E402

OK = "\033[32m✓\033[0m"
BAD = "\033[31m✗\033[0m"


def _redact(url: str) -> str:
    """Never print the password, even in a local dev script."""
    if "@" not in url:
        return url
    creds, _, host = url.rpartition("@")
    scheme, _, user_pass = creds.partition("://")
    user = user_pass.split(":")[0]
    return f"{scheme}://{user}:***@{host}"


async def main() -> int:
    settings = get_settings()
    if not settings.database_url:
        print(f"{BAD} DATABASE_URL is not set in apps/backend/.env")
        return 1

    url = normalize_database_url(settings.database_url)
    print(f"  connecting to {_redact(url)}")

    engine = get_engine()

    async with engine.connect() as connection:
        database, user = (
            await connection.execute(text("SELECT current_database(), current_user"))
        ).one()
        print(f"{OK} connected — database={database} user={user}")

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    print(f"{OK} table `items` exists")

    async with get_session_factory()() as session:
        item = Item(name="supabase round-trip", description="written by check_db.py")
        session.add(item)
        await session.commit()
        print(f"{OK} inserted row id={item.id}")

        found = await session.scalar(select(Item).where(Item.id == item.id))
        if found is None:
            print(f"{BAD} row was not readable after commit")
            return 1
        print(f"{OK} read it back — name={found.name!r} created_at={found.created_at}")

        total = await session.scalar(select(Item))
        count = len((await session.scalars(select(Item))).all())
        print(f"{OK} table holds {count} row(s)")

        await session.delete(found)
        await session.commit()
        print(f"{OK} cleaned up the test row")

    await engine.dispose()
    print("\n  Supabase is wired up correctly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
