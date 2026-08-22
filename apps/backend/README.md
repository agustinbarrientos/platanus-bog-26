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

## Layout

```
app/
  main.py            app factory: CORS, lifespan, router wiring
  config.py          env-driven settings
  routers/
    health.py        /health — what Render pings
    items.py         example CRUD, in-memory — delete when real endpoints exist
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
