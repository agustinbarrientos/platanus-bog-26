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
    "escolaridad_anios": 12
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
    "tabaco": false,
    "actividad": "baja",
    "alimentacion": "media",
    "estres": "alto"
  },
  "historia_familiar": ["diabetes_t2", "alzheimer_materno"],
  "objetivos_usuario": ["energia", "prevencion"],
  "datos_faltantes": ["creatinina", "fosfatasa_alcalina", "APOE"],
  "notas_incertidumbre": "texto libre",
  "onboarding_completo": true
}
```

**Merge semantics differ by field shape** — this is the one non-obvious part
of this endpoint:
- `demografia` and `habitos` (objects) **merge**: a `PATCH` with only
  `{"habitos": {"estres": "medio"}}` updates just `estres` and leaves
  `sueno_h`, `tabaco`, etc. as they were. Send a sub-field as `null` to clear
  just that one.
- `biomarcadores`, `historia_familiar`, `objetivos_usuario`, `datos_faltantes`
  (arrays) **replace wholesale** when sent — there's no single sensible
  "merge" for a list, so resend the full array each time you update it.
- `notas_incertidumbre` (string) replaces when sent.
- `onboarding_completo` (bool, default `false`) replaces when sent — **not**
  derived from how much of the rest of this resource is filled in. The app
  sets it explicitly when its own onboarding flow finishes (which includes
  steps this schema never sees: photo, genetic test, wearable provider). A
  new device/reinstall should `GET` this on login/session-restore and skip
  local onboarding if it's already `true`.

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
above. Upload one or more lab-exam documents as `multipart/form-data`,
**repeating the field name `files`** once per file (pages of the same exam,
or a few separate exams/reports from the same visit):
```
Content-Type: multipart/form-data; boundary=...

--...
Content-Disposition: form-data; name="files"; filename="examen1.pdf"
Content-Type: application/pdf

<file bytes>
--...
Content-Disposition: form-data; name="files"; filename="examen2.jpg"
Content-Type: image/jpeg

<file bytes>
--...--
```
Accepted `Content-Type` per file: `application/pdf`, `image/png`,
`image/jpeg`, `image/webp`. `422` if any file's type isn't one of those four,
if no files are sent, or if more than 5 are sent in one request. Size limits,
checked before anything is sent to Claude: `413` if any single file exceeds
`MAX_UPLOAD_MB` (default 10MB), or if the **combined** size of all files
exceeds 20MB.

All files go to Claude in a single request (multiple documents, one call),
so it can reconcile a biomarker that shows up on more than one of them
instead of reading each file blind to the others — told to prefer the most
recently dated document on a conflict and note it in `notas`. Whatever it
extracts (across however many files you sent) **writes straight into
`health_context.biomarcadores` itself** — no separate `PATCH` call needed.
Unlike a normal `PATCH` (which replaces the whole array), this **merges by
`nombre`**: an extracted reading overwrites the existing entry with the same
name; every other previously-stored biomarker (including ones you entered by
hand, or from an earlier upload) is left untouched.

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
  "hallazgos": ["Médico recomienda control de presión arterial en 3 meses"],
  "notas_incertidumbre": "Médico recomienda control de presión arterial en 3 meses",
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
- `hallazgos` — clinically relevant things the document(s) say that aren't
  one of the 12 biomarkers (a diagnosis, a doctor's recommendation, a
  mentioned allergy or family history) — short and factual, Claude quoting
  rather than interpreting. Automatically **appended** to
  `health_context.notas_incertidumbre` (never overwritten — an earlier
  upload's or a manual `PATCH`'s notes survive). `notas_incertidumbre` in
  this response is the full accumulated value after that append, same field
  `GET /me/health-context` returns.
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
  "escenarios": ["ninguna", "ejercicio_aerobico"],  // omit for all 7
  "n_trayectorias": 5000,   // 100–20000, default 5000
  "anios": 10               // 1–30, default 10
}
```
Runs `n_trayectorias` independent 1-year-step simulations per scenario over
`anios` years, evolving each biomarker with a natural-aging drift + the
scenario's effect + biological noise, then computes PhenoAge at the horizon
for every trajectory. Omitting `escenarios` runs **all 7**, returned in the
order listed below (the declaration order of `SCENARIOS` in
`app/health_metrics/interventions.py`) — a caller that omits the field gets
`ninguna` first, so the baseline is always `escenarios[0]`. `422` if an
`escenarios` key isn't one of:

| key | label |
|---|---|
| `ninguna` | Sin intervención (línea base) |
| `ejercicio_aerobico` | Ejercicio aeróbico regular |
| `dieta_mediterranea` | Dieta mediterránea |
| `cesacion_tabaco` | Cesación de tabaco |
| `sueno_8h` | Dormir 8 horas |
| `reducir_estres` | Reducir el estrés |
| `combinada` | Ejercicio + dieta mediterránea + cesación de tabaco |

`sueno_8h` and `reducir_estres` are the two levers of `MOIRAI_ENGINE_SPEC.md`
§5 that the engine was missing; their effect sizes are deliberately smaller
than exercise or diet because the trial evidence behind them is weaker. They
were added without renaming or removing any existing key, so a caller that
passes an explicit `escenarios` list keeps behaving exactly as before.

```json
{
  "edad_cronologica": 52,
  "horizonte_anios": 10,
  "trayectorias_por_escenario": 5000,
  "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
  "escenarios": [
    {
      "escenario": "ninguna",
      "nombre": "Sin intervención (línea base)",
      "edad_biologica_p10": 51.76,
      "edad_biologica_mediana": 57.65,
      "edad_biologica_p90": 63.44,
      "curva": {
        "anios":    [0,     1,     "...", 10],
        "p10":      [52.30, 51.62, "...", 51.76],
        "mediana":  [52.30, 53.44, "...", 57.65],
        "p90":      [52.30, 55.28, "...", 63.44]
      }
    }
  ]
}
```
`edad_biologica_p10`/`mediana`/`p90` are percentiles of simulated biological
age across all trajectories for that scenario **at the horizon** — not a
confidence interval, the actual spread the noise model produces. Compare
scenarios by their medians.

`curva` is the same three percentiles **year by year**, `anios[i]` counted from
today (`0` = today). Its last point is exactly the flat `edad_biologica_*`
above it, and its first point is the same for every scenario (no drift or noise
has been applied yet, so the band has zero width at year 0 and the median
equals what `/phenoage` returns). This is the fan a UI renders — the app no
longer needs to interpolate one locally.

Two properties the engine guarantees, both covered in `tests/test_montecarlo.py`:

- **The p10–p90 band widens every year.** More distance, less certainty. A band
  that narrowed with time would be the model claiming it knows the far future
  better than the near one.
- **Imputed biomarkers widen the band.** A biomarker that came from the
  reference-median table instead of a lab gets its annual noise multiplied by
  `SIGMA_IMPUTADO_FACTOR` (2.0), so a profile with 3 of 9 values inferred
  projects a visibly wider fan than a fully measured one. Measuring one more
  biomarker narrows it. Note this widens the band **symmetrically** — it does
  not shift the median, so a user who uploaded no labs gets a less certain
  answer, not a worse prognosis.

> Intervention effect sizes are **approximate and derived from epidemiological
> literature** — each one is annotated in `app/health_metrics/interventions.py`
> with the trial or meta-analysis its order of magnitude comes from, and
> `tests/test_evolution.py` checks that the 10-year cumulative effect stays
> inside the published range. Approximate and citable, not exact, and not
> fitted to any cohort of ours. The per-year aging drift is anchored to the
> age gradient of this engine's own reference-median table, and those medians
> (`nhanes_reference.py`) are still hand-set NHANES-shaped values, not NHANES
> microdata. Estimate, not a clinical claim.

---

## Chat agent (`/me/health-context/chat`)

### `POST /me/health-context/chat` → `200`
Moirai (the app's mascot, first person singular) answering about the
caller's own stored data, a freshly computed PhenoAge **and the simulation
result the app sends** — grounded by retrieval, not by pasting everything into
the prompt. The model (`CHAT_MODEL`, default `claude-haiku-4-5`) only sees the
handful of fragments that match the question plus an always-on card with the
headline numbers, and may call one tool (`buscar_mis_datos`) to fetch more
when the first pass missed something (max 2 rounds). Stateless: send the
conversation back each turn.
```json
// request
{
  "message": "¿Por qué el ejercicio es mi primera palanca?",
  "history": [],              // optional; pass back what the previous response returned here
  "enfoque": "escenario:0",   // optional; where in the app the chat was opened from
  "resultado": { "...": "SimulacionResultado.toChatJson() — spec §8 shape, see below" }
}
```
- `message`: 1–4000 chars. `history`: max 40 entries, each
  `{"role": "user"|"assistant", "content": "..."}` (`extra="forbid"`).
- `enfoque` (optional, ≤ 80 chars): biases retrieval and pins the matching
  fragment first. Values the app uses: `escenario:<índice>` (a lever; index
  into `resultado.escenarios`), `porque`, `incertidumbre`, `biomarcador:<nombre>`,
  `medir`, `poblacion`. Anything else is matched as a substring of fragment ids.
- `resultado` (optional): the spec §8 JSON as the app holds it — `id`,
  `creado_en`, `edad_cronologica`, `edad_biologica_hoy`,
  `trayectoria_baseline {anios, mediana, p10, p90}`, `mejor_decision`,
  `veredicto_gemelo`, `porque`, `shap_top_drivers[]`, `comparacion_poblacional`,
  `incertidumbre`, `descargo`, `escenarios[] {intervenciones, etiqueta,
  anios_ganados, rango, esfuerzo, ratio_impacto_esfuerzo,
  pct_futuros_que_mejoran, curva}`, `intervenciones_catalogo[]`,
  `biomarcadores_usados[]`. **The one body in this API with `extra="ignore"`:**
  unknown keys are dropped, not 422 — the app assembles part of this locally
  (see API_CONTRACT.md) and its shape moves faster than the API. Do **not**
  send `muestra_trayectorias`: it is most of the payload and is never read.
  Without `resultado` the chat still answers about stored data, PhenoAge and
  how the engine works, and says there is no simulation to talk about.
```json
// response
{
  "reply": "...",
  "history": [
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "fuentes": [
    {"id": "sim:mejor_decision", "titulo": "Tu mejor palanca", "grupo": "resultado"},
    {"id": "kb:intervencion:ejercicio_aerobico", "titulo": "Palanca: Ejercicio aeróbico regular", "grupo": "conocimiento"}
  ]
}
```
- `history`: pass it straight back as the request's `history` on the next
  call. Plain text only — tool calls never leak into it.
- `fuentes`: the fragments the answer was grounded in, in the order shown to
  the model (initial retrieval, then anything fetched with the tool). `grupo`
  is `usuario` (stored data — ids `perfil`, `habitos`, `historia_familiar`,
  `objetivos`, `phenoage`, `faltantes`, `bio:<nombre>` for each of the 12
  biomarkers, measured or not), `resultado` (`sim:resumen`,
  `sim:mejor_decision`, `sim:escenario:<i>`, `sim:baseline`, `sim:porque`,
  `sim:poblacion`, `sim:incertidumbre`, `sim:catalogo`) or `conocimiento`
  (`kb:*` — PhenoAge, the three layers, the P10–P90 band, imputation, what to
  measure, effort/ratio, adherence, each biomarker, each intervention, limits,
  where things are in the app). The app renders them as "Leí: …" under the
  bubble. Empty only when nothing matched and nothing was fetched.

**How retrieval works** (`app/chat_rag/`, no embeddings, no extra service):
the user's data, the `resultado` and a static knowledge base built from the
engine's own tables become ~60 short chunks; BM25 over accent-stripped
Spanish stems plus a synonym map (`azúcar`→glucosa, `fumar`→tabaco,
`rango`→incertidumbre…) scores them, the previous user turn counts at lower
weight (so "¿y por qué?" keeps its topic), `enfoque` pins its fragment first,
a diversity penalty keeps one family from crowding out the rest, and a
~1.600-token budget caps the prompt. Greetings with no keywords fall back to
the overview fragments. Net effect: ~2.500 input tokens per turn instead of
the ~8–10k a full dump of data + result + knowledge would cost.

**Errors specific to this endpoint** (still the `{"detail": "..."}` shape):
- `503` — `ANTHROPIC_API_KEY` isn't set on this deployment, or the agent is unreachable.
- `502` — the agent responded with an error.
- `429` — rate-limited; retry shortly.

If the profile's `date_of_birth`/`sex_at_birth` aren't set yet, this endpoint
does **not** 422 like `/phenoage` does — it still answers, just without a
PhenoAge figure to reference (it'll say so).

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
