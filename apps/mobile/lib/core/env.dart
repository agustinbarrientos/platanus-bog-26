/// Configuración en tiempo de compilación.
///
/// Se pasa con `--dart-define` (o `--dart-define-from-file=env.json`).
/// Los defaults son los valores públicos de `AUTH.md`: la anon key de Supabase
/// está hecha para ir dentro del bundle y no es un secreto.
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://platanus-bog-26.onrender.com',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wplkytspqzwotmatnbxo.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndwbGt5dHNwcXp3b3RtYXRuYnhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczNzIxOTEsImV4cCI6MjEwMjk0ODE5MX0.UUiu8ysxWbnjJlKZp-w0GPJVTVFX0emvmtjZjChSP88',
  );

  /// Mientras el backend no tenga `/simular`, `/examenes/extraer`, etc., la app
  /// usa repositorios mock para esas rutas. `--dart-define=USE_MOCK_ENGINE=false`
  /// las apaga y pega al backend real (ver `API_CONTRACT.md`).
  static const useMockEngine = bool.fromEnvironment(
    'USE_MOCK_ENGINE',
    defaultValue: true,
  );
}
