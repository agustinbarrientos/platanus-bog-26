# Backend — FastAPI

Python API for the project. Deploys to Render from the root `render.yaml`.

## Run locally

```bash
cd apps/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

- API: http://localhost:8000
- Interactive docs: http://localhost:8000/docs
- Health: http://localhost:8000/health

No `.env` is needed to boot — every setting has a working default. Copy
`.env.example` to `.env` when you want to override one.

**Building a frontend against this API?** Read [`API.md`](API.md) — every
endpoint, request/response shape, error format, and enum table, kept in
sync with the routers on every change.

## Database (Supabase)

1. Run `schema.sql` in the Supabase SQL editor, or `python scripts/apply_schema.py`.
   It creates `users`, `auth_tokens` and `profiles`, and migrates a database
   that still has `profiles` pointing at `auth.users`.
2. Put the **transaction pooler** connection string (port 6543) in `.env` as
   `DATABASE_URL`, and the same value in Render → Environment.
3. Verify: `GET /health/ready` returns 200 with the database name, or 503
   with the reason.

Use the **transaction pooler**, not the direct connection. Supabase's direct
host is IPv6-only and Render dials out over IPv4, so it will not resolve.

Two things `app/db.py` handles so you do not have to: it rewrites
`postgresql://` to `postgresql+asyncpg://`, and strips `?sslmode=require`
(a libpq parameter that asyncpg rejects). It also disables the prepared
statement cache, which pgbouncer in transaction mode cannot support.

If the password contains `@ : / ? #`, percent-encode it inside the URL —
`@` becomes `%40` — or the URL parser splits on it.

## Auth

This service owns the accounts. There is no identity provider behind it:
Supabase is the Postgres host and nothing else, and `auth.users` is not touched
anywhere. The frontend is a Flutter app that talks only to this API — it holds
no database key and no Supabase SDK.

The whole scheme is one header:

```
Authorization: Bearer <token>
```

- Passwords are hashed with **argon2id** (`app/security.py`) and never logged,
  returned, or forwarded.
- The **token** is 48 random bytes, stored only as a SHA-256, and looked up in
  `auth_tokens` on every request. That costs one indexed row read and buys the
  thing a self-contained token cannot: revocation that takes effect
  immediately, so logout, a password change, and account deletion all stop
  working *now*.
- Because the token is opaque there is **no refresh flow and no signing key**.
  Nothing to rotate, nothing to leak, one less secret in the dashboard.
- **No cookies, no CSRF, no CORS concerns.** Those exist because browsers
  attach cookies to requests they were tricked into making. A native app never
  does, and a header is not attached to anything the app did not send itself.

`AUTH.md` at the repository root is the client-facing version, with the Dart
client to copy.

The backend connects to Postgres as `postgres`, which **bypasses RLS**. RLS is
enabled on every table anyway, because that closes Supabase's PostgREST path
(reachable with the anon key) — and `public.users` holds password hashes, so
that door being shut matters. It is still not what protects the API: every
query must filter by `user_id` itself. That is the real access control.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness — Render pings this, keep it dependency-free |
| `GET` | `/health/ready` | Database reachable |
| `POST` | `/auth/signup` | Create an account, return a token |
| `POST` | `/auth/login` | Sign in, return a token |
| `GET` | `/auth/session` | Is this token still valid? |
| `POST` | `/auth/logout` | Revoke this device's token |
| `POST` | `/auth/logout-all` | Revoke every token on the account |
| `POST` | `/auth/password` | Change password, sign out every device |
| `POST` | `/auth/delete-account` | Delete the account and everything attached |
| `GET` | `/me` | Signed-in user + profile; creates the row on first sight |
| `PATCH` | `/me` | Save any subset of the profile fields |
| `DELETE` | `/me` | Erase this user's data |
| `GET` `PATCH` `DELETE` | `/profiles/{user_id}` | The same three, with the id named in the URL |

`/profiles/{user_id}` is a second door onto the same handlers for callers that
prefer an explicit id. The id is checked against the token and a mismatch is a
**404**, not a 403 — a 403 would confirm the id belongs to a real account,
which is a membership check anyone could run against a list of guessed ids.
Trusting the id instead would mean any valid token could read or overwrite any
user's medical record by changing a number in the URL.

`PATCH /me` is partial by design: the intake form saves one answer at a time
and a user who abandons at question three must be able to resume. Sending
`{"weight_kg": 74.2}` leaves every other field untouched; sending
`{"blood_type": null}` clears that one field only.

Page one collects `full_name`, `date_of_birth`, `height_cm`, `weight_kg`,
`blood_type`, `sex_at_birth`. The response carries `answered` / `remaining` /
`complete` so the UI progress counter is computed server-side and cannot drift
from what is actually stored.

Age is **derived from `date_of_birth`, never stored** — a stored age is wrong
by the user's next birthday, and survival curves are very age-sensitive.

## Layout

```
app/
  main.py               app factory: CORS, lifespan, router wiring
  config.py             env-driven settings
  auth.py               CurrentUser dependency — reads and checks the token
  security.py           password hashing, token generation
  db.py                 engine, session dependency, Supabase URL fix-ups
  anthropic_client.py    lazy Anthropic client singleton for the chat/extraction agents
  lab_extraction.py      extraction schema, unit conversion, Biomarcador validation (no FastAPI/DB)
  models.py             tables
  routers/
    health.py           /health (liveness) and /health/ready (database)
    auth.py             /auth — accounts and sessions
    profile.py          /me — the intake form
    health_context.py   /me/health-context — biomarkers, habits, risk-assessment intake
    biological_age.py   /me/health-context/{phenoage,montecarlo} — compute, no state of its own
    health_chat.py       /me/health-context/chat — agent grounded in the user's own data
    lab_upload.py         /me/health-context/biomarkers/extract — upload a lab exam, auto-save readings
  health_metrics/        pure compute: PhenoAge formula, NHANES imputation, Monte Carlo sim
schema.sql              the schema
scripts/apply_schema.py apply schema.sql (idempotent)
```

## Adding endpoints

Make `app/routers/<thing>.py` with an `APIRouter`, then
`app.include_router(<thing>.router)` in `app/main.py`.

For a new secret: add the field to `Settings` in `app/config.py`, then set the
env var in Render (dashboard → Environment). Never commit `.env`.

## Deploy

Render → **New → Blueprint** → this repo. It reads `/render.yaml`, which pins
`rootDir: apps/backend`. The only thing you must set by hand is `DATABASE_URL`
in the dashboard.

Watch out for:

- **Bind to `$PORT`.** Hardcoding 8000 fails the health check and rolls the deploy back.
- **Free plan sleeps** after ~15 min idle; the next request takes 30–50s. Ping it before a demo.
- **Keep `/health` dependency-free.** If it checks a database, a slow database becomes a failed deploy.

## Talking to it from the Flutter app

Set the app's base URL to the `onrender.com` URL, or `http://10.0.2.2:8000`
against a local server from the Android emulator — `localhost` there means the
emulator itself. `CORS_ORIGINS` does not apply to a native app.
