/// Configuración en tiempo de compilación (`--dart-define`).
abstract final class Env {
  /// Backend FastAPI (ver `apps/backend/API.md`).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://platanus-bog-26.onrender.com',
  );

  /// `true` → simulación, lectura de exámenes y chat corren con mocks locales
  /// (demo sin red). `false` (default) → pega al backend real.
  static const useMockEngine = bool.fromEnvironment(
    'USE_MOCK_ENGINE',
    defaultValue: false,
  );
}
