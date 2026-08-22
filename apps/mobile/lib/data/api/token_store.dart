import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sesión del backend (`/auth/login` · `/auth/signup`). El token se muestra
/// una sola vez y es de larga vida (sin refresh), así que va al keychain /
/// EncryptedSharedPreferences. Cache en memoria para lectura síncrona.
class TokenStore extends ChangeNotifier {
  TokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'moirai.token';
  static const _kUserId = 'moirai.user_id';
  static const _kEmail = 'moirai.email';
  static const _kExpires = 'moirai.expires_at';

  String? _token;
  String? _userId;
  String? _email;
  DateTime? _expiresAt;

  String? get token => _token;
  String? get userId => _userId;
  String? get email => _email;
  DateTime? get expiresAt => _expiresAt;

  bool get hasSession => _token != null && (_expiresAt == null || _expiresAt!.isAfter(DateTime.now()));

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _kToken);
      _userId = await _storage.read(key: _kUserId);
      _email = await _storage.read(key: _kEmail);
      final e = await _storage.read(key: _kExpires);
      _expiresAt = e == null ? null : DateTime.tryParse(e);
    } catch (_) {
      _token = null;
    }
    notifyListeners();
  }

  Future<void> save({required String token, required String userId, required String email, DateTime? expiresAt}) async {
    _token = token;
    _userId = userId;
    _email = email;
    _expiresAt = expiresAt;
    try {
      await _storage.write(key: _kToken, value: token);
      await _storage.write(key: _kUserId, value: userId);
      await _storage.write(key: _kEmail, value: email);
      await _storage.write(key: _kExpires, value: expiresAt?.toIso8601String());
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clear() async {
    _token = null;
    _userId = null;
    _email = null;
    _expiresAt = null;
    try {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kUserId);
      await _storage.delete(key: _kEmail);
      await _storage.delete(key: _kExpires);
    } catch (_) {}
    notifyListeners();
  }
}
