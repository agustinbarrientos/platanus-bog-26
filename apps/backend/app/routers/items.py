"""Example CRUD router — delete this once you have real endpoints.

State lives in a module-level dict, which is only honest for a demo: Render
restarts the instance on every deploy and free instances spin down when idle,
so anything in here is gone. Swap in a database before you rely on it.
"""

from __future__ import annotations

from uuid import uuid4

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/items", tags=["items"])

_items: dict[str, "Item"] = {}


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class Item(ItemIn):
    id: str


@router.get("", summary="List items")
async def list_items() -> list[Item]:
    return list(_items.values())


@router.post("", status_code=status.HTTP_201_CREATED, summary="Create an item")
async def create_item(payload: ItemIn) -> Item:
    item = Item(id=str(uuid4()), **payload.model_dump())
    _items[item.id] = item
    return item


@router.get("/{item_id}", summary="Fetch one item")
async def get_item(item_id: str) -> Item:
    item = _items.get(item_id)
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="item not found")
    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete an item")
async def delete_item(item_id: str) -> None:
    if _items.pop(item_id, None) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="item not found")
