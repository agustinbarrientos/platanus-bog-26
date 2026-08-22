"""Passwords and API tokens.

Two primitives, and nothing more than that on purpose.

**Passwords** are hashed with argon2id. Slow by design, because the whole point
is that guessing them in bulk is expensive.

**Tokens** are random strings. They are stored only as a SHA-256, so a database
dump yields nothing usable, and looked up on every request, so signing out
actually signs someone out. A plain hash is enough here where it would not be
for a password: 48 random bytes have nothing to guess.
"""

from __future__ import annotations

import hashlib
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import Argon2Error, InvalidHashError

_hasher = PasswordHasher()

#: Verified against when the email does not exist, so a login attempt for an
#: unknown address costs the same time as one for a known address. Without it,
#: response latency alone tells an attacker which emails are registered.
_DUMMY_HASH = _hasher.hash("a-password-that-belongs-to-nobody")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """False rather than raising, for any reason the hash fails to match."""
    try:
        return _hasher.verify(password_hash, password)
    except (Argon2Error, InvalidHashError):
        return False


def burn_time() -> None:
    """Spend the cost of one verification against a hash belonging to nobody."""
    try:
        _hasher.verify(_DUMMY_HASH, "wrong")
    except (Argon2Error, InvalidHashError):
        pass


def needs_rehash(password_hash: str) -> bool:
    """True once argon2's default parameters have moved on from this hash."""
    try:
        return _hasher.check_needs_rehash(password_hash)
    except (Argon2Error, InvalidHashError):
        return True


def new_token() -> str:
    """~64 characters of URL-safe randomness. Shown to the client once."""
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
