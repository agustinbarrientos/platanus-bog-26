import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/biomarcador.dart';
import '../models/me.dart';
import '../models/onboarding.dart';

/// Perfil: `/me` (6 campos básicos) + `/me/health-context` (biomarcadores,
/// hábitos, historia familiar, objetivos, demografía extra). Lo que el backend
/// aún no modela (nacionalidad, alcohol, suplementos, wearable, foto, genética)
/// vive en local con clave por usuario.
class ProfileRepository {
  ProfileRepository(this._api, this._prefs);
  final ApiClient _api;
  final SharedPreferences _prefs;

  // ── /me ───────────────────────────────────────────────────────────────
  Future<Me> getMe() async => Me.fromJson((await _api.get('/me') as Map).cast<String, dynamic>());

  /// Manda solo los campos presentes (el backend hace `exclude_unset`).
  Future<Me> patchMe(Map<String, dynamic> fields) async =>
      Me.fromJson((await _api.patch('/me', body: fields) as Map).cast<String, dynamic>());

  Future<void> deleteMe() => _api.delete('/me');

  // ── /me/health-context ───────────────────────────────────────────────
  Future<Map<String, dynamic>> getHealthContext() async =>
      ((await _api.get('/me/health-context')) as Map).cast<String, dynamic>();

  /// `demografia` y `habitos` se mezclan; las listas reemplazan completas.
  Future<Map<String, dynamic>> patchHealthContext(Map<String, dynamic> patch) async =>
      ((await _api.patch('/me/health-context', body: patch)) as Map).cast<String, dynamic>();

  /// Sube el onboarding extendido al backend (lo que cabe en health-context).
  /// Best-effort: si falla (Render dormido, sin red) queda el local y se
  /// reintenta en la próxima edición.
  Future<bool> syncOnboarding(OnboardingData d) async {
    try {
      await patchHealthContext(healthContextPatchFrom(d));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> healthContextPatchFrom(OnboardingData d) {
    final hab = <String, dynamic>{};
    if (d.suenoH != null) hab['sueno_h'] = d.suenoH;
    if (d.tabaco != null) hab['tabaco'] = d.tabaco;
    if (d.ejercicio != null) hab['actividad'] = _actividad(d.ejercicio!);
    if (d.alimentacion != null) hab['alimentacion'] = d.alimentacion;
    if (d.estres != null) hab['estres'] = _estres(d.estres!);
    final patch = <String, dynamic>{
      if (d.ancestria != null) 'demografia': {'ancestria_reportada': d.ancestria},
      if (hab.isNotEmpty) 'habitos': hab,
      'historia_familiar': d.historialFamiliar
          .where((e) => e.condicion != 'ninguna')
          .map((e) => e.parentesco == null ? e.condicion : '${e.condicion}:${e.parentesco}')
          .toList(),
      'objetivos_usuario': d.objetivos.toList(),
    };
    return patch;
  }

  /// ejercicio (nulo|bajo|moderado|alto) → actividad (baja|media|alta).
  static String _actividad(String e) => switch (e) { 'nulo' || 'bajo' => 'baja', 'moderado' => 'media', _ => 'alta' };

  /// estrés (baja|media|alta) → (bajo|medio|alto), como el ejemplo del backend.
  static String _estres(String e) => switch (e) { 'baja' => 'bajo', 'media' => 'medio', _ => 'alto' };

  /// Reemplaza la lista completa de biomarcadores en el backend. Filtra lo que
  /// el backend rechazaría (nombre fuera del vocabulario, unidad distinta,
  /// valor fuera de rango) para que un dato raro no tumbe todo el PATCH.
  Future<List<Biomarcador>> pushBiomarcadores(List<Biomarcador> list, {Profile? perfil}) async {
    final validos = <Biomarcador>[];
    for (final b in list) {
      final def = BiomarcadorDef.byId(b.nombre);
      if (def == null || b.inferido) continue;
      if (b.unidad != def.unidad) continue;
      if (b.valor < def.min || b.valor > def.max) continue;
      validos.add(b);
    }
    final imc = perfil?.imc;
    if (imc != null && !validos.any((b) => b.nombre == 'imc') && imc >= 10 && imc <= 80) {
      validos.add(Biomarcador(nombre: 'imc', valor: imc, unidad: 'kg/m2', fuente: 'calculado'));
    }
    final faltan = BiomarcadorDef.phenoAgeDefs.map((d) => d.id).where((id) => !validos.any((b) => b.nombre == id)).toList();
    final j = await patchHealthContext({
      'biomarcadores': validos.map((b) => b.toApiJson()).toList(),
      'datos_faltantes': faltan,
    });
    return ((j['biomarcadores'] as List?) ?? const [])
        .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Biomarcadores que el backend tiene hoy (p. ej. tras extraer un examen).
  Future<List<Biomarcador>> pullBiomarcadores() async {
    final j = await getHealthContext();
    return ((j['biomarcadores'] as List?) ?? const [])
        .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── Local (clave por usuario) ────────────────────────────────────────
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
