import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/env.dart';
import '../api/api_client.dart';
import '../mock/mock_engine.dart';
import '../models/biomarcador.dart';
import '../models/simulacion.dart';

/// Simulación contra el backend real:
/// `POST /me/health-context/phenoage` (edad biológica hoy) +
/// `POST /me/health-context/montecarlo` (P10/mediana/P90 por escenario, al
/// horizonte y **año por año** en el objeto `curva`).
///
/// La curva del abanico viene del motor. Lo que sigue siendo local: las
/// trayectorias individuales que dibuja la pantalla (el backend no expone
/// trayectorias, solo percentiles) y el SHAP aproximado — ambas marcadas como
/// ilustrativas en la UI. Con `USE_MOCK_ENGINE` corre el motor mock en el
/// dispositivo.
class SimulationRepository {
  SimulationRepository(this._api, this._prefs);
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const horizonte = 10;
  static const nTrayectorias = 5000;

  /// Escenarios del backend (`SCENARIOS` en interventions.py). El orden manda
  /// el del catálogo; el de las palancas en pantalla lo decide el ratio
  /// impacto/esfuerzo, no este mapa.
  static const escenariosBackend = <String, ({String etiqueta, int esfuerzo, String icono, String descripcion, List<String> partes})>{
    'sueno_8h': (etiqueta: 'Dormir 8 horas', esfuerzo: 2, icono: 'bedtime', descripcion: 'Acostarte a una hora fija y llegar a 8 horas casi todas las noches.', partes: ['sueno_8h']),
    'ejercicio_aerobico': (etiqueta: 'Ejercicio aeróbico regular', esfuerzo: 3, icono: 'directions_walk', descripcion: '150 minutos a la semana de algo que te suba el pulso: caminar rápido, bici, nadar.', partes: ['ejercicio_aerobico']),
    'dieta_mediterranea': (etiqueta: 'Dieta mediterránea', esfuerzo: 3, icono: 'restaurant', descripcion: 'Más verduras, legumbres, pescado y aceite de oliva; menos ultraprocesados. Un patrón, no una dieta.', partes: ['dieta_mediterranea']),
    'reducir_estres': (etiqueta: 'Bajar el estrés', esfuerzo: 2, icono: 'self_improvement', descripcion: 'Un hábito diario que lo baje de verdad: pausas, respiración, terapia.', partes: ['reducir_estres']),
    'cesacion_tabaco': (etiqueta: 'Dejar el tabaco', esfuerzo: 4, icono: 'smoke_free', descripcion: 'Cero cigarrillos. Es la palanca que más mueve la inflamación y los leucocitos.', partes: ['cesacion_tabaco']),
    'combinada': (etiqueta: 'Ejercicio + dieta mediterránea + dejar el tabaco', esfuerzo: 10, icono: 'auto_awesome', descripcion: 'Las tres a la vez.', partes: ['ejercicio_aerobico', 'dieta_mediterranea', 'cesacion_tabaco']),
  };

  Stream<SimulacionProgreso> simular(SimulacionInput input) {
    if (Env.useMockEngine) return MockEngine(n: 400).simular(input);
    return _simularRemoto(input);
  }

  Stream<SimulacionProgreso> _simularRemoto(SimulacionInput input) async* {
    final edad0 = input.edad.toDouble();
    final fuma = input.habitos['tabaco'] == true;
    // Solo se piden las palancas que esta persona puede accionar. El motor
    // aplica un efecto fijo por escenario, así que ofrecer "dormir 8 horas" a
    // quien ya duerme 8 le prometería años que no tiene cómo ganar.
    final duermePoco = ((input.habitos['sueno_h'] as num?)?.toDouble() ?? 7) < 8;
    // `startsWith('baj')` a propósito: el modelo del onboarding guarda
    // baja/media/alta (Catalogos.nivelBMA) pero API_CONTRACT.md documenta
    // bajo/medio/alto, así que la palanca no depende de cuál gane.
    final estresado = !'${input.habitos['estres'] ?? 'media'}'.startsWith('baj');
    final pedir = [
      'ninguna',
      if (duermePoco) 'sueno_8h',
      'ejercicio_aerobico',
      'dieta_mediterranea',
      if (estresado) 'reducir_estres',
      if (fuma) 'cesacion_tabaco',
      if (fuma) 'combinada',
    ];

    // 1) PhenoAge hoy.
    final ph = ((await _api.post('/me/health-context/phenoage', timeout: const Duration(seconds: 120))) as Map).cast<String, dynamic>();
    final hoy = (ph['edad_biologica'] as num).toDouble();
    final valores = ((ph['valores_usados'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toDouble()));
    final inferidos = ((ph['campos_inferidos'] as List?) ?? const []).map((e) => '$e').toList();

    // Mientras corre Monte Carlo en el servidor, emitimos trayectorias
    // sintéticas "en vivo" (deriva genérica) para que la pantalla respire.
    final rng = math.Random(42);
    final sint = <List<double>>[];
    final mcFuture = _api.post(
      '/me/health-context/montecarlo',
      body: {'escenarios': pedir, 'n_trayectorias': nTrayectorias, 'anios': horizonte},
      timeout: const Duration(seconds: 180),
    );
    var done = false;
    late Map<String, dynamic> mc;
    unawaited(mcFuture.then((v) {
      mc = (v as Map).cast<String, dynamic>();
      done = true;
    }).catchError((Object e) {
      done = true;
      mc = {'__error': e};
    }));
    var tick = 0;
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      tick++;
      if (sint.length < 60) sint.add(_trayectoriaSintetica(rng, hoy, 0.55, 0.9));
      final frac = (1 - math.exp(-tick / 40)).clamp(0.02, 0.92);
      yield SimulacionProgreso(
        fraccion: frac,
        vidas: (frac * nTrayectorias * pedir.length).round(),
        totalVidas: nTrayectorias * pedir.length,
        trayectoriasParciales: List.of(sint),
      );
    }
    if (mc['__error'] != null) {
      final e = mc['__error'];
      throw e is ApiException ? e : ApiException(500, 'La simulación no terminó. Intenta de nuevo.');
    }

    // 2) Armar el resultado en la forma de la spec §8.
    final escs = ((mc['escenarios'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    Map<String, dynamic>? find(String k) => escs.where((e) => '${e['escenario']}' == k).firstOrNull;
    final base = find('ninguna');
    if (base == null) throw ApiException(500, 'El servidor no devolvió la línea base.');
    final baseline = _curvaDe(hoy, base);
    final baseSd = _sd(base);

    final escenarios = <Escenario>[];
    for (final e in escs) {
      final k = '${e['escenario']}';
      if (k == 'ninguna') continue;
      final meta = escenariosBackend[k];
      final curva = _curvaDe(hoy, e);
      final delta = _m(base) - _m(e);
      final sdGain = math.sqrt(baseSd * baseSd + _sd(e) * _sd(e)) * 0.5; // pareadas → menos varianza
      final pct = (_phi(delta / math.max(sdGain, 0.05)) * 100).round().clamp(0, 100);
      final esfuerzo = meta?.esfuerzo ?? 3;
      escenarios.add(Escenario(
        intervenciones: meta?.partes ?? [k],
        etiqueta: meta?.etiqueta ?? '${e['nombre'] ?? k}',
        aniosGanados: MockEngine.r1(delta),
        rango: [MockEngine.r1(delta - 1.28 * sdGain), MockEngine.r1(delta + 1.28 * sdGain)],
        esfuerzo: esfuerzo,
        ratio: (delta / esfuerzo * 100).round() / 100,
        pctMejoran: pct,
        curva: curva,
      ));
    }
    escenarios.sort((a, b) => b.ratio.compareTo(a.ratio));
    final mejor = escenarios.isNotEmpty
        ? escenarios.first
        : Escenario(intervenciones: const [], etiqueta: 'Seguir como vas', aniosGanados: 0, rango: const [0, 0], esfuerzo: 0, ratio: 0, pctMejoran: 0, curva: baseline);

    // Trayectorias ilustrativas coherentes con la banda final del baseline.
    final muestra = List.generate(60, (i) => _trayectoriaSintetica(math.Random(1000 + i), hoy, (baseline.mediana.last - hoy) / horizonte, (baseline.p90.last - baseline.p10.last) / 2.56));

    // "SHAP" aproximado sobre el estado basal (el backend aún no lo expone).
    final estado = <String, double>{for (final d in BiomarcadorDef.phenoAgeDefs) d.id: valores[d.id] ?? BiomarcadorDef.medianas[d.id]!};
    final shap = MockEngine.shapAprox(estado, edad0, input.habitos);
    final percentil = MockEngine.percentil(hoy - edad0);

    final usados = [
      for (final d in BiomarcadorDef.phenoAgeDefs)
        Biomarcador(nombre: d.id, valor: valores[d.id] ?? BiomarcadorDef.medianas[d.id]!, unidad: d.unidad, fuente: inferidos.contains(d.id) ? 'inferido' : 'documento'),
    ];

    final catalogo = [
      for (final e in escenariosBackend.entries)
        if (e.key != 'combinada') Intervencion(id: e.key, etiqueta: e.value.etiqueta, esfuerzo: e.value.esfuerzo, icono: e.value.icono, descripcion: e.value.descripcion),
    ];

    final resultado = SimulacionResultado(
      id: 'sim_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      creadoEn: DateTime.now(),
      edadCronologica: input.edad,
      edadBiologicaHoy: MockEngine.r1(hoy),
      baseline: baseline,
      mejorDecision: mejor,
      veredicto: _veredicto(mejor),
      porque: MockEngine.porque(mejor, shap.isNotEmpty ? shap.first : null),
      shap: shap,
      percentilPoblacional: percentil,
      mensajePoblacional: percentil > 55
          ? 'Tu edad biológica está por encima del promedio de tu grupo de edad y sexo.'
          : percentil < 45
              ? 'Tu edad biológica está por debajo del promedio de tu grupo de edad y sexo.'
              : 'Tu edad biológica está cerca del promedio de tu grupo de edad y sexo.',
      incertidumbre: inferidos.isEmpty
          ? 'Usé tus 9 biomarcadores; la banda de proyección es la más angosta que puedo darte.'
          : '${inferidos.length} de 9 biomarcadores fueron imputados con medianas poblacionales por edad y sexo; la banda de proyección es más ancha en consecuencia.',
      descargo: 'Estimación de riesgo poblacional, no diagnóstico. Consulta a un profesional para decisiones clínicas.',
      escenarios: escenarios,
      muestraTrayectorias: muestra,
      catalogo: catalogo,
      biomarcadoresUsados: usados,
    );
    yield SimulacionProgreso(fraccion: 1, vidas: nTrayectorias * pedir.length, totalVidas: nTrayectorias * pedir.length, trayectoriasParciales: muestra, resultado: resultado);
  }

  static double _m(Map<String, dynamic> e) => (e['edad_biologica_mediana'] as num).toDouble();
  static double _sd(Map<String, dynamic> e) => (((e['edad_biologica_p90'] as num) - (e['edad_biologica_p10'] as num)) / 2.56).toDouble();
  static double _phi(double z) => 0.5 * (1 + MockEngine.erf(z / math.sqrt2));

  /// La curva año por año tal como la calculó el motor (Capa 3): el objeto
  /// `curva` que `/montecarlo` trae dentro de cada escenario, con los
  /// percentiles reales de las 5.000 trayectorias en cada año.
  ///
  /// El fallback sintético queda solo por si este APK termina hablando con un
  /// backend anterior a ese cambio; contra el backend actual nunca corre.
  static Curva _curvaDe(double hoy, Map<String, dynamic> e) {
    final c = e['curva'];
    if (c is Map) return Curva.fromJson(c.cast<String, dynamic>());
    return _curvaAproximada(hoy, e);
  }

  /// FALLBACK. Aproximación que la app usaba cuando `/montecarlo` solo devolvía
  /// percentiles al horizonte: mediana lineal, banda ∝ √t. El ancho de banda
  /// se acerca bastante al real, pero la mediana sale recta y la del motor
  /// tiene curvatura — por eso dejó de ser el camino principal.
  static Curva _curvaAproximada(double hoy, Map<String, dynamic> e) {
    final med = _m(e), p10 = (e['edad_biologica_p10'] as num).toDouble(), p90 = (e['edad_biologica_p90'] as num).toDouble();
    final anios = List.generate(horizonte + 1, (i) => i);
    final m = <double>[], lo = <double>[], hi = <double>[];
    for (final t in anios) {
      final f = t / horizonte;
      final mt = hoy + (med - hoy) * f;
      final w = math.sqrt(f);
      m.add(mt);
      lo.add(mt - (med - p10) * w);
      hi.add(mt + (p90 - med) * w);
    }
    return Curva(anios: anios, mediana: m, p10: lo, p90: hi);
  }

  static List<double> _trayectoriaSintetica(math.Random r, double hoy, double derivaAnual, double sdFinal) {
    final out = <double>[hoy];
    var v = hoy;
    final sdPaso = sdFinal / math.sqrt(horizonte);
    for (var t = 1; t <= horizonte; t++) {
      final u1 = math.max(r.nextDouble(), 1e-12), u2 = r.nextDouble();
      v += derivaAnual + math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2) * sdPaso;
      out.add(v);
    }
    return out;
  }

  static String _veredicto(Escenario e) {
    if (e.intervenciones.isEmpty) return 'Tu gemelo seguiría como vas: no encontré una palanca que mueva tu futuro lo suficiente.';
    return 'Tu gemelo empezaría por ${e.etiqueta.toLowerCase()} antes que por cualquier otra cosa.';
  }

  // ── Historial (local) ─────────────────────────────────────────────────
  String _k(String userId) => 'moirai.$userId.simulaciones';

  List<SimulacionResultado> historial(String userId) {
    final raw = _prefs.getString(_k(userId));
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => SimulacionResultado.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> guardar(String userId, SimulacionResultado r) async {
    final list = [r, ...historial(userId).where((e) => e.id != r.id)].take(10).toList();
    await _prefs.setString(_k(userId), jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> guardarPlan(String simulacionId, List<String> intervenciones, String adherencia) async {
    await _prefs.setString('moirai.plan.$simulacionId', jsonEncode({'intervenciones': intervenciones, 'adherencia': adherencia}));
  }

  Map<String, dynamic>? plan(String simulacionId) {
    final raw = _prefs.getString('moirai.plan.$simulacionId');
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }
}
