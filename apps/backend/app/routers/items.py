"""Items — the Supabase round-trip test.

Rows live in Postgres now, so anything created here survives a redeploy and an
idle spin-down. That is the whole point of the exercise: if a POST here is
still readable after Render restarts the instance, the database is genuinely
wired up.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import Item

router = APIRouter(prefix="/items", tags=["items"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class ItemOut(ItemIn):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime


@router.get("", summary="List items")
async def list_items(session: SessionDep) -> list[ItemOut]:
    rows = await session.scalars(select(Item).order_by(Item.created_at.desc()))
    return [ItemOut.model_validate(row) for row in rows]


@router.post("", status_code=status.HTTP_201_CREATED, summary="Create an item")
async def create_item(payload: ItemIn, session: SessionDep) -> ItemOut:
    item = Item(**payload.model_dump())
    session.add(item)
    # Flush rather than commit: the dependency commits once the response is
    # built, so a serialization failure rolls the row back instead of leaving
    # a committed row the caller never saw.
    await session.flush()
    await session.refresh(item)
    return ItemOut.model_validate(item)


@router.get(
    "/{item_id}",
    summary="Fetch one item",
    responses={404: {"description": "No item with that id"}},
)
async def get_item(item_id: uuid.UUID, session: SessionDep) -> ItemOut:
    item = await session.get(Item, item_id)
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="item not found")
    return ItemOut.model_validate(item)


@router.delete(
    "/{item_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an item",
    responses={404: {"description": "No item with that id"}},
)
async def delete_item(item_id: uuid.UUID, session: SessionDep) -> None:
    item = await session.get(Item, item_id)
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="item not found")
    await session.delete(item)
