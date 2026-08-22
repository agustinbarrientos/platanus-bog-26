# Moirai — app Flutter

La app móvil de Moirai (Android + iOS, Material 3). Simula miles de versiones del futuro de una persona a partir de pocos datos y le dice qué palanca gana más años sanos por unidad de esfuerzo. Habla con el backend FastAPI (`apps/backend`, ver su `API.md`) y trae un **motor mock en Dart** (`lib/data/mock/mock_engine.dart`) para demo sin red.

## Correr

```bash
export PATH="$HOME/.local/share/flutter/bin:$PATH" ANDROID_HOME="$HOME/Android/Sdk"
cd apps/mobile
flutter pub get
flutter run                      # dispositivo/emulador conectado
flutter analyze --no-pub
flutter test                     # invariantes de la spec §9 sobre el motor mock
flutter build apk --release      # el APK para deploy-url
```

Configuración en compilación (opcional, defaults en `lib/core/env.dart`):

```bash
flutter run --dart-define=API_BASE_URL=https://platanus-bog-26.onrender.com   # default
flutter run --dart-define=USE_MOCK_ENGINE=true                                 # demo sin backend
```

## Qué es real y qué es local hoy

| Pieza | Estado |
| --- | --- |
| Registro / login / logout / cambiar contraseña / borrar cuenta | Real (`/auth/*`, token en keychain) |
| `GET/PATCH /me` (nombre, nacimiento, sexo, estatura, peso, sangre) | Real |
| Hábitos, historia familiar, objetivos, ancestría | Real (`PATCH /me/health-context`, sync best-effort tras cada cambio) + copia local |
| Biomarcadores | Real (`PATCH /me/health-context.biomarcadores`, `POST …/biomarkers/extract` con Claude) + copia local |
| Edad biológica y Monte Carlo | Real (`/phenoage` + `/montecarlo`); la curva por año, las trayectorias finas, el "por qué" (SHAP) y el percentil poblacional se aproximan en el dispositivo |
| Chat "Pregúntame" | Real (`/chat`, claude-haiku-4-5) |
| Wearables | Lectura real de Health Connect / HealthKit; resumen de hábitos en local → sube a `habitos` |
| Nacionalidad, alcohol, suplementos, foto, prueba genética, historial de simulaciones, "mi plan" | Local (`SharedPreferences`) hasta que el backend los acepte |

## Estructura

```
lib/
  main.dart            TokenStore.load + ProviderScope
  app/                 theme (tokens + MoiraiTheme), providers.dart, router.dart
  core/                env.dart (dart-defines), format.dart (es-CO)
  data/
    api/               ApiClient (Bearer token, 401 → cerrar sesión), TokenStore (secure storage)
    models/            Me/Profile, OnboardingData, Biomarcador, SimulacionInput/Resultado (spec §3/§8), Chat
    repositories/      auth, profile (+health-context), exams, simulation (phenoage+montecarlo → spec §8), chat, wearables, demo_data
    mock/              mock_engine.dart
  features/            auth, onboarding, exams, simulation, future, levers, backing, profile, chat, shell
  widgets/             mo.dart (MoScreen, MoCard, MoChoice…), mascot.dart, big_number.dart, fan_chart.dart, lever_card.dart
```

Flujo: Bienvenida → registro → onboarding (13 pasos) → exámenes (foto / archivo / manual / después) → confirmar lectura → **simulando en vivo** → Tu futuro · Simular (palancas) · Respaldo · Perfil, con "Pregúntame" (chat) desde Futuro y Perfil.
