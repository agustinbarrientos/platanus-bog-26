# API reference

> **Keep this file current.** Any change to a router — a new endpoint, a
> renamed field, a different status code, a new required value — gets this
> file edited in the same change. An agent building `apps/web` or
> `apps/mobile` reads this instead of the source, so a stale entry here is
> worse than no entry at all.
>
> Live, authoritative docs also exist at `/docs` (Swagger UI) and
> `/openapi.json` once the server is running — this file is the version
> meant to be read without booting the service, and the place error-shape
> and cross-endpoint conventions (not visible in one route's schema) live.

## Base URL, auth, conventions

- Local: `http://localhost:8000`. Deployed: the Render URL for this service.
- Every endpoint except `/health`, `/auth/signup`, and `/auth/login` requires:
  ```
  Authorization: Bearer <token>
  ```
  The token comes from the `token` field of `/auth/signup` or `/auth/login`'s
  response. It is shown **once** — store it (Flutter: keychain). There is no
  refresh flow; the token is long-lived (`TOKEN_DAYS`, default 90) and
  revocable via `/auth/logout`.
- All request and response bodies are JSON. All timestamps are ISO 8601 UTC
  (`"2026-08-22T14:03:11Z"`).
- **Two different error shapes** — check which one you're getting:
  - **Pydantic validation failure** (bad JSON shape, wrong type, failed
    field constraint) → `422`, body is FastAPI's structured error:
    ```json
    {"detail": [{"type": "...", "loc": ["body", "field"], "msg": "...", "input": ...}]}
    ```
  - **Everything else this API rejects on purpose** (wrong password, unknown
    email, business-rule violation) → status varies (401/403/404/409/422),
    body is always:
    ```json
    {"detail": "human-readable message, usually in Spanish"}
    ```
- Every model in this file that has `extra="forbid"` rejects unknown JSON
  keys with a `422` rather than silently ignoring them — treat that as the
  default assumption for every request body below.
- Field/value names inside domain data (`biomarcadores`, `demografia`, ...)
  are Spanish; protocol-level names (`token`, `role`, `email`) are English.
  This is intentional, not inconsistent — match it when adding fields.

---

## Health

### `GET /health`
No auth. Liveness only — never touches the database, always fast.
```json
{"status": "ok", "environment": "development"}
```

### `GET /health/ready`
No auth. Touches Postgres. `200` if reachable, `503` otherwise.
```json
{"status": "ok", "database": {"ok": true, "name": "postgres", "server": "PostgreSQL 17.6"}}
```

---

## Auth (`/auth`)

No token required on `/signup` and `/login`. All others require the bearer token.

### `POST /auth/signup` → `201`
```json
// request
{"email": "ana@moirai.test", "password": "una-clave-larga-123"}
```
- `password`: 1–128 chars, must be ≥ `MIN_PASSWORD_LENGTH` (default 8) or `422`.
- `email` is normalized (lower-cased, validated) before storage/lookup.
- `409` if the email is already registered.
```json
// response — identical shape on /login and /password too (SessionOut)
{
  "user": {"id": "uuid", "email": "ana@moirai.test", "created_at": "2026-08-22T14:03:11Z"},
  "token": "IrX3Zq…",
  "token_type": "bearer",
  "expires_at": "2026-11-20T14:03:11Z"
}
```
An empty `profiles` row is created automatically — no need to call anything
else before `GET /me`.

### `POST /auth/login` → `200`
Same request/response shape as signup. `401` on wrong email or password (same
message and timing for both, deliberately — this endpoint never reveals
whether an email has an account).

### `GET /auth/session` → `200`
Cheap check for "is this token still valid" (e.g. deciding whether to show a
login screen on app start).
```json
{"id": "uuid", "email": "ana@moirai.test", "created_at": "2026-08-22T14:03:11Z"}
```
`401` if the token is invalid/expired/revoked, or the account no longer exists.

### `POST /auth/logout` → `204`
Signs out the device that sent this request only (revokes the current token).

### `POST /auth/logout-all` → `204`
Signs out every device.

### `POST /auth/password` → `200`
```json
{"current_password": "...", "new_password": "..."}
```
Revokes every existing session (including the caller's) and returns a fresh
`SessionOut` — same shape as signup. `401` if `current_password` is wrong.

### `POST /auth/delete-account` → `204`
```json
{"password": "..."}
```
Deletes the account and everything attached to it (profile, health context,
tokens) via cascade. `401` if the password is wrong.

---

## Profile (`/me`, `/profiles/{user_id}`)

`/me` is the one to use — the token says who's calling. `/profiles/{user_id}`
is the identical GET/PATCH/DELETE trio for a caller that wants the id
explicit in the URL; `user_id` **must** match the token's own id or it's a
`404` (not `403` — a 403 would leak which ids are real accounts).

Every profile field is optional and independently settable — a half-filled
profile is normal, not broken. `PATCH` only touches the fields you send
(`exclude_unset` semantics): omit a field to leave it alone, send it as
`null` to explicitly clear it.

### `GET /me` → `200`
```json
{
  "email": "ana@moirai.test",
  "profile": {
    "full_name": "Ana Rueda",
    "date_of_birth": "1991-11-02",
    "height_cm": 163.0,
    "weight_kg": 58.4,
    "blood_type": "A-",
    "sex_at_birth": "F",
    "age": 34
  },
  "answered": ["full_name", "date_of_birth", "height_cm", "weight_kg", "blood_type", "sex_at_birth"],
  "remaining": [],
  "total": 6,
  "complete": true
}
```
- `profile.age` is computed from `date_of_birth` on every read, never stored.
- `answered`/`remaining`/`total`/`complete` track the 6 `PAGE_ONE_FIELDS` —
  useful for an intake-progress UI.
- No `user_id` in the body — the token already identifies the caller; the
  `/profiles/{user_id}` variant carries the id in the URL instead.

### `PATCH /me` → `200`, same body shape as `GET`'s `profile`
```json
// any subset of these
{
  "full_name": "Ana Rueda",       // 1–120 chars
  "date_of_birth": "1991-11-02",  // must be in the past; implies age 18–120 or 422
  "height_cm": 163.0,             // 100–250
  "weight_kg": 58.4,              // 25–350
  "blood_type": "A-",             // one of A+ A- B+ B- AB+ AB- O+ O-
  "sex_at_birth": "F"             // "F" or "M" only — no other value accepted
}
```
`date_of_birth` and `sex_at_birth` matter beyond this endpoint: the
PhenoAge/Monte Carlo/chat endpoints below read age and sex **from here**, not
from anywhere else, and 422 if either is still unset. Set both before using them.

### `DELETE /me` → `204`
Erases the profile row only (not the account — see `/auth/delete-account`
for that).

---

## Health context (`/me/health-context`)

The longevity/risk-assessment intake: biomarkers, habits, family history,
stated goals. One row per user, created lazily on first read or write. Same
`PATCH` philosophy as `/me` — send whatever you were able to collect.

**Important:** age and sex are **not** part of this resource — they live on
the profile (`date_of_birth`/`sex_at_birth` via `/me`, above). Sending
`edad` or `sexo_biologico` inside `demografia` here is a `422` (unknown field).

### `GET /me/health-context` → `200`
Returns nulls/empty collections for anything never saved.

### `PATCH /me/health-context` → `200`, same shape both ways
```json
{
  "demografia": {
    "ancestria_reportada": "mixta_latam",
    "escolaridad_anios": 12,
    "nacionalidad": "chilena",
    "pais_residencia": "Chile"
  },
  "biomarcadores": [
    {"nombre": "hs_CRP", "valor": 2.1, "unidad": "mg/L", "fuente": "documento"},
    {"nombre": "glucosa", "valor": 92, "unidad": "mg/dL", "fuente": "documento"},
    {"nombre": "albumina", "valor": 4.4, "unidad": "g/dL", "fuente": "reportado"},
    {"nombre": "colesterol_total", "valor": 262, "unidad": "mg/dL", "fuente": "documento"},
    {"nombre": "presion_sistolica", "valor": 146, "unidad": "mmHg", "fuente": "reportado"},
    {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"}
  ],
  "habitos": {
    "sueno_h": 6,
    "sueno_calidad": "regular",
    "tabaco": false,
    "actividad": "baja",
    "alimentacion": "media",
    "alimentacion_patron": ["alto_ultraprocesados", "bajo_fibra"],
    "estres": "alto",
    "alcohol_frecuencia": "semanal",
    "alcohol_nivel": "moderado"
  },
  "historia_familiar": ["diabetes_t2", "alzheimer_materno"],
  "objetivos_usuario": ["energia", "prevencion"],
  "datos_faltantes": ["creatinina", "fosfatasa_alcalina", "APOE"],
  "notas_incertidumbre": "texto libre",
  "suplementos": [
    {"nombre": "Omega-3", "dosis": "1000mg", "frecuencia": "diaria"}
  ],
  "wearable": {"proveedor": "apple_health", "conectado": true},
  "onboarding_completo": true
}
```

**Merge semantics differ by field shape** — this is the one non-obvious part
of this endpoint:
- `demografia`, `habitos`, and `wearable` (objects) **merge**: a `PATCH` with
  only `{"habitos": {"estres": "medio"}}` updates just `estres` and leaves
  `sueno_h`, `tabaco`, etc. as they were. Send a sub-field as `null` to clear
  just that one.
- `biomarcadores`, `historia_familiar`, `objetivos_usuario`, `datos_faltantes`,
  `suplementos` (arrays) **replace wholesale** when sent — there's no single
  sensible "merge" for a list, so resend the full array each time you update it.
- `notas_incertidumbre` (string) and `onboarding_completo` (bool) replace
  when sent. `onboarding_completo` defaults to `false` and is **not**
  derived from field coverage — the app sets it explicitly when its own
  onboarding flow finishes (which may include steps, like a photo or genetic
  test upload, that this schema doesn't track — see below).
- `actividad`, `alimentacion`, `estres`, `sueno_calidad`, `alcohol_frecuencia`,
  `alcohol_nivel` are free text, not enums — send whatever granularity you
  collect (e.g. `"nulo"`/`"bajo"`/`"moderado"`/`"alto"` is fine, no need to
  collapse to fewer buckets before sending).
- `wearable` is connection status only (`proveedor`, `conectado`) — there is
  **no endpoint yet** for syncing actual wearable health data. Don't build a
  frontend flow assuming one exists.

**`biomarcadores[].nombre`** is a fixed vocabulary, not free text — an
unlisted name is a `422`, as is the wrong `unidad` for a name or a `valor`
outside its plausible range:

| `nombre` | `unidad` | plausible range | used by PhenoAge? |
|---|---|---|---|
| `hs_CRP` | `mg/L` | 0.01–200 | yes |
| `glucosa` | `mg/dL` | 30–600 | yes |
| `albumina` | `g/dL` | 1.5–6.0 | yes |
| `creatinina` | `mg/dL` | 0.2–15 | yes |
| `fosfatasa_alcalina` | `U/L` | 20–500 | yes |
| `linfocitos_pct` | `%` | 1–90 | yes |
| `vcm` | `fL` | 50–130 | yes |
| `rdw` | `%` | 10–25 | yes |
| `leucocitos` | `10^3/uL` | 1–50 | yes |
| `colesterol_total` | `mg/dL` | 50–500 | no (other risk models) |
| `presion_sistolica` | `mmHg` | 60–260 | no (other risk models) |
| `imc` | `kg/m2` | 10–80 | no (other risk models) |

Any of the 9 "used by PhenoAge" biomarkers you don't provide gets imputed
from an age/sex reference median when you call `/phenoage` or `/montecarlo`
— see below. `fuente` is free text (e.g. `"documento"` / `"reportado"` /
`"calculado"`), not validated against a fixed set.

### `POST /me/health-context/biomarkers/extract` → `200`

**Not JSON** — the one exception to the "every body is JSON" convention
above. Upload a lab-exam document as `multipart/form-data`, field name `file`:
```
Content-Type: multipart/form-data; boundary=...

--...
Content-Disposition: form-data; name="file"; filename="examen.pdf"
Content-Type: application/pdf

<file bytes>
--...--
```
Accepted `Content-Type`: `application/pdf`, `image/png`, `image/jpeg`,
`image/webp`. Max size: `MAX_UPLOAD_MB` (default 10MB) — `413` if exceeded,
`422` if the content type isn't one of the four above.

Claude reads the document, extracts any of the 12 biomarkers above it
recognizes, and **this endpoint writes them straight into
`health_context.biomarcadores` itself** — no separate `PATCH` call needed.
Unlike a normal `PATCH` (which replaces the whole array), this **merges by
`nombre`**: an extracted reading overwrites the existing entry with the same
name; every other previously-stored biomarker (including ones you entered by
hand) is left untouched.

```json
{
  "guardados": [
    {"nombre": "glucosa", "valor": 92.0, "unidad": "mg/dL", "fuente": "documento"}
  ],
  "biomarcadores": [
    {"nombre": "glucosa", "valor": 92.0, "unidad": "mg/dL", "fuente": "documento"},
    {"nombre": "imc", "valor": 31.2, "unidad": "kg/m2", "fuente": "calculado"}
  ],
  "advertencias": [
    {
      "nombre": "hs_CRP",
      "valor_reportado": 21.0,
      "unidad_reportada": "mg/L",
      "razon": "hs_CRP=21.0 fuera de rango plausible [0.01, 200.0] mg/L"
    }
  ],
  "notas": null
}
```
- `guardados` — extracted, validated, and just written this call.
- `biomarcadores` — the **full** list now in storage, after the merge (same
  shape as `GET /me/health-context`'s field of the same name).
- `advertencias` — readings Claude found on the document that failed the same
  unit/range validation `Biomarcador` always enforces (unrecognized unit with
  no known conversion, or implausible value even after conversion) — **not
  saved**. A document that's readable but has zero recognizable biomarkers
  is a normal `200` with empty `guardados`/`advertencias`, not an error.
- Units are converted deterministically in Python (a small fixed table: e.g.
  glucose/cholesterol in mmol/L, creatinine in umol/L, CRP in mg/dL) — Claude
  reports the value exactly as printed and never does the unit math itself.
- Uses `claude-haiku-4-5`, same cost-over-accuracy choice as `/chat`. Because
  this writes directly to storage with no review step, the validator above is
  the only thing standing between a misread value and a saved one — keep
  that in mind if biomarker names/ranges/units in the table above ever change.
- Same additional error cases as `/chat`: `502` (agent unreachable/errored),
  `429` (rate-limited), `503` (`ANTHROPIC_API_KEY` unset).

---

## Biological age compute (`/me/health-context/phenoage`, `/montecarlo`)

Both are pure computations over what `/me` + `/me/health-context` already
hold — neither takes a body describing the person. Both `422` with a clear
message if `date_of_birth` or `sex_at_birth` is missing from the profile.

### `POST /me/health-context/phenoage` → `200`
No request body. Implements Levine et al. 2018's PhenoAge biological-age
clock from the 9 biomarkers above (whatever's on file; the rest imputed from
NHANES-style age/sex medians).
```json
{
  "edad_cronologica": 52,
  "edad_biologica": 45.9,
  "aceleracion": -6.1,
  "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
  "valores_usados": {
    "hs_CRP": 2.1, "glucosa": 92.0, "albumina": 4.4, "creatinina": 0.8,
    "fosfatasa_alcalina": 72.0, "linfocitos_pct": 30.0, "vcm": 91.0,
    "rdw": 13.3, "leucocitos": 6.7
  }
}
```
- `aceleracion` = `edad_biologica - edad_cronologica`. Negative = biologically
  younger than the calendar; positive = older.
- `campos_inferidos` names which of `valores_usados` were imputed rather than
  measured — always show this distinction in any UI that surfaces the result.

### `POST /me/health-context/montecarlo` → `200`
```json
// request — every field optional
{
  "escenarios": ["ninguna", "ejercicio_aerobico"],  // omit for all 5
  "n_trayectorias": 5000,     // 100–20000, default 5000
  "anios": 10,                // 1–30, default 10
  "adherencia": 1.0,          // 0.0–1.0, default 1.0 — see below
  "percentil_inferior": 10,   // 1–49, default 10
  "percentil_superior": 90,   // 51–99, default 90
  "seed": null,                // omit for fresh randomness each call — see below
  "incluir_trayectoria": false // default false — see below
}
```
Runs `n_trayectorias` independent 1-year-step simulations per scenario over
`anios` years, evolving each biomarker with a natural-aging drift + the
scenario's effect (scaled by `adherencia`) + biological noise, then scores
PhenoAge for every trajectory. `422` if an `escenarios` key isn't one of:

| key | label |
|---|---|
| `ninguna` | Sin intervención (línea base) |
| `ejercicio_aerobico` | Ejercicio aeróbico regular |
| `dieta_mediterranea` | Dieta mediterránea |
| `cesacion_tabaco` | Cesación de tabaco |
| `combinada` | Ejercicio + dieta mediterránea + cesación de tabaco |

- **`adherencia`** scales only the scenario's own intervention effect, never
  the natural-aging drift everyone gets regardless — `0.0` collapses any
  scenario to the same result as `ninguna` (no intervention benefit, still
  ages normally); `1.0` (default) is "the intervention applies in full every
  year," same behavior as before this parameter existed. Use it to model
  partial follow-through instead of assuming perfect adherence.
- **`percentil_inferior`/`percentil_superior`** control the band width
  around the median — default 10/90 is unchanged from before. The response
  field names stay `edad_biologica_p10`/`edad_biologica_p90` regardless of
  what you requested (backward compatible); the response's own
  `percentil_inferior`/`percentil_superior` say what they actually are.
- **`seed`** — omit for fresh randomness each call. The seed actually used
  (generated server-side if you didn't pass one) always comes back in the
  response's `seed` field, so you can replay the *exact* same run later by
  passing that value back — useful for a before/after comparison where only
  one parameter (e.g. `adherencia`) should differ.
- **`incluir_trayectoria`** — off by default, so the response stays the same
  shape it always was unless you opt in. When `true`, each scenario also
  returns `trayectoria`: one entry per simulated year (not just the final
  horizon), each with its own `p_inferior`/`mediana`/`p_superior` — the
  actual band-widening-over-time "fan of futures," not just its endpoint.

```json
{
  "edad_cronologica": 52,
  "horizonte_anios": 10,
  "trayectorias_por_escenario": 5000,
  "adherencia": 1.0,
  "percentil_inferior": 10,
  "percentil_superior": 90,
  "seed": 7823914502,
  "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
  "escenarios": [
    {
      "escenario": "ninguna",
      "nombre": "Sin intervención (línea base)",
      "edad_biologica_p10": 51.76,
      "edad_biologica_mediana": 57.65,
      "edad_biologica_p90": 63.44,
      "trayectoria": null
    }
  ]
}
```
When `incluir_trayectoria: true`, each scenario's `trayectoria` looks like:
```json
[
  {"anio": 1, "edad_biologica_p_inferior": 46.01, "edad_biologica_mediana": 47.83, "edad_biologica_p_superior": 49.6},
  {"anio": 2, "...": "..."},
  {"anio": 10, "edad_biologica_p_inferior": 52.31, "edad_biologica_mediana": 58.27, "edad_biologica_p_superior": 64.05}
]
```
`p10`/`mediana`/`p90` (or `trayectoria[].edad_biologica_p_inferior`/
`p_superior`, if requested) are percentiles of simulated biological age
across all trajectories for that scenario/year — not a confidence interval,
the actual spread the noise model produces. Compare scenarios by their
medians; the band is what a UI should render as the "fan of futures."

> Both intervention effect sizes and the NHANES imputation medians are
> directional placeholders (see `app/health_metrics/interventions.py` and
> `nhanes_reference.py`), not literature-fitted — fine for a demo, not a
> stated clinical claim.

---

## Chat agent (`/me/health-context/chat`)

### `POST /me/health-context/chat` → `200`
An LLM (`claude-haiku-4-5`) grounded in exactly the caller's own stored
`/me` + `/me/health-context` data (including a freshly computed PhenoAge, if
enough is on file) — no other data source, no tools. Stateless: send the
conversation back each turn.
```json
// request
{
  "message": "¿qué significa que mi PhenoAge sea distinto a mi edad cronológica?",
  "history": []   // optional; pass back what the previous response returned here
}
```
- `message`: 1–4000 chars. `history`: max 40 entries, each `{"role": "user"|"assistant", "content": "..."}`.
```json
// response
{
  "reply": "...",
  "history": [
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ]
}
```
Pass the returned `history` straight back as the request's `history` on the
next call to continue the same conversation.

**Errors specific to this endpoint** (still the `{"detail": "..."}` shape):
- `503` — `ANTHROPIC_API_KEY` isn't set on this deployment, or the agent is unreachable.
- `502` — the agent responded with an error.
- `429` — rate-limited; retry shortly.

If the profile's `date_of_birth`/`sex_at_birth` aren't set yet, this endpoint
does **not** 422 like `/phenoage` does — it still answers, just without a
PhenoAge figure to reference (it'll say so).

---

## Known gaps — don't build a frontend flow assuming these exist

The onboarding flow collects more than this API currently stores. These are
real, scoped-out gaps, not oversights — each needs its own design pass
(most involve storage/infra this repo doesn't have yet), not a quick field
addition like the ones above:

- **Photo and genetic-test-PDF upload** — no endpoint, and no object storage
  exists anywhere in this backend to put an uploaded file into. A client
  holding only a local file path today has nowhere to send it yet.
- **Wearable raw health data** — `wearable` (above) is connection status
  only. There's no `/wearables/sync`-type endpoint, and ingesting an actual
  raw data feed (HealthKit-style records) is a different shape of problem
  (likely its own time-series table) than the JSONB blobs this resource uses.
- **Simulation history and plan/adherence tracking** — `/montecarlo` (below)
  computes and returns a result but saves nothing; there's no persisted
  concept of "a plan" or "adherence to it" anywhere in this API yet.
- **Persisted chat history** — `/chat` (above) is deliberately stateless;
  conversations aren't stored server-side at all.

If a screen depends on any of these, that's a signal to come back and design
the specific endpoint/table needed — not to assume one of the fields above
already covers it.

---

## Maintenance

When you touch a router, before you consider the change done:
1. Update the matching section above — new endpoint, changed field, new
   status code, new validation rule.
2. If you added a brand-new resource, add its section following the same
   format (path, auth requirement, request shape, response shape, error
   cases, a short note on anything non-obvious like merge-vs-replace).
3. If a scenario/biomarker/enum table above changed, update the table, not
   just the prose around it — a frontend agent reading this will trust the
   table over any surrounding sentence.
