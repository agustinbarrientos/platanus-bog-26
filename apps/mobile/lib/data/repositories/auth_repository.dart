import 'dart:async';

import '../api/api_client.dart';
import '../api/token_store.dart';

/// Auth contra el backend (`/auth/*`, ver `apps/backend/API.md`): el backend
/// guarda la contraseña (argon2) y emite un token opaco de 90 días que se
/// muestra una sola vez. Lo guardamos en [TokenStore] (keychain).
class AuthRepository {
  AuthRepository(this._api, this._tokens);
  final ApiClient _api;
  final TokenStore _tokens;

  bool get signedIn => _tokens.hasSession;
  String? get userId => _tokens.userId;
  String? get email => _tokens.email;

  Future<void> signUp({required String email, required String password, String? fullName}) async {
    try {
      final j = (await _api.post('/auth/signup', body: {'email': email.trim(), 'password': password}, auth: false) as Map).cast<String, dynamic>();
      await _guardarSesion(j);
    } on ApiException catch (e) {
      throw AuthFailure(_traducir(e));
    }
    if (fullName != null && fullName.trim().isNotEmpty) {
      try {
        await _api.patch('/me', body: {'full_name': fullName.trim()});
      } catch (_) {}
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      final j = (await _api.post('/auth/login', body: {'email': email.trim(), 'password': password}, auth: false) as Map).cast<String, dynamic>();
      await _guardarSesion(j);
    } on ApiException catch (e) {
      throw AuthFailure(_traducir(e));
    }
  }

  /// ¿Sigue válido el token guardado? (`GET /auth/session`). Si el backend
  /// dice 401, limpia la sesión local. Errores de red no la tocan.
  Future<bool> validarSesion() async {
    if (!_tokens.hasSession) return false;
    try {
      await _api.get('/auth/session');
      return true;
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await _tokens.clear();
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Cerrar sesión nunca depende de la red: primero se borra la sesión local
  /// (el router redirige al instante) y la revocación en el backend queda en
  /// segundo plano, best-effort y con timeout corto. Importante: `_api.post`
  /// lee el token de forma síncrona al arrancar (antes de su primer `await`),
  /// así que hay que crear el Future ANTES de `clear()` para que lleve el
  /// `Authorization` correcto.
  Future<void> signOut() async {
    final revocar = _api.post('/auth/logout', timeout: const Duration(seconds: 8)).then((_) {}, onError: (_) {});
    await _tokens.clear();
    unawaited(revocar);
  }

  Future<void> changePassword({required String current, required String nueva}) async {
    try {
      final j = (await _api.post('/auth/password', body: {'current_password': current, 'new_password': nueva}) as Map).cast<String, dynamic>();
      await _guardarSesion(j);
    } on ApiException catch (e) {
      throw AuthFailure(_traducir(e));
    }
  }

  /// Borra la cuenta y todo lo asociado (perfil, contexto de salud, tokens).
  Future<void> deleteAccount({required String password}) async {
    try {
      await _api.post('/auth/delete-account', body: {'password': password});
    } on ApiException catch (e) {
      throw AuthFailure(_traducir(e));
    }
    await _tokens.clear();
  }

  Future<void> _guardarSesion(Map<String, dynamic> j) async {
    final user = (j['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    await _tokens.save(
      token: '${j['token']}',
      userId: '${user['id']}',
      email: '${user['email'] ?? ''}',
      expiresAt: DateTime.tryParse('${j['expires_at']}'),
    );
  }

  static String _traducir(ApiException e) {
    final m = e.message.toLowerCase();
    if (e.statusCode == 409 || m.contains('ya existe') || m.contains('already')) return 'Ya existe una cuenta con ese correo.';
    if (e.statusCode == 401) return 'Correo o contraseña incorrectos.';
    if (e.fields.containsKey('password') || m.contains('password') || m.contains('contraseña')) {
      return 'La contraseña necesita al menos 8 caracteres.';
    }
    if (e.fields.containsKey('email') || m.contains('email') || m.contains('correo')) return 'Ese correo no se ve bien. ¿Lo revisas?';
    if (e.statusCode == 429) return 'Demasiados intentos seguidos. Dame un minuto.';
    if (e.statusCode >= 500) return 'El servidor está despertando. Dame unos segundos y vuelve a intentar.';
    return e.message;
  }
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
