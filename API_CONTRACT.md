# Moirai — Contrato de API (lo que consume la app Flutter)

> Estado: **borrador vivo**. El backend desplegado (https://platanus-bog-26.onrender.com/docs) ya tiene `/health`, `/me` (GET/PATCH/DELETE) y Supabase Auth; la app los usa de verdad. Todo lo demás de este documento la app lo consume contra un repositorio **mock** (`--dart-define=USE_MOCK_ENGINE=true`, el default) hasta que exista en el backend. Si cambias algo aquí, cambia también `apps/mobile/lib/data/` y viceversa.

## Convenciones

- Base URL: `API_BASE_URL` (dart-define en la app; default `https://platanus-bog-26.onrender.com`, `http://localhost:8000` en local).
- **Auth**: la app hace login/registro **directo con el SDK de Supabase** (`supabase_flutter`). A FastAPI le manda el JWT de Supabase en `Authorization: Bearer <access_token>`; el backend lo valida contra el JWKS del proyecto y saca `user_id` = `sub`. Ningún endpoint (salvo `/health` y `/motor/metadatos`) es anónimo.
- JSON en español, `snake_case`, igual que `MOIRAI_ENGINE_SPEC.md` §3 y §8. Fechas ISO-8601 (`2026-07` para fecha de examen, `2026-08-22T14:03:00Z` para timestamps).
- Errores: `{ "detail": "mensaje legible" }` con 4xx/5xx (default de FastAPI). La app muestra `detail` tal cual, así que debe venir en español y en tono amable (sin "error", sin "inválido").
- Unidades: la app manda siempre las unidades que el usuario escribió (`unidad`); **el backend normaliza** (spec §4). La app no convierte.
- Persistencia: todo se guarda en Supabase bajo el `user_id` del JWT. La app no toca tablas directamente salvo Auth.

---

## 1. Perfil (onboarding)

### Lo que YA existe: `GET /me` · `PATCH /me` · `DELETE /me` (ver `AUTH.md`)
La app ya lo consume tal cual. `GET /me` crea la fila la primera vez; `PATCH /me` acepta cualquier subconjunto de `full_name`, `date_of_birth` (`yyyy-MM-dd`, 18–120 años), `height_cm` (100–250), `weight_kg` (25–350), `blood_type`, `sex_at_birth` (`female|male|intersex`) y devuelve `{ email, profile, answered[], remaining[], total, complete }`. 422 por campo con `detail[].loc/msg` — la app los muestra en línea.

### Lo que FALTA en `/me`: los campos del resto del onboarding
Hoy la app los guarda **en local** (`SharedPreferences`, clave por `user_id`) y los manda dentro del input de `/simular`. Para persistirlos del lado del servidor, la propuesta es **extender `PATCH /me` / `GET /me.profile`** con estos campos (mismo estilo `snake_case` en inglés que ya usa el backend; la app está lista para mapearlos — ver `lib/data/models/onboarding.dart`):

```json
{
  "nationality": "CO",
  "country_of_residence": "CO",
  "ancestry": "mixta_latam",
  "goals": ["energia", "prevencion", "longevidad", "fertilidad"],
  "family_history": [
    { "condition": "diabetes_t2", "relative": "madre" },
    { "condition": "cardiovascular", "relative": "abuelo" }
  ],
  "habits": {
    "sleep_hours": 6,
    "sleep_quality": "media",
    "exercise": "bajo",
    "alcohol": "moderado",
    "alcohol_frequency": "2_3_por_semana",
    "diet": "media",
    "diet_patterns": ["ultraprocesados_frecuentes", "poca_fibra"],
    "smoker": false,
    "stress": "alta"
  },
  "supplements": [
    { "name": "vitamina_d", "dose": "2000 UI", "frequency": "diaria" }
  ],
  "wearable": { "provider": "health_connect", "connected": true, "last_sync": "2026-08-22T14:03:00Z" },
  "photo_url": "https://.../storage/v1/object/.../foto.jpg",
  "genetic_test": { "file_url": "https://.../genetica.pdf", "status": "pendiente" },
  "onboarding_complete": true
}
```

Catálogos (valores exactos que manda la app; el backend debe aceptarlos):
- `objetivos`: `energia | prevencion | longevidad | fertilidad | rendimiento | sueno | peso | salud_mental`
- `historial_familiar[].condicion`: `diabetes_t2 | cardiovascular | hipertension | cancer | alzheimer | obesidad | tiroides | ninguna`
- `historial_familiar[].parentesco`: `madre | padre | hermano | abuelo | otro`
- `sueno_calidad | alimentacion | estres`: `baja | media | alta`
- `ejercicio`: `nulo | bajo | moderado | alto`
- `alcohol`: `nunca | ocasional | moderado | alto`; `alcohol_frecuencia`: `nunca | mensual | 2_3_por_semana | casi_diario | diario`
- `ancestria_reportada`: `mixta_latam | europea | africana | indigena | asiatica | otra | prefiero_no_decir`

### `POST /me/foto` — `multipart/form-data` (`archivo`)
Sube la foto del usuario (opcional en onboarding). Responde `{ "foto_url": "..." }`. Para el demo solo se guarda; el "avatar que envejece" es Fase 2 (spec §1).

### `POST /me/genetica` — `multipart/form-data` (`archivo` PDF)
Sube la prueba genética (opcional). Responde `{ "archivo_url": "...", "estado": "pendiente" }`. El análisis con AI/RAG es Fase 2: el backend solo almacena y deja `estado` en `pendiente | analizado`. `GET /me/genetica` devuelve lo mismo.

---

## 2. Exámenes y biomarcadores

### `POST /examenes/extraer` — `multipart/form-data` (`archivo`: imagen o PDF)
OCR/AI sobre el examen. Devuelve candidatos **con confianza**, para la pantalla "Confirmar lectura":

```json
{
  "biomarcadores": [
    { "nombre": "albumina",   "valor": 4.4, "unidad": "g/dL",  "confianza": "alta"  },
    { "nombre": "glucosa",    "valor": 92,  "unidad": "mg/dL", "confianza": "alta"  },
    { "nombre": "hs_CRP",     "valor": 2.1, "unidad": "mg/L",  "confianza": "media" },
    { "nombre": "rdw",        "valor": 13.1,"unidad": "%",     "confianza": "baja"  }
  ],
  "fecha_examen": "2026-07",
  "no_encontrados": ["creatinina", "leucocitos", "linfocitos_pct", "vcm", "fosfatasa_alcalina"]
}
```
Nombres canónicos (los 9 de PhenoAge, spec §4): `albumina, creatinina, glucosa, hs_CRP, rdw, leucocitos, linfocitos_pct, vcm, fosfatasa_alcalina`. Si falla la extracción, responde `422` con `detail` amable; la app ofrece entrada manual.

### `GET /me/biomarcadores` · `PUT /me/biomarcadores`
Lista confirmada por el usuario (misma forma que spec §3 `biomarcadores[]`, con `fuente: "documento" | "manual" | "inferido"`). El `PUT` reemplaza la lista completa. El backend **no** imputa aquí; imputa en `/simular` y lo reporta en el output.

---

## 3. Simulación (el motor)

### `POST /simular`
Exactamente spec §3 → spec §8. La app arma el input a partir del perfil + biomarcadores guardados, pero lo manda completo (el backend podría también leerlo de Supabase; mandar el JSON evita depender de que el perfil esté persistido — útil para el caso demo).

**Extensiones al output de §8 que la app necesita** (añadir, no quitar nada):

```json
{
  "id": "sim_01J…",
  "creado_en": "2026-08-22T14:03:00Z",
  "...": "todo lo de §8",
  "escenarios": [
    {
      "intervenciones": ["sueno_8h", "ejercicio_moderado"],
      "etiqueta": "Dormir 8 horas + ejercicio moderado",
      "anios_ganados": 4.1,
      "rango": [3.2, 5.0],
      "esfuerzo": 5,
      "ratio_impacto_esfuerzo": 0.82,
      "pct_futuros_que_mejoran": 84,
      "curva": { "anios": [0,1,"…",10], "mediana": [], "p10": [], "p90": [] }
    }
  ],
  "muestra_trayectorias": [[37.8, 38.9, "…"], ["…"]],
  "intervenciones_catalogo": [
    { "id": "sueno_8h", "etiqueta": "Dormir 8 horas", "esfuerzo": 2, "icono": "moon" }
  ]
}
```
- `escenarios`: el barrido completo de spec §6 ya rankeado por `ratio` (la pantalla "Palancas" lo lista entero; `mejor_decision` es `escenarios[0]`). Máximo 3 intervenciones por combo (spec §12).
- `muestra_trayectorias`: 40–80 trayectorias individuales (de las N) para dibujar el abanico "vivo". Opcional; si no viene, la app las sintetiza a partir de p10/mediana/p90.
- `pct_futuros_que_mejoran`: % de corridas donde el escenario termina con menor edad biológica que el baseline pareado (misma semilla).
- El cálculo puede tardar segundos (5000 × combos). Si supera ~8 s, preferir el modo asíncrono de abajo y que `/simular` responda `202` con `{ "id": "sim_…", "estado": "en_proceso" }`.

### `GET /simulaciones/{id}`
Devuelve `{ "estado": "en_proceso" | "lista" | "fallida", "progreso": 0.31, "resultado": <output de /simular o null> }`. La app hace polling cada 1.5 s durante la pantalla "Simulando en vivo" y "En segundo plano".

### `GET /me/simulaciones`
Historial: `[{ "id", "creado_en", "edad_biologica_hoy", "mejor_decision": { "intervenciones", "anios_ganados" } }]`, más reciente primero.

### `POST /simulaciones/{id}/plan`
El usuario guarda un escenario como "mi plan": `{ "intervenciones": ["sueno_8h"], "adherencia": "8_meses" }` → `200 { "guardado": true }`. `adherencia`: `3_meses | 8_meses | 2_anios | siempre`. (Simular adherencia imperfecta es Fase 2; por ahora solo se guarda.)

---

## 4. Wearables

La lectura la hace la **app** con Health Connect (Android) / HealthKit (iOS) vía el paquete `health`; el backend solo recibe agregados diarios. Nada de tokens OAuth de terceros en el back.

### `POST /wearables/sincronizar`
```json
{
  "proveedor": "health_connect",
  "dias": [
    { "fecha": "2026-08-21", "sueno_h": 6.4, "sueno_calidad_score": 71, "pasos": 8240, "minutos_ejercicio": 22, "fc_reposo": 61 }
  ]
}
```
Responde `{ "dias_guardados": 14, "habitos_actualizados": { "sueno_h": 6.3, "ejercicio": "bajo" } }` — el backend puede recalcular `habitos_moduladores` a partir de los últimos 14 días y la app refresca el perfil.

---

## 5. Respaldo / metodología

### `GET /motor/metadatos` (anónimo)
Para la pestaña "Respaldo": `{ "version_motor": "0.1.0", "capas": [ { "nombre": "PhenoAge", "fuente": "Levine et al. 2018, Aging", "url": "..." }, { "nombre": "Deriva anual", "fuentes": [ { "intervencion": "ejercicio_moderado", "biomarcador": "hs_CRP", "efecto": -0.08, "cita": "..." } ] } ], "n_montecarlo": 5000, "datos_poblacion": "NHANES 2017-2020", "descargo": "Estimación de riesgo poblacional, no diagnóstico…" }`.

### `GET /demo/perfil` (anónimo)
El caso demo precargado (spec §9 + §11 paso 9): devuelve un input completo de §3 listo para `POST /simular`. La app lo usa en el botón "Probar con un caso de ejemplo" y como red de seguridad si falla el OCR en vivo.

---

## Resumen de endpoints

| Método | Ruta | Auth | Pantalla que lo usa |
| --- | --- | --- | --- |
| GET | `/health` | no | — |
| GET | `/motor/metadatos` | no | Respaldo |
| GET | `/demo/perfil` | no | Bienvenida / Exámenes (fallback) |
| GET/PATCH/DELETE | `/me` ✅ existe | sí | Onboarding, Perfil |
| PATCH | `/me` (campos extendidos, ver §1) | sí | Onboarding, Perfil |
| POST | `/me/foto` | sí | Onboarding (foto) |
| POST/GET | `/me/genetica` | sí | Onboarding (genética) |
| POST | `/examenes/extraer` | sí | Subir exámenes |
| GET/PUT | `/me/biomarcadores` | sí | Confirmar lectura |
| POST | `/simular` | sí | Simulando |
| GET | `/simulaciones/{id}` | sí | Simulando (polling) |
| GET | `/me/simulaciones` | sí | Perfil (historial), Tu futuro |
| POST | `/simulaciones/{id}/plan` | sí | Detalle de palanca |
| POST | `/wearables/sincronizar` | sí | Onboarding (wearables), Perfil |
