import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/biomarcador.dart';
import '../models/me.dart';
import '../models/onboarding.dart';

/// Perfil: lo que el backend ya guarda (`/me`) + lo que todavía no
/// (onboarding extendido y biomarcadores, en local, con clave por usuario).
class ProfileRepository {
  ProfileRepository(this._api, this._prefs);
  final ApiClient _api;
  final SharedPreferences _prefs;

  // ── /me (real) ────────────────────────────────────────────────────────
  Future<Me> getMe() async => Me.fromJson((await _api.get('/me') as Map).cast<String, dynamic>());

  /// Manda solo los campos presentes (el backend hace `exclude_unset`).
  Future<Me> patchMe(Map<String, dynamic> fields) async =>
      Me.fromJson((await _api.patch('/me', body: fields) as Map).cast<String, dynamic>());

  Future<void> deleteMe() => _api.delete('/me');

  // ── Onboarding extendido (local hasta que exista PUT /me/perfil) ──────
  String _k(String userId, String what) => 'moirai.$userId.$what';

  OnboardingData loadOnboarding(String userId) {
    final raw = _prefs.getString(_k(userId, 'onboarding'));
    if (raw == null) return const OnboardingData();
    try {
      return OnboardingData.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const OnboardingData();
    }
  }

  Future<void> saveOnboarding(String userId, OnboardingData data) =>
      _prefs.setString(_k(userId, 'onboarding'), jsonEncode(data.toJson()));

  // ── Biomarcadores confirmados (local hasta PUT /me/biomarcadores) ─────
  List<Biomarcador> loadBiomarcadores(String userId) {
    final raw = _prefs.getString(_k(userId, 'biomarcadores'));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveBiomarcadores(String userId, List<Biomarcador> list) =>
      _prefs.setString(_k(userId, 'biomarcadores'), jsonEncode(list.map((b) => b.toJson()).toList()));

  Future<void> clearLocal(String userId) async {
    await _prefs.remove(_k(userId, 'onboarding'));
    await _prefs.remove(_k(userId, 'biomarcadores'));
    await _prefs.remove(_k(userId, 'simulaciones'));
  }
}
