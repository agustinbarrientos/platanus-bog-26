import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth directa con Supabase (ver `AUTH.md`): Supabase guarda la contraseña y
/// emite el JWT; la API solo lo verifica. La confirmación por correo está
/// apagada, así que tras registrarse ya hay sesión.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;
  bool get signedIn => session != null;

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  Future<void> signUp({required String email, required String password, String? fullName}) async {
    try {
      await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: fullName == null || fullName.trim().isEmpty ? null : {'full_name': fullName.trim()},
      );
    } on AuthException catch (e) {
      throw AuthFailure(_traducir(e));
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AuthFailure(_traducir(e));
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  static String _traducir(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (m.contains('invalid login credentials')) return 'Correo o contraseña incorrectos.';
    if (m.contains('password should be at least')) return 'La contraseña necesita al menos 6 caracteres.';
    if (m.contains('unable to validate email') || m.contains('invalid email')) return 'Ese correo no se ve bien. ¿Lo revisas?';
    if (m.contains('rate limit')) return 'Demasiados intentos seguidos. Dame un minuto.';
    if (m.contains('network') || m.contains('socket')) return 'No pude conectarme. ¿Tienes internet?';
    return 'No pude completar eso. Intenta de nuevo.';
  }
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
