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
- Every endpoint except `/health`, `/auth/signup`, `/auth/login` and `/engine/catalogo`
  (static engine constants, nothing personal) requires:
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
    "perfil_conocimiento": "general"
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
    "estres": "alto",
    "alcohol": "ocasional"
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

**`demografia.perfil_conocimiento`** (`general` | `curioso` | `profesional`,
closed vocabulary → `422` otherwise) is how much the person already knows
about health/science, asked in onboarding ("¿Qué tanto sabes de salud?"). The
engine ignores it; the chat (`/chat`, below) uses it to pick its register —
plain everyday words for `general` (also the default when unset), concepts
named for `curioso`, clinical/statistical vocabulary allowed for
`profesional`. At every level the chat stays warm and simple and only goes
deep-technical when the person explicitly asks.

**`habitos`** is what the engine reads to build the person's own baseline
and to decide which levers apply (see `/montecarlo`): `sueno_h` (hours),
`tabaco` (bool), `actividad` and `alimentacion` in `baja|media|alta`, `estres`
in `bajo|medio|alto`, `alcohol` in `nunca|ocasional|moderado|alto`. Values are
free text at the API level (the app fixes the vocabulary); anything outside
those sets is treated by the engine as "not recorded".

**`biomarcadores[].nombre`** is a fixed vocabulary, not free text — an
unlisted name is a `422`, as is the wrong `unidad` for a name or a `valor`
outside its plausible range:

| `nombre` | `unidad` | plausible range | used by PhenoAge? |
|---|---|---|---|
| `hs_CRP` | `mg/L` | 0.1–200 | yes |
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
above. Upload a single lab-exam document as `multipart/form-data`, field
name `file`:
```
Content-Type: multipart/form-data; boundary=...

--...
Content-Disposition: form-data; name="file"; filename="examen.pdf"
Content-Type: application/pdf

<file bytes>
--...--
```
Accepted `Content-Type`: `application/pdf`, `image/png`, `image/jpeg`,
`image/webp`. `422` if the type isn't one of those four (or if no file is
sent). `413` if it exceeds `MAX_UPLOAD_MB` (default 10MB).

Whatever Claude extracts from the document **writes straight into
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
- `hallazgos` — clinically relevant things the document says that aren't
  one of the 12 biomarkers (a diagnosis, a doctor's recommendation, a
  mentioned allergy or family history) — short and factual, Claude quoting
  rather than interpreting. Automatically **appended** to
  `health_context.notas_incertidumbre` (never overwritten, and never
  duplicated if the same finding shows up again on a later upload — an
  earlier upload's or a manual `PATCH`'s notes survive). `notas_incertidumbre`
  in this response is the full accumulated value after that append, same
  field `GET /me/health-context` returns.
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
the age/sex reference medians), plus the two things the app used to
approximate on the device: the *por qué* and the population percentile.
```json
{
  "edad_cronologica": 52,
  "edad_biologica": 45.9,
  "aceleracion": -6.1,
  "aceleracion_referencia": 0.4,
  "percentil_poblacional": 10.2,
  "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
  "valores_usados": {
    "hs_CRP": 2.1, "glucosa": 92.0, "albumina": 4.4, "creatinina": 0.945,
    "fosfatasa_alcalina": 82.0, "linfocitos_pct": 29.2, "vcm": 91.2,
    "rdw": 13.7, "leucocitos": 7.1
  },
  "contribuciones": {
    "hs_CRP": -0.2, "glucosa": -0.7, "albumina": -1.1, "creatinina": 0.0,
    "fosfatasa_alcalina": 0.0, "linfocitos_pct": 0.0, "vcm": 0.0, "rdw": 0.0, "leucocitos": 0.0
  }
}
```
- `aceleracion` = `edad_biologica - edad_cronologica`. Negative = biologically
  younger than the calendar; positive = older.
- `aceleracion_referencia` = the acceleration of the *reference person* of
  that age and sex (all 9 biomarkers at their median). The reference table is
  calibrated so this is ≈ 0 (±2 years; women ~1 year below men, as in
  NHANES). It is the zero of the percentile.
- `percentil_poblacional` (1–99): `aceleracion` against the reference person
  and the population spread of PhenoAge (~5 years, propagated from the
  per-biomarker dispersion). 50 = like the reference; lower = younger than
  average; higher = older. A user with nothing measured lands at 50.
- `contribuciones`: years each **measured** biomarker adds (+, ages) or
  removes (−, rejuvenates) versus the reference median — the spec §7 "SHAP
  sobre el basal". Imputed ones are exactly `0.0` (they *are* the median).
  They sum to `aceleracion - aceleracion_referencia`. Show the sign, never
  "normal/abnormal".
- `campos_inferidos` names which of `valores_usados` were imputed rather than
  measured — always show this distinction in any UI that surfaces the result.

### `POST /me/health-context/montecarlo` → `200`
```json
// request — every field optional
{
  "escenarios": ["ejercicio_aerobico", "ejercicio_aerobico+sueno_8h"],  // omit → what applies to this person (+ combos)
  "n_trayectorias": 5000,   // 100–20000, default 5000
  "anios": 10,              // 1–30, default 10
  "semilla": 20260822,      // optional; omitted → fixed default (reproducible)
  "combinaciones": true     // only when `escenarios` is omitted: also pairs and triples
}
```
Runs `n_trayectorias` paired 1-year-step simulations per scenario over
`anios` years. Each trajectory evolves the 9 biomarkers with a natural-aging
drift, **the person's own habits** (stored `habitos`), the scenario's effect
(scaled by how much of that habit the person still has to gain), an
individual response multiplier and biological noise, evaluating PhenoAge at
**every year**. Biomarkers that are not measured start **sampled** from the
population spread of their age/sex group (so an imputed value widens the band
from day 0, and measuring it narrows it). All scenarios share the same sampled
starts, the same noise and the same response draws (same `semilla`), so every
trajectory is the *same life* with and without the lever: "años ganados" is
the distribution of that paired difference.

**Scenario keys.** One lever, several levers joined with `+` (max 3, spec
§12), the legacy composite `combinada` (= `ejercicio_aerobico+dieta_mediterranea+cesacion_tabaco`)
or `ninguna`. Unknown/repeated levers or more than 3 → `422`. `ninguna` is
always returned first (the baseline), whether or not you asked for it.

| lever key | label | closes habit | effort (1–10) |
|---|---|---|---|
| `ejercicio_aerobico` | Ejercicio aeróbico regular | `actividad` (baja→1, media→0.5, alta→0) | 3 |
| `dieta_mediterranea` | Dieta mediterránea | `alimentacion` (baja→1, media→0.5, alta→0) | 3 |
| `cesacion_tabaco` | Cesación de tabaco | `tabaco` (true→1, false→0) | 4 |
| `sueno_8h` | Dormir 8 horas | `sueno` (from `sueno_h`: ≤6 h→1, ≥7.5 h→0, linear) | 2 |
| `reducir_estres` | Reducir el estrés | `estres` (alto→1, medio→0.5, bajo→0) | 2 |
| `reducir_alcohol` | Bajar el alcohol | `alcohol` (alto→1, moderado→0.5, ocasional/nunca→0) | 2 |

A lever **applies** to a person when its habit gap is > 0; with gap 0 (they
already have the habit) its effect is 0, `aplica=false` and it collapses onto
the baseline. A habit that is **not recorded** does not adjust the baseline;
for the effect, `ejercicio_aerobico`, `dieta_mediterranea`, `sueno_8h` and
`reducir_estres` are assumed with full gap (offered as before), while
`cesacion_tabaco` and `reducir_alcohol` are not assumed (gap 0). Omitting
`escenarios` returns `ninguna` + every applicable lever + (with
`combinaciones`) all their pairs and triples — the spec §6 sweep. The effort
of a combination is the sum of its parts.

```json
{
  "edad_cronologica": 52,
  "horizonte_anios": 10,
  "trayectorias_por_escenario": 5000,
  "semilla": 20260822,
  "campos_inferidos": ["linfocitos_pct", "vcm", "fosfatasa_alcalina"],
  "ancho_banda_hoy": 4.7,
  "habitos_usados": {"sueno_h": 6, "tabaco": false, "actividad": "baja", "alimentacion": "media", "estres": "alto"},
  "brechas": {"actividad": 1.0, "alimentacion": 0.5, "tabaco": 0.0, "sueno": 1.0, "estres": 1.0, "alcohol": null},
  "palancas": [
    {"id": "ejercicio_aerobico", "nombre": "Ejercicio aeróbico regular", "descripcion": "150 minutos a la semana…",
     "esfuerzo": 3, "habito": "actividad", "brecha": 1.0, "brecha_efectiva": 1.0, "aplica": true,
     "efectos_anuales": {"hs_CRP": -0.08, "glucosa": -0.9, "leucocitos": -0.03}},
    {"id": "cesacion_tabaco", "nombre": "Cesación de tabaco", "descripcion": "Cero cigarrillos…",
     "esfuerzo": 4, "habito": "tabaco", "brecha": 0.0, "brecha_efectiva": 0.0, "aplica": false,
     "efectos_anuales": {"leucocitos": -0.11, "hs_CRP": -0.1, "vcm": -0.15}}
  ],
  "escenarios": [
    {
      "escenario": "ninguna", "nombre": "Sin intervención (línea base)", "intervenciones": [],
      "descripcion": "", "esfuerzo": 0, "aplica": true,
      "edad_biologica_p10": 51.76, "edad_biologica_mediana": 57.65, "edad_biologica_p90": 63.44,
      "curva": {"anios": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                "p10": [45.4, 46.1, 47.0, 47.6, 48.4, 49.1, 49.7, 50.3, 50.8, 51.3, 51.76],
                "mediana": [47.6, 48.6, 49.6, 50.6, 51.6, 52.6, 53.6, 54.6, 55.6, 56.6, 57.65],
                "p90": [49.9, 51.2, 52.4, 53.7, 54.9, 56.1, 57.3, 58.5, 60.1, 61.8, 63.44]},
      "anios_ganados": 0, "anios_ganados_p10": 0, "anios_ganados_p90": 0,
      "pct_futuros_que_mejoran": 0, "ratio_impacto_esfuerzo": 0
    },
    {
      "escenario": "ejercicio_aerobico+sueno_8h", "nombre": "Ejercicio aeróbico regular + dormir 8 horas",
      "intervenciones": ["ejercicio_aerobico", "sueno_8h"], "descripcion": "150 minutos… · Acostarte…",
      "esfuerzo": 5, "aplica": true,
      "edad_biologica_p10": 50.1, "edad_biologica_mediana": 55.8, "edad_biologica_p90": 61.6,
      "curva": {"anios": [0, 1, 10], "p10": [45.4, 45.9, 50.1], "mediana": [47.6, 48.4, 55.8], "p90": [49.9, 51.0, 61.6]},
      "anios_ganados": 1.85, "anios_ganados_p10": 0.89, "anios_ganados_p90": 3.04,
      "pct_futuros_que_mejoran": 99.9, "ratio_impacto_esfuerzo": 0.37
    }
  ],
  "muestra_trayectorias": [[47.6, 48.3, 49.1, 50.5, 51.0, 52.4, 53.1, 54.6, 55.0, 56.7, 57.2], "…(40 rows of 11)"],
  "valor_de_informacion": [
    {"nombre": "vcm", "reduccion_banda_anios": 0.74, "fraccion": 0.8},
    {"nombre": "linfocitos_pct", "reduccion_banda_anios": 0.16, "fraccion": 0.17},
    {"nombre": "fosfatasa_alcalina", "reduccion_banda_anios": 0.03, "fraccion": 0.03}
  ],
  "contribuciones_habitos": [
    {"habito": "actividad", "palanca": "ejercicio_aerobico", "brecha": 1.0, "contribucion": 1.1, "direccion": "empeora"},
    {"habito": "tabaco", "palanca": "cesacion_tabaco", "brecha": 0.0, "contribucion": -1.5, "direccion": "mejora"}
  ]
}
```
- `escenarios[0]` is always `ninguna`. Per scenario: `curva` is the P10 /
  mediana / P90 of the simulated biological age **per year** (year 0 = today;
  with imputed biomarkers it already has width — `ancho_banda_hoy`);
  `edad_biologica_*` are the same numbers at the horizon (the previous shape
  of this endpoint, kept). `anios_ganados` (+ `_p10`/`_p90`) is the **paired**
  difference baseline − scenario, trajectory by trajectory, and
  `pct_futuros_que_mejoran` the share of trajectories where the lever ends
  younger (typically 95–100 %: the ~2 % non-responders of the response
  multiplier, plus noise). `ratio_impacto_esfuerzo` = `anios_ganados /
  esfuerzo`; the app ranks by it. `aplica=false` scenarios are returned (if
  asked) but gain nothing.
- `palancas`: the full lever catalog evaluated for this person (`brecha`,
  `aplica`, effects) — use it as the app's catalog/descriptions instead of a
  local table.
- `muestra_trayectorias`: up to 40 real baseline trajectories (year by year)
  to draw while simulating / behind the fan.
- `valor_de_informacion`: for each imputed biomarker, how many years the
  baseline P10–P90 band at the horizon would shrink if it were measured
  (same seed, that biomarker fixed at its median), largest first; `fraccion`
  sums to 1. Empty when all 9 are measured. Feeds "¿Qué te conviene medir?".
- `contribuciones_habitos`: deterministic, at the horizon — years this
  recorded habit costs (`empeora`, gap > 0) or saves (`mejora`, gap 0) versus
  having it the other way. Pairs with `/phenoage`'s `contribuciones` (today,
  biomarkers) for the "por qué".
- Backwards compatible: every field the previous version returned is still
  there with the same meaning; a client that only reads
  `escenarios[].edad_biologica_*` keeps working (it just gets habit-aware,
  paired numbers).

> Intervention effect sizes are **approximate and derived from epidemiological
> literature** — each one is annotated in `app/health_metrics/interventions.py`
> with the trial or meta-analysis its order of magnitude comes from, and
> `tests/test_evolution.py` checks that the 10-year cumulative effect stays
> inside the published range. hs-CRP effects are proportional to the current
> value (calibrated at 2.5 mg/L); the rest are absolute. The per-year aging
> drift is anchored to the age gradient of the engine's reference-median
> table, which is hand-set NHANES-shaped data calibrated so the median person
> of each age/sex reads ≈ their own age (`nhanes_reference.py`), not NHANES
> microdata. The mixture decomposition that places each habit's baseline uses
> declared prevalence assumptions (it moves where the baseline sits, not the
> years gained). Combining levers discounts 8 % per extra lever on the same
> biomarker; individual response is N(1, 0.5) truncated at 0. Estimate, not a
> clinical claim.

### `GET /engine/catalogo` → `200`
**No auth.** The engine's static constants — what every number is made of —
so the app's "Respaldo" screen and any client can render them without a copy
that drifts:
```json
{
  "version": "0.3.0",
  "biomarcadores": [
    {"nombre": "hs_CRP", "unidad": "mg/L", "valor_min": 0.1, "valor_max": 200.0,
     "descripcion": "Proteína C reactiva de alta sensibilidad", "phenoage": true,
     "deriva_anual": 0.012, "ruido_anual_sd": 0.6, "dispersion": {"tipo": "lognormal", "sigma": 1.0}},
    {"nombre": "imc", "unidad": "kg/m2", "valor_min": 10.0, "valor_max": 80.0,
     "descripcion": "Índice de masa corporal", "phenoage": false,
     "deriva_anual": null, "ruido_anual_sd": null, "dispersion": null}
  ],
  "palancas": [
    {"id": "ejercicio_aerobico", "nombre": "Ejercicio aeróbico regular", "descripcion": "150 minutos…",
     "esfuerzo": 3, "habito": "actividad", "brecha_promedio": 0.5, "brecha_si_desconocido": 1.0,
     "efectos_anuales": {"hs_CRP": -0.08, "glucosa": -0.9, "leucocitos": -0.03}}
  ],
  "habitos": ["actividad", "alimentacion", "tabaco", "sueno", "estres", "alcohol"],
  "combinacion": {"descuento_por_palanca_adicional": 0.08, "max_intervenciones": 3, "heterogeneidad_respuesta_sd": 0.5},
  "defaults": {"n_trayectorias": 5000, "anios": 10, "semilla": 20260822, "muestra_trayectorias": 40}
}
```

---

## Health report (`/me/health-context/reporte`, `/reporte.pdf`)

The downloadable, clinical-tone, **orientative** health report of
`docs/MOIRAI_REPORTE_SPEC.md` — the deliverable the person takes *to* their
doctor. Same contract as `/phenoage` + `/montecarlo`: a pure function of what
`/me` + `/me/health-context` already hold (name, age, sex, stored
`biomarcadores` with their `fuente`, `habitos`, `demografia.ancestria_reportada`).
Every number is recomputed from the real engine on each call (PhenoAge +
paired Monte Carlo with the engine's default seed, so it matches what the app
showed); nothing is stored, nothing is generated by a language model — the
prose is fixed templates filled with engine numbers. `422` (string `detail`)
if `date_of_birth`/`sex_at_birth` are missing from the profile.

Guard-rails baked into the templates (and pinned by `tests/test_report.py`):
no disease is ever named as a diagnosis, nothing is prescribed (no drugs,
supplements or doses), no outcome is promised, no "88 % accuracy" claims; a
disclaimer sits on the cover, in every page footer and in the triage
section. Out-of-range values are worded exactly as "fuera del rango de
referencia", never as a condition.

### `POST /me/health-context/reporte` → `200`
Optional body (all defaults = what the app used for the simulation):
```json
{"n_trayectorias": 5000, "anios": 10, "semilla": null, "resumen": false}
```
Response (`ReporteOut`; abridged — every section is what the PDF prints):
```json
{
  "meta": {"id": "rep_7f3a9c21", "generado_en": "2026-08-22T20:11:03+00:00", "version_motor": "0.3.0",
           "semilla": 20260822, "trayectorias_por_escenario": 5000, "horizonte_anios": 10,
           "disclaimer": "Documento orientativo, no diagnóstico. …", "privacidad": "Datos procesados de forma privada; …",
           "fuentes": ["Levine ME, et al. … Aging 2018 (PhenoAge).", "NHANES (CDC): …", "…"]},
  "persona": {"nombre": "Ana Rueda", "edad": 34, "sexo": "F", "ancestria": "mixta_latam"},
  "resumen": "Tu edad biológica estimada es 28,9 años (tienes 34); lo que más la mueve a 10 años es ejercicio aeróbico regular: +1,6 años, entre +0,6 y +2,7.",
  "foto_hoy": {
    "edad_cronologica": 34, "edad_biologica": 28.9, "rango_hoy": {"p10": 26.6, "mediana": 28.9, "p90": 31.3},
    "aceleracion": -5.1, "percentil_poblacional": 20.6, "n_medidos": 6, "n_inferidos": 3,
    "biomarcadores": [
      {"nombre": "glucosa", "etiqueta": "Glucosa en ayunas", "valor": 92.0, "unidad": "mg/dL",
       "estado": "en_rango", "lado": null, "rango_referencia": "70–99 mg/dL (en ayunas)",
       "fuente_rango": "ADA, Standards of Care (…)", "fuente": "documento", "contribucion_anios": -0.3, "nota": null},
      {"nombre": "vcm", "etiqueta": "Volumen corpuscular medio (VCM)", "valor": 90.7, "unidad": "fL",
       "estado": "inferido", "lado": null, "rango_referencia": "80–100 fL", "fuente_rango": null,
       "fuente": "inferido", "contribucion_anios": 0.0, "nota": null}
    ],
    "nota_poblacional": "Los rangos de referencia y la población de comparación vienen mayormente de poblaciones europeas y estadounidenses (NHANES); …",
    "lectura": "Tu edad biológica estimada (28,9) está 5,1 años por debajo de tu edad (34) …"
  },
  "ejes": [
    {"id": "inflamacion", "nombre": "Inflamación", "nivel": "optimo", "nivel_texto": "en rango",
     "biomarcadores": [{"nombre": "hs_CRP", "etiqueta": "Proteína C reactiva (hs-CRP)", "valor": 2.1, "medido": true, "estado": "en_rango"},
                       {"nombre": "leucocitos", "etiqueta": "Leucocitos", "valor": 6.2, "medido": true, "estado": "en_rango"}],
     "aporte_anios": -0.6, "explicacion": "Señales de inflamación de bajo grado en la sangre: … Lo que mediste está dentro de los rangos de referencia. …"}
  ],
  "futuros": {
    "horizonte_anios": 10,
    "curva_base": {"anios": [0, 1, 10], "p10": [26.6, 27.2, 33.7], "mediana": [28.9, 30.0, 40.0], "p90": [31.3, 32.7, 46.1]},
    "sigues_igual": {"titulo": "Si sigues igual", "escenario": "ninguna", "nombre": "Línea base con tus hábitos de hoy",
                     "al_horizonte": {"p10": 33.7, "mediana": 40.0, "p90": 46.1}, "anios_ganados": null, "rango_ganados": null, "texto": "En 10 años …"},
    "si_mejoras": {"titulo": "Si mejoras", "escenario": "ejercicio_aerobico", "nombre": "Ejercicio aeróbico regular",
                   "al_horizonte": {"p10": 32.0, "mediana": 38.3, "p90": 44.7}, "anios_ganados": 1.6, "rango_ganados": [0.6, 2.7], "texto": "Con ejercicio aeróbico regular …"},
    "si_te_descuidas": {"titulo": "Si te descuidas", "escenario": null, "nombre": "Línea base con todos los hábitos en el extremo adverso",
                        "al_horizonte": {"p10": 36.6, "mediana": 42.8, "p90": 48.9}, "anios_ganados": -2.8, "rango_ganados": null, "texto": "Si los seis hábitos … No es una predicción …"},
    "ranking": [
      {"escenario": "ejercicio_aerobico+dieta_mediterranea+sueno_8h", "nombre": "Ejercicio aeróbico regular + dieta mediterránea + dormir 8 horas",
       "intervenciones": ["ejercicio_aerobico", "dieta_mediterranea", "sueno_8h"], "anios_ganados": 2.3, "anios_ganados_p10": 1.3, "anios_ganados_p90": 3.5,
       "pct_futuros_que_mejoran": 100, "esfuerzo": 8, "ratio_impacto_esfuerzo": 0.29, "fuentes": ["Fedewa MV, … Br J Sports Med 2017;51:670–676 (…)", "Estruch R, et al. Ann Intern Med 2006;145:1–11 (…)", "Irwin MR, … Biol Psychiatry 2016;80:40–52 (…)"]}
    ],
    "nota_incertidumbre": "Estimación, no certeza: el rango refleja lo que no sé de ti …"
  },
  "recomendaciones": [
    {"id": "ejercicio_aerobico", "nombre": "Ejercicio aeróbico regular",
     "que_hacer": "150 minutos a la semana de algo que te suba el pulso: caminar rápido, bici, nadar.",
     "por_que": "En tu simulación, ejercicio aeróbico regular baja la inflamación (proteína C reactiva), baja la glucosa en ayunas y baja el recuento de leucocitos; acumulado a 10 años, eso se traduce en +1,6 años …",
     "anios_ganados": 1.6, "rango_ganados": [0.6, 2.7], "pct_futuros_que_mejoran": 98, "esfuerzo": 3,
     "evidencia": [{"hallazgo": "El entrenamiento físico sostenido se asocia con menor proteína C reactiva …", "fuente": "Fedewa MV, Hathaway ED, Ward-Ritacco CL. Br J Sports Med 2017;51:670–676 (…)"}],
     "habito": "actividad física", "brecha": 1.0}
  ],
  "consulta": {
    "disclaimer": "Esto es orientación para que un profesional lo evalúe, no una conclusión. Lleva este reporte a tu consulta: resume lo que Moirai observó.",
    "sugerencias": [{"eje": "ninguno", "nombre": "Control de rutina", "nivel": "optimo", "profesional": "medicina general o familiar",
                     "texto": "Con lo medido no veo ningún eje que pida una consulta especial. Un control preventivo de rutina …"}],
    "lleva_esto": "Lleva este reporte a tu consulta. Resume lo que Moirai observó: …"
  },
  "afinar": {"ancho_banda_hoy": 4.7,
             "faltantes": [{"nombre": "vcm", "etiqueta": "Volumen corpuscular medio (VCM)", "reduccion_banda_anios": 0.8, "fraccion": 0.664}],
             "nota": "Hoy 3 de los 9 biomarcadores del reloj están imputados; …"}
}
```
- **§1 `foto_hoy`** — the 9 PhenoAge biomarkers always (measured or
  `inferido`), plus `colesterol_total` / `presion_sistolica` / `imc` only if
  measured. `estado` ∈ `en_rango | borde | fuera | inferido | sin_rango`
  from `app/health_metrics/reference_ranges.py` (adult clinical reference
  ranges with their source: AHA/CDC for hs-CRP, ADA for fasting glucose, NCEP
  for cholesterol, ACC/AHA for BP, WHO for BMI, usual lab ranges for the
  rest; `borde` = the explicit borderline band — glucose 100–125, cholesterol
  200–239, BP 120–129, BMI 25–29.9 — or, when none, within 10 % of the range
  width past the limit). `fuente` is what the app stored (`documento` /
  `reportado` / `calculado`), `inferido` for imputed. `contribucion_anios` is
  `/phenoage.contribuciones` for that biomarker. `rango_hoy` is year 0 of the
  baseline fan (the band from imputation); `p10 == p90` when all 9 are measured.
- **§2 `ejes`** — the five systemic axes
  (`inflamacion`: hs_CRP, leucocitos · `metabolico`: glucosa, imc ·
  `renal_hepatico`: creatinina, albumina, fosfatasa_alcalina ·
  `hematologico`: vcm, rdw, linfocitos_pct · `cardio_metabolico`:
  presion_sistolica, colesterol_total, imc), each with
  `nivel` ∈ `optimo | a_vigilar | atencion | sin_datos` by a declared rule
  (`app/health_metrics/ejes.py`): `atencion` if any **measured** component is
  `fuera`, `a_vigilar` if any is `borde`, `optimo` if all measured are in
  range, `sin_datos` if nothing in the axis is measured (imputed values never
  count). `aporte_anios` = sum of the axis' PhenoAge contributions.
- **§3 `futuros`** — `curva_base` is `/montecarlo`'s baseline `curva`;
  `sigues_igual` = baseline; `si_mejoras` = the applicable scenario with the
  best `ratio_impacto_esfuerzo` (same paired `anios_ganados` + P10/P90 as
  `/montecarlo`); `si_te_descuidas` = the baseline re-run **with the same
  seed and all six habit gaps fully open** (`brechas = 1`) — the only
  scenario `/montecarlo` doesn't run by default; when the person is already
  at every adverse habit it says so and `anios_ganados` is `null`. `ranking`
  = every applicable scenario (singles + 2–3 combos) sorted by years gained,
  with one literature `fuente` per lever. `si_mejoras` is `null` when no
  lever applies.
- **§4 `recomendaciones`** — the 2–3 **single** levers with the best
  impact/effort for this person (only those with an open gap), each with
  `que_hacer` (the lever's description), `por_que` (which biomarkers it
  moves + the paired years gained), `evidencia[]` (`hallazgo` + `fuente`,
  from `app/health_metrics/evidencia.py` — same provenance as the
  coefficient notes in `interventions.py`), `habito` and the `brecha` the
  effect was scaled by. Empty when nothing applies (then the text says
  "seguir como vas").
- **§5 `consulta`** — triage by **rule**, axis → type of professional, only
  for axes at `a_vigilar`/`atencion` (`atencion` first), each worded as "para
  que lo evalúe"; when nothing is flagged, a single `eje: "ninguno"` routine
  check-up suggestion. Always carries its own `disclaimer`.
- **§6 `afinar`** — the imputed PhenoAge biomarkers ordered by
  `/montecarlo.valor_de_informacion` (how much each would narrow the 10-year
  band), plus a note naming the non-PhenoAge ones not measured.

### `POST /me/health-context/reporte.pdf` → `200`, `application/pdf`
Same optional body. Returns the rendered PDF bytes (never written to disk)
with `Content-Disposition: attachment; filename="moirai-reporte-<Nombre>-<fecha>.pdf"`,
`Cache-Control: no-store` and `X-Moirai-Reporte-Id: rep_…`. With
`"resumen": true` it returns the **one-page summary** for the consultation
(`moirai-resumen-…pdf`): cover line, today's numbers, what's out of range,
the top levers, the triage, what to measure next. Layout: A4, the app's
palette (blue / green = in range / amber = attention, no red) and fonts
(Fredoka for display numbers, Nunito for body — TTFs bundled in
`app/report/fonts/`, OFL; Helvetica fallback if missing), the PhenoAge fan
(P10–P90 band + median + best-scenario line) drawn natively, disclaimer +
privacy line + sources + "Página X de Y" in every footer. Full report is
6–7 pages; typical size 45–70 KB.

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
  "perfil_conocimiento": "general",  // optional; general | curioso | profesional — how technical the reply may be
  "resultado": { "...": "SimulacionResultado.toChatJson() — spec §8 shape, see below" }
}
```
- **Voice.** Moirai answers warm, plain and human: the person should feel
  heard (a short acknowledgement when the question carries worry or doubt),
  get an answer to exactly what they asked, in everyday words and short
  sentences, with any unavoidable term translated in the same sentence. It
  only goes deep-technical (coefficients, units, formulas, sources) when the
  person explicitly asks for it ("explícame la parte técnica", "cómo se
  calcula exactamente"), and simplifies further if asked to. Still first
  person singular, gains not losses, no alarm words, es-CO numbers,
  "estimación, no diagnóstico" the first time a projection comes up.
- `perfil_conocimiento` (optional): picks the register for this turn —
  `general` = zero untranslated jargon (no "percentil"/"mediana"/"biomarcador"
  on their own), `curioso` = concepts may be named with the translation
  alongside, `profesional` = clinical/statistical vocabulary with precision,
  no explaining the basics. Overrides `demografia.perfil_conocimiento` stored
  in the health context (what onboarding saves); omit to use the stored
  value; neither set → `general`. Same closed vocabulary → `422` otherwise.
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

## Voice (`/me/voice`)

Moirai speaking and listening, through ElevenLabs. This API is a **proxy on
purpose**: the ElevenLabs key would be extractable from the APK if the app
called ElevenLabs directly (a `--dart-define` is plain text in the bundle), so
the key stays in the server environment and the app authenticates against us
with the token it already has. Nothing is stored — audio in, audio out, same
request.

Configured with two env vars on Render; without them these endpoints `503`
and every other endpoint keeps working:

| Env var | Qué es |
| --- | --- |
| `ELEVENLABS_API_KEY` | elevenlabs.io → Developers → API Keys. |
| `ELEVENLABS_VOICE_ID` | elevenlabs.io → Voices → la voz → "Copy voice ID". |
| `TTS_MODEL` | Opcional. Default `eleven_flash_v2_5` (~75 ms, 32 idiomas, media unidad de crédito por carácter). `eleven_v3_conversational` suena más expresivo a ~280 ms. Los `eleven_turbo_*` están deprecados. |
| `STT_MODEL` | Opcional. Default `scribe_v2`. |
| `TTS_MAX_CHARS` | Opcional. Default `1500`. |
| `MAX_AUDIO_MB` | Opcional. Default `8`. |

### `GET /me/voice/estado` → `200`
Whether this deployment can speak. Ask once at startup and hide the speaker
and microphone if `disponible` is `false`, instead of discovering a `503`
mid-demo.
```json
{
  "disponible": true,
  "modelo_tts": "eleven_flash_v2_5",
  "modelo_stt": "scribe_v2",
  "max_caracteres": 1500
}
```

### `POST /me/voice/tts` → `200`, `audio/mpeg`
A chat reply, spoken. Send the `reply` from `/me/health-context/chat`
**verbatim** — the server normalizes it for speech before synthesizing
(`app/voice_text.py`), so the app never has to know how its own formatting
sounds:

| En pantalla | Se lee |
| --- | --- |
| `8.240` | `8240` (el punto de miles engañaría al lector) |
| `6,4` | `6,4` — la coma decimal de es-CO ya se lee bien, se conserva |
| `+2,4` / `-1,2` | `más 2,4` / `menos 1,2` |
| `1,1–3,7`, `P10–P90` | `1,1 a 3,7`, `percentil 10 a percentil 90` |
| `79%` | `79 por ciento` |
| `#1` | `número 1` |
| `hs-CRP`, `IMC`, `mg/dL` | nombres completos en español |
| `**negrita**`, viñetas, enlaces | se eliminan |

Nombres propios que fallan a nivel de fonema (Moirai, PhenoAge, *Turritopsis
dohrnii*, NHANES) no se arreglan aquí: van en un pronunciation dictionary de
ElevenLabs.

```json
// request
{
  "texto": "Ejercicio es tu palanca #1: +2,4 años a 10 años (1,1–3,7).",
  "voice_id": "..."   // opcional; solo para probar voces desde /docs. La app no lo manda.
}
```
Respuesta: MP3 en streaming (`mp3_44100_128`), `Cache-Control: no-store` y
`X-Caracteres` con lo que efectivamente se sintetizó. El audio empieza a
llegar antes de estar completo: reprodúcelo en streaming en vez de esperar el
archivo entero.

Texto por encima de `TTS_MAX_CHARS` se recorta **en la última frase que
quepa**, nunca a mitad de palabra.

### `POST /me/voice/stt` → `200`
`multipart/form-data` con un campo `audio` (la grabación del micrófono: m4a,
wav, webm, mp3, ogg, flac…). Devuelve el texto listo para mandarlo como
`message` a `/me/health-context/chat`.
```json
{ "texto": "¿Por qué el ejercicio es mi primera palanca?", "idioma": "spa", "confianza_idioma": 0.98 }
```

### Errores (ambos)
- `402` — la cuenta de ElevenLabs se quedó sin créditos. **Distínguelo**: es
  el caso realista en plan gratis y la señal para caer al TTS local del
  dispositivo sin mostrar un error.
- `413` — el audio supera `MAX_AUDIO_MB` (solo `/stt`).
- `415` — el `content-type` del archivo no es audio (solo `/stt`).
- `422` — no queda nada que leer tras normalizar, o el audio está vacío.
- `429` — rate-limited en ElevenLabs; reintenta en un momento.
- `502` — ElevenLabs rechazó la petición (key inválida o sin el permiso
  correspondiente) o respondió con un error.
- `503` — la voz no está configurada en este despliegue, o no se pudo
  contactar a ElevenLabs.

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
