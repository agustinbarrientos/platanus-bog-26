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

## Database (Supabase)

1. Run `schema.sql` in the Supabase SQL editor to create the `items` table.
2. Put the **transaction pooler** connection string (port 6543) in `.env` as
   `DATABASE_URL`, and the same value in Render → Environment.
3. Verify: `python scripts/check_db.py` — connects, writes a row, reads it
   back, deletes it.
4. Live check: `GET /health/ready` returns 200 with the database name, or 503
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

Users sign in against Supabase **directly from the frontend** with email and
password. No password ever reaches this service — it only receives an
already-signed JWT and verifies it offline against the project's JWKS keys
(ES256), checking signature, expiry, issuer and audience.

Do not add a signup endpoint here that proxies the password through. It puts
plaintext credentials into this service's logs and error traces for no gain.

```javascript
// apps/web
await supabase.auth.signUp({ email, password })
const { data } = await supabase.auth.getSession()
fetch(`${API}/me`, { headers: { Authorization: `Bearer ${data.session.access_token}` } })
```

Supabase dashboard checklist, or none of this works:

- Authentication → Providers → **Email** enabled
- **Confirm email** on (real accounts) — users must click the link before their first sign-in
- Authentication → URL Configuration → add the Vercel domain *and* `http://localhost:3000`
- Minimum password length 8+, and turn on leaked-password protection

The backend connects to Postgres as `postgres`, which **bypasses RLS**. RLS is
enabled on every table anyway, because that closes Supabase's PostgREST path
(reachable with the anon key) — but it is not what protects the API. Every
query must filter by `user_id` itself. That is the real access control.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness — Render pings this, keep it dependency-free |
| `GET` | `/health/ready` | Database reachable |
| `GET` | `/me` | Signed-in user + profile; creates the row on first sight |
| `PATCH` | `/me` | Save any subset of the profile fields |
| `DELETE` | `/me` | Erase this user's data |

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
  auth.py               JWT verification, CurrentUser dependency
  db.py                 engine, session dependency, Supabase URL fix-ups
  models.py             tables
  routers/
    health.py           /health (liveness) and /health/ready (database)
    profile.py          /me — the intake form
    items.py            scratch table from the connection test, safe to delete
schema.sql              the schema
scripts/apply_schema.py apply schema.sql (idempotent)
scripts/check_db.py     end-to-end connection test
```

## Adding endpoints

Make `app/routers/<thing>.py` with an `APIRouter`, then
`app.include_router(<thing>.router)` in `app/main.py`.

For a new secret: add the field to `Settings` in `app/config.py`, then set the
env var in Render (dashboard → Environment). Never commit `.env`.

## Deploy

Render → **New → Blueprint** → this repo. It reads `/render.yaml`, which pins
`rootDir: apps/backend`, and prompts for `CORS_ORIGINS` — set that to the web
app's deployed origin.

Watch out for:

- **Bind to `$PORT`.** Hardcoding 8000 fails the health check and rolls the deploy back.
- **Free plan sleeps** after ~15 min idle; the next request takes 30–50s. Ping it before a demo.
- **Keep `/health` dependency-free.** If it checks a database, a slow database becomes a failed deploy.

## Talking to it from `apps/web`

Set `NEXT_PUBLIC_API_BASE_URL` to `http://localhost:8000` locally and to the
`onrender.com` URL in Vercel, and add that Vercel origin to `CORS_ORIGINS` here
or the browser blocks the call.
