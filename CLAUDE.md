# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este repo

**Moirai / "Diez Mil Futuros"** — proyecto del team-37 para Platanus Hack 26 Bogotá (track *Simulations*). Una app móvil que toma pocos datos de una persona (≈8 básicos + exámenes opcionales), corre una microsimulación Monte Carlo de su salud futura y devuelve **una** recomendación protagonista: qué palanca (hábito) gana más años sanos por unidad de esfuerzo, con su rango de incertidumbre y el porqué.

Tres documentos son la fuente de verdad, en este orden de precedencia cuando se contradicen (y se contradicen — ver "Decisiones tomadas"):

1. [MOIRAI_ENGINE_SPEC.md](MOIRAI_ENGINE_SPEC.md) — el motor (3 capas + esquemas JSON de input/output + orden de construcción + lo que NO se hace). Léelo completo antes de tocar el backend.
2. `screens.zip` (mockups más recientes, 16 pantallas, canvas "Diez Mil Futuros") + [design/](design/) (misma canvas, versión anterior, con los scripts que la generan y las anotaciones de producto en [design/canvas.json](design/canvas.json)). Léelos antes de tocar UI.
3. El design system dentro de `screens.zip` (`_ds/evara-health-design-system-*/readme.md` + `tokens/*.css`): voz, color, tipografía, motion.

El backend real está documentado en [apps/backend/API.md](apps/backend/API.md) (leerlo antes de tocar cualquier llamada de red); [API_CONTRACT.md](API_CONTRACT.md) dice cómo la app usa cada endpoint y qué sigue resuelto en local. `AUTH.md` está obsoleto (era el flujo Supabase). No commitear/pushear sin que lo pidan.

## Layout del monorepo

```
apps/web/       Next.js 16 + Tailwind 4 + shadcn (starter de Platanus, npm workspace @team-37/web). Deploy Vercel.
apps/backend/   FastAPI (Python) + Postgres (Supabase). Deploy Render vía /render.yaml (rootDir apps/backend). Aquí vive el motor; contrato en apps/backend/API.md.
apps/mobile/    Flutter app (el frontend del producto; ver su README.md).
design/         Generadores de los artboards (.dc.html) + tokens. No es código de producto.
```

## Comandos

### Web (`apps/web`, desde la raíz)
- `npm ci` · `npm run dev` (http://localhost:3000) · `npm run check` (lint + typecheck) · `npm run build`
- Node 24.x (`.nvmrc`). Agregar componentes shadcn desde `apps/web`: `npx shadcn@latest add <comp>`.

### Backend (`apps/backend`)
```bash
cd apps/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload          # http://localhost:8000 · /docs · /health
```
- Nuevo endpoint: `app/routers/<x>.py` con `APIRouter` + `app.include_router(...)` en `app/main.py`.
- Nuevo secreto/config: campo en `Settings` (`app/config.py`), env var en Render. Todo tiene default; no hace falta `.env` para arrancar.
- `/health` debe seguir sin dependencias (Render lo usa para decidir si el deploy pasó). Bind a `$PORT` en producción.
- Routers reales: `auth`, `profile` (`/me`), `health_context`, `lab_upload` (extracción con Claude), `biological_age` (`/phenoage`, `/montecarlo`), `health_chat`. Cualquier cambio en un router se refleja en `API.md` en el mismo cambio.
- Esquema SQL en `schema.sql` (`scripts/apply_schema.py`). Secretos: `DATABASE_URL`, `ANTHROPIC_API_KEY` (env en Render).
- No hay tests aún. Cuando se agreguen: `pytest` (agregar a `requirements.txt`); test individual `pytest tests/test_x.py::test_y`.

### Mobile (`apps/mobile`, Flutter — el frontend del producto)
- Flutter está en `~/.local/share/flutter` (clon `stable`, 3.47); **no está en el PATH del shell**: anteponer `export PATH="$HOME/.local/share/flutter/bin:$PATH" ANDROID_HOME="$HOME/Android/Sdk"` a cada comando. Android SDK en `~/Android/Sdk` (sin `cmdline-tools`, así que `flutter doctor --android-licenses` no corre; la licencia principal ya está aceptada).
- `flutter pub get` · `flutter run` · `flutter analyze --no-pub` · `flutter test` · un test: `flutter test test/mock_engine_test.dart` · `flutter build apk --release` (el APK es lo que va en `deploy-url` de `platanus-hack-project.jsonc`).
- Config en compilación (`--dart-define`): `API_BASE_URL` (default https://platanus-bog-26.onrender.com) y `USE_MOCK_ENGINE` (default `false`; `true` = simulación, lectura de exámenes y chat con mocks locales para demo sin red).
- Paleta exacta para Dart: `node design/tokens-hex.mjs` imprime las constantes `Color(0xFF…)` (ya copiadas en `lib/app/theme/tokens.dart`).

Arquitectura de `apps/mobile/lib/` (Riverpod 2 con `Notifier`, go_router, Material 3):
- `app/` — `theme/` (tokens + `MoiraiTheme`), `providers.dart` (todos los providers: sesión vía `TokenStore`, `/me`, onboarding (local + sync a `/me/health-context`), biomarcadores (local + PATCH), `simulacionInputProvider` que arma el JSON de la spec §3, `simulationProvider` con estados `SimIdle/SimRunning/SimDone/SimFailed`), `router.dart` (`Routes` + redirect auth → onboarding → shell; `/chat` fuera del shell).
- `data/` — `api/api_client.dart` (única puerta al backend, `Authorization: Bearer` del token propio; 401 → cierra sesión) + `api/token_store.dart` (flutter_secure_storage), `models/` (espejo de spec §3/§8, `/me`, chat), `repositories/` (auth backend, perfil + health-context, exámenes vía `/biomarkers/extract`, simulación = `/phenoage` + `/montecarlo` adaptados a la forma de la spec §8, chat, wearables con `health`), `mock/mock_engine.dart` (port en Dart de las 3 capas para demo sin backend; `test/mock_engine_test.dart` valida los invariantes de la spec §9).
- `features/<flujo>/` — pantallas: `auth`, `onboarding`, `exams`, `simulation`, `future`, `levers`, `backing`, `profile`, `chat` ("Pregúntame", agente Haiku del backend), `shell` (bottom nav Futuro · Simular · Respaldo · Perfil).
- `widgets/` — piezas compartidas: `mo.dart` (MoScreen/MoCard/MoChoice/MoPrimaryButton/…), `mascot.dart` (mascota animada en código), `big_number.dart` (count-up), `fan_chart.dart` (abanico P10–P90 + trayectorias, `CustomPainter`), `lever_card.dart`.

### Design (`design/`)
- `node design/gen-curves.mjs` regenera `curves.json` (trayectorias seeded para los artboards); `node design/build-{a..e}.mjs` regeneran los `.dc.html` de cada flujo (A ingreso, B simulación, C futuro, D simular, E respaldo). `diez-mil-futuros.html` es la canvas publicada (2.4 MB, no editar a mano).

## Arquitectura del motor (backend)

Tres capas apiladas, nunca mezcladas (spec §2):

1. **Medidor — PhenoAge (Levine 2018)**: determinista, mide edad biológica HOY a partir de 9 biomarcadores + edad. No predice. Verificar coeficientes y unidades contra el paper y documentar la fuente en el código; un resultado de 200 o −30 años es error de unidades.
2. **Motor de evolución**: deriva anual por biomarcador + efecto de cada intervención → estado(t+1). Coeficientes aproximados pero citables de literatura; nunca inventados-y-presentados-como-verdad.
3. **Monte Carlo**: corre la capa 2 N veces con ruido → mediana/P10/P90 por año. Biomarcadores imputados (medianas NHANES) ⇒ más sigma ⇒ banda más ancha. Luego barrido de combinaciones de 1–3 intervenciones rankeadas por años ganados / esfuerzo, y SHAP solo sobre el estado basal.

En el backend real esto vive en `app/health_metrics/` (`phenoage.py`, `interventions.py`, `montecarlo.py`, `nhanes_reference.py`) y se expone como `POST /me/health-context/phenoage` + `POST /me/health-context/montecarlo` (percentiles al horizonte por escenario; todavía no devuelve curvas por año ni SHAP — la app los aproxima, ver API_CONTRACT.md). La spec §3/§8 sigue siendo la forma objetivo del resultado; validar cada capa con el caso de prueba de §9. Siempre debe existir un **caso demo precargado** — nunca depender de upload/OCR en vivo durante el pitch.

Lo que explícitamente NO se construye (spec §12): foto envejecida, dieta/suplementos/alergias, genética, >3 intervenciones simultáneas, SHAP sobre las 5000 trayectorias.

## Flujo de pantallas (mockups, 16 artboards 390×844)

- **A · Ingreso**: Bienvenida → Datos básicos (8 datos, el abanico se va cerrando en la esquina a medida que respondes) → Subir exámenes (foto/archivo/manual, opcional) → Confirmar lectura (cada valor con confianza alta/media/baja; baja confianza = rango más ancho, no "más falso").
- **B · Simulación visible**: "Simulando en vivo" (las trayectorias se dibujan una por una y el contador de vidas sube de verdad — reemplaza al spinner) → En segundo plano → Notificación.
- **C · Tu futuro**: pantalla principal (titular = años sin enfermedad crónica, rango tipografiado tan grande como el número, "lo que puedes mover" al lado) → "Estás bien" (estado vacío honesto) → Qué conviene medir (qué dato angosta más el rango) → Curva de supervivencia (mortalidad, solo tras un toque deliberado, nunca por defecto).
- **D · Simular**: Palancas ordenadas por cuánto mueven la distribución → Detalle pareado (mismos futuros, misma semilla, una sola variable cambiada) → Adherencia (slider "¿cuánto lo sostienes?": 3 meses / 8 meses / 2 años / siempre).
- **E · Respaldo**: Calibración (88% de cobertura del rango del 90% en 5.000 personas de NHANES no vistas) → Caso individual (3 datos → lo que dije → lo que pasó).
- Bottom nav: Futuro · Simular · Respaldo. El chip "calibración 88%" del header lleva a E desde cualquier pantalla.

## Reglas de producto/diseño (no negociables en la UI)

- **Ningún número sin su palanca al lado; ningún delta sin su intervalo.** Los rangos son anchos a propósito y se muestran tan grandes como el número.
- **Voz**: primera persona del singular, la mascota le habla al usuario ("estoy simulando", "esto es lo que leí", "no encontré nada"). Nunca "nosotros". Español colombiano. Enmarcar como ganancia ("+2,4 años"), nunca como pérdida. "Estimación, no diagnóstico" aparece donde se muestra una proyección por primera vez.
- **Color**: azul clínico suave (marca) + verde (bien/mejora) + ámbar (atención). **Rojo en ninguna parte.** Sin emoji. Sin "risk score", "abnormal", "crítico", streaks.
- **Tipografía**: Fredoka (números grandes/display) + Nunito (cuerpo) en los mockups actuales (el DS anterior decía Quicksand; los mockups mandan). Números siempre en cifras, formato es-CO (`8.240`, `6,4`), un decimal máximo.
- **Mascota**: cuatro estados — idle/tranquilo, working, gentle (malas noticias), happy. **Nunca triste.** En mockups es SVG animado; en Flutter la anotación del diseño sugiere Rive o Lottie.
- **Motion**: suave, nada parpadea; los números grandes hacen count-up (~900 ms); radios ≥ 8 px, cards 24 px, botones pill, touch ≥ 48 px.

## Decisiones tomadas (2026-08-22)

- **La spec manda; los mockups son guía.** Cuando `screens.zip` y `MOIRAI_ENGINE_SPEC.md` se contradicen (métrica protagonista, biomarcadores, palancas, calibración), se sigue la spec: edad biológica PhenoAge proyectada a 10 años, 9 biomarcadores (6 núcleo + imputados), intervenciones y esquemas JSON de §3/§8. De los mockups se toma el flujo de pantallas, la voz, el color y las animaciones.
- **Frontend = app Flutter**, Material Design (Material 3), con el mismo acabado en Android e iOS. Animaciones y vistas son parte del producto, no decoración.
- **Auth propia del backend** (`/auth/*`, token opaco de 90 días guardado en keychain; Supabase es solo el Postgres). **Datos vía el backend** (`apps/backend`, FastAPI), desplegado aparte en https://platanus-bog-26.onrender.com (docs en `/docs`; free tier: la primera request tras 15 min tarda 30–50 s, pegarle a `/health` antes de un demo). Endpoints reales: `/me`, `/me/health-context` (+ `/biomarkers/extract` con Claude), `/phenoage`, `/montecarlo`, `/chat` (claude-haiku-4-5). Lo que el backend aún no expone (curvas por año, SHAP, historial, plan, foto/genética, wearables) la app lo resuelve en local — lista en [API_CONTRACT.md](API_CONTRACT.md).
- Onboarding tras registro: peso, edad, demografía, nacionalidad, historial familiar, objetivos (energía, prevención, longevidad, fertilidad…), suplementos, wearables (Health Connect / HealthKit vía paquete `health`; sin OAuth de terceros), alcohol y alimentación, foto opcional y prueba genética en PDF opcional (se guarda; el análisis con AI/RAG es Fase 2).
- La mascota se llama **Moirai** (nombre de `screens.zip`, el más reciente); "Tino" en `design/` es la versión vieja.
- OCR de exámenes: mock en la app (`/examenes/extraer` en el contrato) hasta que el back lo implemente.
