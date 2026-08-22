# Moirai — Qué consume la app Flutter del backend (y qué le falta)

> La referencia autoritativa del backend es [`apps/backend/API.md`](apps/backend/API.md) (+ `/docs` en https://platanus-bog-26.onrender.com/docs). Este archivo documenta **cómo la app (`apps/mobile`) usa cada endpoint** y la lista de cosas que la app todavía resuelve en local porque el backend no las expone. Si cambia un router, actualizar `API.md`, este archivo y `apps/mobile/lib/data/`.

## Auth (token propio del backend, sin Supabase SDK)

| Endpoint | Uso en la app |
| --- | --- |
| `POST /auth/signup` · `POST /auth/login` | `AuthRepository.signUp/signIn`. El `token` se guarda en `TokenStore` (flutter_secure_storage) con `user.id`, `email`, `expires_at`. Tras signup, `PATCH /me {full_name}` si el usuario escribió nombre. |
| `GET /auth/session` | `validarSesion()` al arrancar (un 401 limpia la sesión local; errores de red no). |
| `POST /auth/logout` | "Cerrar sesión" (best-effort) + borrar token local. |
| `POST /auth/password` | "Cambiar contraseña" en Perfil (guarda el nuevo `SessionOut`). |
| `POST /auth/delete-account` | "Borrar mis datos" en Perfil (pide contraseña). |

`ApiClient` manda `Authorization: Bearer <token>` en todo lo demás y, ante un 401 con token guardado, dispara `onUnauthorized` → la app vuelve a Bienvenida.

## Perfil y contexto de salud

| Endpoint | Uso en la app |
| --- | --- |
| `GET/PATCH /me` | Onboarding pasos a/b (nombre, nacimiento, sexo `F|M`, estatura, peso, sangre) y Perfil → "Datos básicos". 422 por campo se muestra inline. |
| `GET/PATCH /me/health-context` | `ProfileRepository.syncOnboarding()` manda, tras cada cambio del onboarding: `demografia.ancestria_reportada`, `habitos {sueno_h, tabaco, actividad(baja|media|alta), alimentacion, estres(bajo|medio|alto)}`, `historia_familiar` (`condicion` o `condicion:parentesco`), `objetivos_usuario`. `pushBiomarcadores()` reemplaza `biomarcadores` (solo nombres/unidades/rangos válidos, + `imc` calculado desde `/me`) y `datos_faltantes`. |
| `POST /me/health-context/biomarkers/extract` | Pantalla "Subir exámenes" (foto/PDF, campo `file`). La app muestra `guardados`/`biomarcadores` en "Confirmar lectura" y `advertencias` como aviso ámbar; al confirmar hace `PATCH biomarcadores` con la lista editada. |

## Simulación

| Endpoint | Uso en la app |
| --- | --- |
| `POST /me/health-context/phenoage` | Edad biológica hoy, `valores_usados`, `campos_inferidos` (→ "inferido" en la UI). |
| `POST /me/health-context/montecarlo` | `{escenarios, n_trayectorias: 5000, anios: 10}`. La app pide `ninguna`, `ejercicio_aerobico`, `dieta_mediterranea` y, solo si `tabaco == true`, `cesacion_tabaco` + `combinada`. |
| `POST /me/health-context/chat` | Pantalla "Pregúntame" (`/chat`; también desde el detalle de una palanca y desde "Por qué" en Futuro vía `Routes.chatCon`). `ChatRepository.enviar` manda `message`, `history` (stateless, se devuelve tal cual), `resultado` = `SimulacionResultado.toChatJson()` (spec §8 sin `muestra_trayectorias`, curvas a 1 decimal) y `enfoque` (`escenario:<i>` · `porque` · `incertidumbre` · `biomarcador:<nombre>` · `medir` · `poblacion`). El backend recupera solo los fragmentos relevantes (RAG léxico, `app/chat_rag/`) y devuelve `reply`, `history` y `fuentes`; la app pinta las fuentes como "Leí: …" bajo cada respuesta. |

Cómo se arma el resultado de la spec §8 (`SimulationRepository._simularRemoto`): `edad_biologica_hoy` = phenoage; `trayectoria_baseline` = interpolación de hoy al año 10 (mediana lineal, banda ∝ √t) con los P10/mediana/P90 del escenario `ninguna`; cada escenario → `anios_ganados` = mediana base − mediana escenario, `rango` ≈ ±1,28·sd (sd de la banda, pareado ×0,5), `pct_futuros_que_mejoran` ≈ Φ(delta/sd), `esfuerzo` de una tabla local (3/3/4/10), `ratio` = ganados/esfuerzo; `shap_top_drivers` y `comparacion_poblacional` son aproximaciones locales sobre `valores_usados`; `muestra_trayectorias` son líneas ilustrativas coherentes con la banda.

## Lo que la app resuelve en local porque el backend aún no lo expone

1. **Curva por año y trayectorias**: `/montecarlo` solo devuelve percentiles al horizonte. Ideal: `curvas: {anio: {p10, mediana, p90}}` y `muestra_trayectorias` (40–80) por escenario, y `pct_futuros_que_mejoran` pareado por semilla.
2. **SHAP / "por qué"** y **percentil poblacional NHANES** (spec §7/§8): hoy aproximados en el dispositivo.
3. **Catálogo de escenarios según hábitos** (p. ej. sueño, alcohol, estrés de la spec §5) y **esfuerzo** por escenario: la app usa 4 escenarios fijos + tabla local de esfuerzo.
4. **Wearables** (`/wearables/sincronizar`): la app lee Health Connect/HealthKit y recalcula `sueno_h`/`actividad` en local; luego los sube con `PATCH /me/health-context.habitos`.
5. **Campos del onboarding sin sitio en `health-context`**: nacionalidad/país, alcohol (frecuencia), patrones de alimentación, suplementos, proveedor de wearable, foto y prueba genética (PDF). Viven en `SharedPreferences` (clave por `user_id`). Propuesta: aceptarlos en `demografia`/`habitos` (`extra="forbid"` hoy los rechaza) y endpoints `POST /me/foto`, `POST /me/genetica` (storage).
6. **Historial de simulaciones** y **"mi plan"** (escenario + adherencia): local. Propuesta: `GET /me/simulaciones`, `POST /me/simulaciones/{id}/plan`. Mientras tanto, el chat recibe el resultado compacto en cada turno (`resultado`); si el backend guardara la última simulación, la app dejaría de mandarlo.
7. **Caso demo precargado** (spec §11 paso 9): vive en `DemoData` + motor mock (`--dart-define=USE_MOCK_ENGINE=true`). Propuesta: `GET /demo/perfil` o una cuenta demo sembrada.

## Catálogos que la app manda (y el backend acepta como texto libre)

- `objetivos_usuario`: `energia | prevencion | longevidad | fertilidad | rendimiento | sueno | peso | salud_mental`
- `historia_familiar[]`: `diabetes_t2 | cardiovascular | hipertension | cancer | alzheimer | obesidad | tiroides` (opcional `:madre|padre|hermano|abuelo|otro`)
- `habitos.actividad`: `baja | media | alta` · `habitos.alimentacion`: `baja | media | alta` · `habitos.estres`: `bajo | medio | alto`
- `demografia.ancestria_reportada`: `mixta_latam | europea | africana | indigena | asiatica | otra | prefiero_no_decir`
