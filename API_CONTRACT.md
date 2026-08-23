# Moirai - Qué consume la app Flutter del backend (y qué le falta)

> La referencia autoritativa del backend es [`apps/backend/API.md`](apps/backend/API.md) (+ `/docs` en https://platanus-bog-26.onrender.com/docs). Este archivo documenta **cómo la app (`apps/mobile`) usa cada endpoint** y la lista de cosas que la app todavía resuelve en local porque el backend no las expone. Si cambia un router, actualizar `API.md`, este archivo y `apps/mobile/lib/data/`.

## Auth (token propio del backend, sin Supabase SDK)

| Endpoint | Uso en la app |
| --- | --- |
| `POST /auth/signup` - `POST /auth/login` | `AuthRepository.signUp/signIn`. El `token` se guarda en `TokenStore` (flutter_secure_storage) con `user.id`, `email`, `expires_at`. Tras signup, `PATCH /me {full_name}` si el usuario escribió nombre. |
| `GET /auth/session` | `validarSesion()` al arrancar (un 401 limpia la sesión local; errores de red no). |
| `POST /auth/logout` | "Cerrar sesión" (best-effort) + borrar token local. |
| `POST /auth/password` | "Cambiar contraseña" en Perfil (guarda el nuevo `SessionOut`). |
| `POST /auth/delete-account` | "Borrar mis datos" en Perfil (pide contraseña). |

`ApiClient` manda `Authorization: Bearer <token>` en todo lo demás y, ante un 401 con token guardado, dispara `onUnauthorized` -> la app vuelve a Bienvenida.

## Perfil y contexto de salud

| Endpoint | Uso en la app |
| --- | --- |
| `GET/PATCH /me` | Onboarding pasos a/b (nombre, nacimiento, sexo `F|M`, estatura, peso, sangre) y Perfil -> "Datos básicos". 422 por campo se muestra inline. |
| `GET/PATCH /me/health-context` | `ProfileRepository.syncOnboarding()` manda, tras cada cambio del onboarding: `demografia.ancestria_reportada`, `demografia.perfil_conocimiento` (paso "¿Qué tanto sabes de salud?" del onboarding, editable en Perfil -> "Cómo te explico"; el chat lo usa para su registro), `habitos {sueno_h, tabaco, actividad(baja|media|alta), alimentacion(baja|media|alta), estres(bajo|medio|alto), alcohol(nunca|ocasional|moderado|alto)}`, `historia_familiar` (`condicion` o `condicion:parentesco`), `objetivos_usuario`. **El motor lee `habitos`**: ajusta la línea base de la persona y decide qué palancas aplican (ver `/montecarlo`). `pushBiomarcadores()` reemplaza `biomarcadores` (solo nombres/unidades/rangos válidos, + `imc` calculado desde `/me`) y `datos_faltantes`. |
| `POST /me/health-context/biomarkers/extract` | Pantalla "Subir exámenes" (foto/PDF, campo `file`). La app muestra `guardados`/`biomarcadores` en "Confirmar lectura" y `advertencias` como aviso ámbar; al confirmar hace `PATCH biomarcadores` con la lista editada. |

## Simulación

| Endpoint | Uso en la app |
| --- | --- |
| `POST /me/health-context/phenoage` | Edad biológica hoy, `valores_usados`, `campos_inferidos` (-> "inferido" en la UI), `contribuciones` (el "por qué" de los biomarcadores medidos frente a la mediana de referencia), `percentil_poblacional` y `aceleracion_referencia` ("frente a personas como tú"). |
| `POST /me/health-context/montecarlo` | `{n_trayectorias: 10000, anios: 10}` **sin `escenarios`**: el backend decide qué palancas aplican según los hábitos guardados (ejercicio, dieta, tabaco, sueño, estrés, alcohol) y corre cada una sola y sus combinaciones de 2 y 3 (spec sec. 6/sec. 12), todo pareado con la misma semilla. La app consume `escenarios[]` (con `curva` por año, `anios_ganados` + `_p10`/`_p90`, `pct_futuros_que_mejoran`, `esfuerzo`, `ratio_impacto_esfuerzo`, `aplica`, `descripcion`), `palancas[]` (catálogo evaluado: `brecha`, `aplica`), `muestra_trayectorias`, `valor_de_informacion`, `contribuciones_habitos`, `ancho_banda_hoy` y `semilla`. |
| `POST /me/health-context/reporte` - `POST /me/health-context/reporte.pdf` | Pantalla "Tu reporte" (`/reporte`, push desde la tarjeta "Tu reporte para el médico" en "Tu futuro" y desde Perfil). `ReportRepository.obtener()` pide el JSON **sin cuerpo** (defaults del motor = lo que la app simuló) y la pantalla lo muestra: foto de hoy, ejes (nivel por regla), recomendaciones (2-3 palancas con evidencia), ranking de combinaciones, con quién consultar (triage por regla) y qué medir. "Descargar PDF" / "Resumen de 1 página" -> `descargarPdf(resumen:)` guarda los bytes en el directorio temporal (`path_provider`) y abre la hoja de compartir (`share_plus`) para guardarlo o mandárselo al médico. Con `USE_MOCK_ENGINE` el reporte no está disponible (necesita el motor real; la pantalla lo dice). |
| `POST /me/health-context/chat` | Pantalla "Pregúntame" (pestaña `/preguntame` del bottom nav y `/chat` a pantalla completa; también desde el detalle de una palanca y desde "Por qué" en Futuro vía `Routes.chatCon`). `ChatRepository.enviar` manda `message`, `history` (stateless, se devuelve tal cual), `resultado` = `SimulacionResultado.toChatJson()` (spec sec. 8 sin `muestra_trayectorias`, curvas a 1 decimal), `enfoque` (`escenario:<i>` - `porque` - `incertidumbre` - `biomarcador:<nombre>` - `medir` - `poblacion`) y `perfil_conocimiento` (el del onboarding local, en cada turno, para que el registro sea el correcto aunque el sync no haya llegado; sin él el backend usa el guardado y si no hay, `general`). Moirai responde cálida y sencilla siempre, y técnica solo si la persona lo pide explícitamente. El backend recupera solo los fragmentos relevantes (RAG léxico, `app/chat_rag/`) y devuelve `reply`, `history` y `fuentes`; la app pinta las fuentes como "Leí: ..." bajo cada respuesta. |

| `GET /me/voice/estado` - `POST /me/voice/tts` - `POST /me/voice/stt` | La voz de Moirai en "Pregúntame". `VoiceRepository`: `estado()` una vez por sesión (si `disponible` es `false`, la app usa la voz del teléfono en vez de mostrar un error); `audioDe(texto)` manda el `reply` **tal cual** - la normalización para voz la hace el backend - y guarda el MP3 en el directorio temporal con el nombre derivado del texto, así que volver a tocar el altavoz no gasta créditos; `transcribir(ruta)` sube la grabación (`record`, AAC-LC 16 kHz mono) como campo `audio` y devuelve la pregunta, que se envía al chat. `402` (sin créditos) y `503` (voz no configurada) caen a `flutter_tts` en silencio y el ícono del altavoz lo dice; cualquier otro error sí se cuenta. Los MP3 se borran al cerrar sesión. |

Cómo se arma el resultado de la spec sec. 8 (`SimulationRepository.armarResultado`): `edad_biologica_hoy` = phenoage; `trayectoria_baseline` y cada `curva` vienen **año a año del motor** (`escenarios[].curva`); `anios_ganados`/`rango`/`pct_futuros_que_mejoran`/`esfuerzo`/`ratio` vienen del motor (pareados); `shap_top_drivers` = `contribuciones` de `/phenoage` (biomarcadores, hoy) + `contribuciones_habitos` de `/montecarlo` (hábitos, a 10 años); `comparacion_poblacional` = `percentil_poblacional`; `muestra_trayectorias` son las 40 trayectorias reales del motor; `intervenciones_catalogo` sale de `palancas[]`; `valor_de_informacion` alimenta "Qué medir". **Compatibilidad**: si el backend es viejo y no trae `curva`/`anios_ganados`/etc., la app cae a las aproximaciones de antes (interpolación √t, Φ(delta/sd), tabla local de esfuerzo, SHAP y percentil locales) y lo marca con `fuente_curvas = "interpolada"`.

## Lo que la app resuelve en local porque el backend aún no lo expone

1. ~~Curva por año y trayectorias~~ **Resuelto en el backend** (2026-08-22): `/montecarlo` devuelve `curva` por año por escenario, `muestra_trayectorias`, y `anios_ganados`/`pct_futuros_que_mejoran` pareados por semilla.
2. ~~SHAP / "por qué" y percentil poblacional~~ **Resuelto en el backend**: `/phenoage.contribuciones` + `/montecarlo.contribuciones_habitos`; `/phenoage.percentil_poblacional` (centrado en la persona de referencia de la edad/sexo). Sigue sin ser SHAP sobre las 10.000 trayectorias (spec sec. 12: basal basta).
3. ~~Catálogo de escenarios según hábitos y esfuerzo~~ **Resuelto en el backend**: 6 palancas (ejercicio, dieta, tabaco, sueño, estrés, alcohol) con `esfuerzo` y `descripcion` propios, aplicabilidad por hábito (`brecha`), combinaciones de 2-3 y `GET /engine/catalogo` para Respaldo. Pendiente en el motor: **adherencia** (la app sigue aplicando factores locales 0,25 - 0,5 - 0,8 - 1, marcados como aproximación).
4. **Wearables** (`/wearables/sincronizar`): la app lee Health Connect/HealthKit y recalcula `sueno_h`/`actividad` en local; luego los sube con `PATCH /me/health-context.habitos`.
5. **Campos del onboarding sin sitio en `health-context`**: nacionalidad/país, patrones de alimentación, suplementos, proveedor de wearable, foto y prueba genética (PDF) (el alcohol ya viaja en `habitos.alcohol`). Viven en `SharedPreferences` (clave por `user_id`). Propuesta: aceptarlos en `demografia`/`habitos` (`extra="forbid"` hoy los rechaza) y endpoints `POST /me/foto`, `POST /me/genetica` (storage).
6. **Historial de simulaciones** y **"mi plan"** (escenario + adherencia): local. Propuesta: `GET /me/simulaciones`, `POST /me/simulaciones/{id}/plan`. Mientras tanto, el chat recibe el resultado compacto en cada turno (`resultado`); si el backend guardara la última simulación, la app dejaría de mandarlo.
7. ~~Reporte descargable~~ **Resuelto en el backend** (2026-08-22): `/reporte` (JSON) + `/reporte.pdf` (PDF completo o resumen de 1 página) desde el motor real; la app solo lo muestra y lo comparte.
8. **Caso demo precargado** (spec sec. 11 paso 9): vive en `DemoData` + motor mock (`--dart-define=USE_MOCK_ENGINE=true`). Propuesta: `GET /demo/perfil` o una cuenta demo sembrada.

## Catálogos que la app manda (y el backend acepta como texto libre)

- `objetivos_usuario`: `energia | prevencion | longevidad | fertilidad | rendimiento | sueno | peso | salud_mental`
- `historia_familiar[]`: `diabetes_t2 | cardiovascular | hipertension | cancer | alzheimer | obesidad | tiroides` (opcional `:madre|padre|hermano|abuelo|otro`)
- `habitos.actividad`: `baja | media | alta` - `habitos.alimentacion`: `baja | media | alta` - `habitos.estres`: `bajo | medio | alto` - `habitos.alcohol`: `nunca | ocasional | moderado | alto` (la app lo deriva de `alcohol_frecuencia`: nunca->nunca, mensual->ocasional, 2_3_por_semana->moderado, casi_diario/diario->alto)
- `demografia.ancestria_reportada`: `mixta_latam | europea | africana | indigena | asiatica | otra | prefiero_no_decir`
- `demografia.perfil_conocimiento`: `general | curioso | profesional` (este sí lo valida el backend: otro valor es 422; la app solo manda valores del catálogo)
