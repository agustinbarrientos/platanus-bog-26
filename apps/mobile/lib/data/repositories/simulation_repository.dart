import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/env.dart';
import '../api/api_client.dart';
import '../mock/mock_engine.dart';
import '../models/simulacion.dart';

/// Simulación: `POST /simular` (+ polling a `GET /simulaciones/{id}`) o el
/// motor mock en el dispositivo. Historial local mientras no exista
/// `GET /me/simulaciones`.
class SimulationRepository {
  SimulationRepository(this._api, this._prefs);
  final ApiClient _api;
  final SharedPreferences _prefs;

  Stream<SimulacionProgreso> simular(SimulacionInput input) {
    if (Env.useMockEngine) return MockEngine(n: 400).simular(input);
    return _simularRemoto(input);
  }

  Stream<SimulacionProgreso> _simularRemoto(SimulacionInput input) async* {
    final first = await _api.post('/simular', body: input.toJson());
    final j = (first as Map).cast<String, dynamic>();
    if (j['estado'] == 'en_proceso' && j['id'] != null) {
      final id = '${j['id']}';
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final s = ((await _api.get('/simulaciones/$id')) as Map).cast<String, dynamic>();
        final estado = '${s['estado']}';
        final prog = (s['progreso'] as num?)?.toDouble() ?? 0;
        if (estado == 'lista' && s['resultado'] != null) {
          final r = SimulacionResultado.fromJson((s['resultado'] as Map).cast<String, dynamic>());
          yield SimulacionProgreso(fraccion: 1, vidas: 5000, totalVidas: 5000, trayectoriasParciales: r.muestraTrayectorias, resultado: r);
          return;
        }
        if (estado == 'fallida') throw ApiException(500, 'La simulación no terminó. Intenta de nuevo.');
        yield SimulacionProgreso(fraccion: prog, vidas: (prog * 5000).round(), totalVidas: 5000);
      }
    }
    final r = SimulacionResultado.fromJson(j);
    yield SimulacionProgreso(fraccion: 1, vidas: 5000, totalVidas: 5000, trayectoriasParciales: r.muestraTrayectorias, resultado: r);
  }

  // ── Historial (local) ─────────────────────────────────────────────────
  String _k(String userId) => 'moirai.$userId.simulaciones';

  List<SimulacionResultado> historial(String userId) {
    final raw = _prefs.getString(_k(userId));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SimulacionResultado.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> guardar(String userId, SimulacionResultado r) async {
    final list = [r, ...historial(userId).where((e) => e.id != r.id)].take(10).toList();
    await _prefs.setString(_k(userId), jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> guardarPlan(String simulacionId, List<String> intervenciones, String adherencia) async {
    if (Env.useMockEngine) {
      await _prefs.setString('moirai.plan.$simulacionId', jsonEncode({'intervenciones': intervenciones, 'adherencia': adherencia}));
      return;
    }
    await _api.post('/simulaciones/$simulacionId/plan', body: {'intervenciones': intervenciones, 'adherencia': adherencia});
  }

  Map<String, dynamic>? plan(String simulacionId) {
    final raw = _prefs.getString('moirai.plan.$simulacionId');
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }
}
