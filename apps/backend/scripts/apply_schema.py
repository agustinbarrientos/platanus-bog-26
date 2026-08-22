"""Apply schema.sql to the database in DATABASE_URL.

    python scripts/apply_schema.py

Every statement is idempotent, so this is safe to re-run after editing the file.

Uses asyncpg directly rather than the SQLAlchemy engine: SQLAlchemy sends
statements through PostgreSQL's extended (prepared) protocol, which accepts
exactly one command per call, and a schema file is many. asyncpg's bare
`execute()` uses the simple query protocol, which takes the whole file and runs
it in one implicit transaction.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import asyncpg  # noqa: E402

from app.config import get_settings  # noqa: E402


async def main() -> int:
    settings = get_settings()
    if not settings.database_url:
        print("✗ DATABASE_URL is not set")
        return 1

    sql = (Path(__file__).resolve().parents[1] / "schema.sql").read_text()
    dsn = settings.database_url.replace("postgresql+asyncpg://", "postgresql://")

    connection = await asyncpg.connect(dsn, statement_cache_size=0)
    try:
        await connection.execute(sql)
    finally:
        await connection.close()

    print("✓ schema applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
