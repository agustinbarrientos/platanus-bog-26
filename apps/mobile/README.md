# Moirai — app Flutter

La app móvil de Moirai (Android + iOS, Material 3). Simula miles de versiones del futuro de una persona a partir de pocos datos y le dice qué palanca gana más años sanos por unidad de esfuerzo. El motor de verdad vive en `apps/backend`; esta app trae un **motor mock en Dart** (`lib/data/mock/mock_engine.dart`, las 3 capas de `MOIRAI_ENGINE_SPEC.md` en chiquito) para ser demostrable sin backend.

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

Configuración en compilación (todas opcionales, defaults en `lib/core/env.dart`):

```bash
flutter run \
  --dart-define=API_BASE_URL=https://platanus-bog-26.onrender.com \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=USE_MOCK_ENGINE=false   # pega a /simular, /examenes/extraer, /wearables/sincronizar reales
```

## Qué es real y qué es mock hoy

| Pieza | Estado |
| --- | --- |
| Registro / login | Real, Supabase Auth (`AUTH.md`) |
| `GET/PATCH/DELETE /me` (nombre, nacimiento, sexo, estatura, peso, sangre) | Real |
| Resto del onboarding (objetivos, familia, hábitos, suplementos, wearable, foto, genética) | Local (`SharedPreferences`) hasta que `/me` los acepte — ver `API_CONTRACT.md` §1 |
| Lectura de exámenes (`/examenes/extraer`) | Mock: devuelve el examen demo tras 2 s |
| Simulación (`/simular`) | Mock en el dispositivo (N=400, mismas fórmulas de la spec) |
| Wearables | Lectura real de Health Connect / HealthKit; el resumen de hábitos se calcula en local |
| Historial y "mi plan" | Local |

## Estructura

```
lib/
  main.dart            Supabase.initialize + ProviderScope
  app/                 theme (tokens + MoiraiTheme), providers.dart, router.dart
  core/                env.dart (dart-defines), format.dart (es-CO)
  data/
    api/               ApiClient (JWT de Supabase en cada request)
    models/            Me/Profile (backend real), OnboardingData, Biomarcador, SimulacionInput/Resultado (spec §3/§8)
    repositories/      auth, profile, exams, simulation, wearables, demo_data
    mock/              mock_engine.dart
  features/            auth, onboarding, exams, simulation, future, levers, backing, profile, shell
  widgets/             mo.dart (MoScreen, MoCard, MoChoice…), mascot.dart, big_number.dart, fan_chart.dart, lever_card.dart
```

Flujo: Bienvenida → registro → onboarding (13 pasos) → exámenes (foto / archivo / manual / después) → confirmar lectura → **simulando en vivo** → Tu futuro · Simular (palancas) · Respaldo · Perfil.
