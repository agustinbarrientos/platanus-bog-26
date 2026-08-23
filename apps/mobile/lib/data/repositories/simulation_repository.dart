import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/env.dart';
import '../../core/format.dart';
import '../api/api_client.dart';
import '../mock/mock_engine.dart';
import '../models/biomarcador.dart';
import '../models/simulacion.dart';

/// Simulación contra el backend real:
/// `POST /me/health-context/phenoage` (edad biológica hoy + "por qué" +
/// percentil) + `POST /me/health-context/montecarlo` (sin `escenarios`: el
/// backend decide qué palancas aplican según los hábitos guardados y corre
/// cada una y sus combinaciones de 2 y 3, pareadas). El motor devuelve curvas
/// por año, años ganados pareados con rango, trayectorias reales de muestra,
/// valor de información y contribuciones de hábitos; la app solo traduce a la
/// forma de la spec §8 (`armarResultado`). Si el backend es viejo y no trae
/// esos campos, cae a las aproximaciones de antes y lo marca
/// (`fuenteCurvas = 'interpolada'`).
/// Con `USE_MOCK_ENGINE` corre el motor mock en el dispositivo.
class SimulationRepository {
  SimulationRepository(this._api, this._prefs);
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const horizonte = 10;
  static const nTrayectorias = 5000;

  /// Cómo nombra la app cada palanca del backend (tono de la mascota). Una
  /// palanca que el backend agregue y no esté aquí usa el nombre que él manda.
  static const etiquetasPalanca = <String, String>{
    'ejercicio_aerobico': 'Ejercicio aeróbico regular',
    'dieta_mediterranea': 'Dieta mediterránea',
    'cesacion_tabaco': 'Dejar el tabaco',
    'sueno_8h': 'Dormir 8 horas',
    'reducir_estres': 'Bajar el estrés',
    'reducir_alcohol': 'Bajar el alcohol',
  };

  static const iconosPalanca = <String, String>{
    'ejercicio_aerobico': 'directions_walk',
    'dieta_mediterranea': 'restaurant',
    'cesacion_tabaco': 'smoke_free',
    'sueno_8h': 'bedtime',
    'reducir_estres': 'self_improvement',
    'reducir_alcohol': 'no_drinks',
  };

  /// Tabla local de respaldo (copia de `interventions.py`) por si el backend
  /// es viejo y no manda `palancas`. Con el backend actual no se usa: el
  /// catálogo llega en la respuesta de `/montecarlo` y en `GET /engine/catalogo`.
  static const escenariosBackend = <String, ({String etiqueta, int esfuerzo, String icono, String descripcion, String habito})>{
    'ejercicio_aerobico': (etiqueta: 'Ejercicio aeróbico regular', esfuerzo: 3, icono: 'directions_walk', descripcion: '150 minutos a la semana de algo que te suba el pulso: caminar rápido, bici, nadar.', habito: 'actividad'),
    'dieta_mediterranea': (etiqueta: 'Dieta mediterránea', esfuerzo: 3, icono: 'restaurant', descripcion: 'Más verduras, legumbres, pescado y aceite de oliva; menos ultraprocesados. Un patrón, no una dieta.', habito: 'alimentacion'),
    'cesacion_tabaco': (etiqueta: 'Dejar el tabaco', esfuerzo: 4, icono: 'smoke_free', descripcion: 'Cero cigarrillos. Es la palanca que más mueve la inflamación y los leucocitos.', habito: 'tabaco'),
    'sueno_8h': (etiqueta: 'Dormir 8 horas', esfuerzo: 2, icono: 'bedtime', descripcion: 'Acostarte a una hora fija y llegar a 7,5–8 horas casi todas las noches.', habito: 'sueno'),
    'reducir_estres': (etiqueta: 'Bajar el estrés', esfuerzo: 2, icono: 'self_improvement', descripcion: 'Un hábito diario que lo baje de verdad: pausas, respiración, terapia.', habito: 'estres'),
    'reducir_alcohol': (etiqueta: 'Bajar el alcohol', esfuerzo: 2, icono: 'no_drinks', descripcion: 'De casi diario a ocasional. Las copas del fin de semana también cuentan.', habito: 'alcohol'),
  };

  Stream<SimulacionProgreso> simular(SimulacionInput input) {
    if (Env.useMockEngine) return MockEngine(n: 400).simular(input);
    return _simularRemoto(input);
  }

  Stream<SimulacionProgreso> _simularRemoto(SimulacionInput input) async* {
    // Cuántos escenarios va a correr el backend (para el contador de vidas
    // mientras llega la respuesta): la misma regla de aplicabilidad que él usa.
    final estimados = escenariosEstimados(input.habitos);
    var totalVidas = nTrayectorias * estimados;

    // 1) PhenoAge hoy (+ contribuciones + percentil).
    final ph = ((await _api.post('/me/health-context/phenoage', timeout: const Duration(seconds: 120))) as Map).cast<String, dynamic>();
    final hoy = (ph['edad_biologica'] as num).toDouble();

    // Mientras corre Monte Carlo en el servidor, emitimos trayectorias
    // sintéticas "en vivo" (deriva genérica) para que la pantalla respire; al
    // final se reemplazan por las 40 reales que manda el motor.
    final rng = math.Random(42);
    final sint = <List<double>>[];
    final mcFuture = _api.post(
      '/me/health-context/montecarlo',
      body: {'n_trayectorias': nTrayectorias, 'anios': horizonte},
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
        vidas: (frac * totalVidas).round(),
        totalVidas: totalVidas,
        trayectoriasParciales: List.of(sint),
      );
    }
    if (mc['__error'] != null) {
      final e = mc['__error'];
      throw e is ApiException ? e : ApiException(500, 'La simulación no terminó. Intenta de nuevo.');
    }

    final resultado = armarResultado(input: input, ph: ph, mc: mc);
    final nEsc = ((mc['escenarios'] as List?) ?? const []).length;
    final nTr = (mc['trayectorias_por_escenario'] as num?)?.toInt() ?? nTrayectorias;
    if (nEsc > 0) totalVidas = nTr * nEsc;
    yield SimulacionProgreso(fraccion: 1, vidas: totalVidas, totalVidas: totalVidas, trayectoriasParciales: resultado.muestraTrayectorias, resultado: resultado);
  }

  // ── Armar el resultado de la spec §8 a partir de /phenoage + /montecarlo ─

  /// Traduce las dos respuestas del backend a [SimulacionResultado]. Pura y
  /// estática para poder testearla con fixtures (`test/remote_result_test.dart`).
  /// Tolera la forma vieja del backend (sin `curva`, `anios_ganados`,
  /// `palancas`, …): en ese caso aproxima como antes y lo marca.
  static SimulacionResultado armarResultado({
    required SimulacionInput input,
    required Map<String, dynamic> ph,
    required Map<String, dynamic> mc,
    DateTime? ahora,
  }) {
    final creado = ahora ?? DateTime.now();
    // La edad manda el backend (es la del perfil guardado); `input` solo aporta
    // hábitos/objetivos para las aproximaciones locales y el caso demo.
    final edadCronologica = (ph['edad_cronologica'] as num?)?.round() ?? input.edad;
    final edad0 = edadCronologica.toDouble();
    final hoy = (ph['edad_biologica'] as num).toDouble();
    final valores = ((ph['valores_usados'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toDouble()));
    final inferidos = ((ph['campos_inferidos'] as List?) ?? ((mc['campos_inferidos'] as List?) ?? const [])).map((e) => '$e').toList();

    final escs = ((mc['escenarios'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    Map<String, dynamic>? find(String k) => escs.where((e) => '${e['escenario']}' == k).firstOrNull;
    final base = find('ninguna');
    if (base == null) throw ApiException(500, 'El servidor no devolvió la línea base.');
    final delMotor = base['curva'] is Map;

    // Catálogo evaluado para esta persona (o la tabla local si el backend es viejo).
    final palancas = <String, Map<String, dynamic>>{
      for (final p in ((mc['palancas'] as List?) ?? const [])) '${(p as Map)['id']}': p.cast<String, dynamic>(),
    };
    int esfuerzoDe(String id) =>
        (palancas[id]?['esfuerzo'] as num?)?.toInt() ?? escenariosBackend[id]?.esfuerzo ?? 3;
    String descripcionDe(String id) => '${palancas[id]?['descripcion'] ?? escenariosBackend[id]?.descripcion ?? ''}';
    String etiquetaDe(String id) => etiquetasPalanca[id] ?? '${palancas[id]?['nombre'] ?? escenariosBackend[id]?.etiqueta ?? id.replaceAll('_', ' ')}';

    final baseline = delMotor ? Curva.fromJson((base['curva'] as Map).cast<String, dynamic>()) : _curva(hoy, base);
    final baseSd = _sd(base);

    final escenarios = <Escenario>[];
    for (final e in escs) {
      final k = '${e['escenario']}';
      if (k == 'ninguna' || e['aplica'] == false) continue;
      final ids = ((e['intervenciones'] as List?)?.map((x) => '$x').toList()) ?? _partesLegado(k);
      final curva = e['curva'] is Map ? Curva.fromJson((e['curva'] as Map).cast<String, dynamic>()) : _curva(hoy, e);
      final delta = (e['anios_ganados'] as num?)?.toDouble() ?? (_m(base) - _m(e));
      final double lo, hi;
      final int pct;
      if (e['anios_ganados_p10'] != null && e['anios_ganados_p90'] != null && e['pct_futuros_que_mejoran'] != null) {
        lo = (e['anios_ganados_p10'] as num).toDouble();
        hi = (e['anios_ganados_p90'] as num).toDouble();
        pct = (e['pct_futuros_que_mejoran'] as num).round().clamp(0, 100);
      } else {
        final sdGain = math.sqrt(baseSd * baseSd + _sd(e) * _sd(e)) * 0.5; // pareadas → menos varianza
        lo = delta - 1.28 * sdGain;
        hi = delta + 1.28 * sdGain;
        pct = (_phi(delta / math.max(sdGain, 0.05)) * 100).round().clamp(0, 100);
      }
      final esfuerzo = (e['esfuerzo'] as num?)?.toInt() ?? ids.fold<int>(0, (s, id) => s + esfuerzoDe(id));
      final ratio = (e['ratio_impacto_esfuerzo'] as num?)?.toDouble() ?? (esfuerzo > 0 ? delta / esfuerzo : 0.0);
      escenarios.add(Escenario(
        intervenciones: ids,
        etiqueta: etiquetaCombo(ids, etiquetaDe) ?? '${e['nombre'] ?? k}',
        aniosGanados: MockEngine.r1(delta),
        rango: [MockEngine.r1(lo), MockEngine.r1(hi)],
        esfuerzo: esfuerzo,
        ratio: (ratio * 100).round() / 100,
        pctMejoran: pct,
        curva: curva,
      ));
    }
    escenarios.sort((a, b) => b.ratio.compareTo(a.ratio));
    final mejor = escenarios.isNotEmpty
        ? escenarios.first
        : Escenario(intervenciones: const [], etiqueta: 'Seguir como vas', aniosGanados: 0, rango: const [0, 0], esfuerzo: 0, ratio: 0, pctMejoran: 0, curva: baseline);

    // Trayectorias: las reales del motor (40 de la línea base) o ilustrativas.
    final muestraMotor = ((mc['muestra_trayectorias'] as List?) ?? const [])
        .map((t) => (t as List).map((e) => (e as num).toDouble()).toList())
        .where((t) => t.isNotEmpty)
        .toList();
    final muestra = muestraMotor.isNotEmpty
        ? muestraMotor
        : List.generate(60, (i) => _trayectoriaSintetica(math.Random(1000 + i), hoy, (baseline.mediana.last - hoy) / horizonte, (baseline.p90.last - baseline.p10.last) / 2.56));

    // "Por qué": contribuciones del motor (biomarcadores hoy + hábitos a 10
    // años) o la aproximación local si el backend no las manda.
    final contrib = (ph['contribuciones'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toDouble()));
    final List<ShapDriver> shap;
    if (contrib != null) {
      final drivers = <ShapDriver>[
        for (final e in contrib.entries)
          if (e.value.abs() >= 0.15) ShapDriver(variable: e.key, contribucion: MockEngine.r1(e.value), direccion: e.value > 0 ? 'empeora' : 'mejora'),
        for (final h in ((mc['contribuciones_habitos'] as List?) ?? const []).map((x) => (x as Map).cast<String, dynamic>()))
          if (((h['contribucion'] as num?)?.abs() ?? 0) >= 0.1)
            ShapDriver(
              variable: '${h['habito']}',
              contribucion: MockEngine.r1((h['contribucion'] as num).toDouble()),
              direccion: '${h['direccion'] ?? (((h['contribucion'] as num) > 0) ? 'empeora' : 'mejora')}',
            ),
      ]..sort((a, b) => b.contribucion.abs().compareTo(a.contribucion.abs()));
      shap = drivers.take(6).toList();
    } else {
      final estado = <String, double>{for (final d in BiomarcadorDef.phenoAgeDefs) d.id: valores[d.id] ?? BiomarcadorDef.medianas[d.id]!};
      shap = MockEngine.shapAprox(estado, edad0, input.habitos);
    }
    final percentil = (ph['percentil_poblacional'] as num?)?.round().clamp(1, 99) ?? MockEngine.percentil(hoy - edad0);

    final usados = [
      for (final d in BiomarcadorDef.phenoAgeDefs)
        Biomarcador(nombre: d.id, valor: valores[d.id] ?? BiomarcadorDef.medianas[d.id]!, unidad: d.unidad, fuente: inferidos.contains(d.id) ? 'inferido' : 'documento'),
    ];

    final idsCatalogo = palancas.isNotEmpty ? palancas.keys.toList() : escenariosBackend.keys.toList();
    final catalogo = [
      for (final id in idsCatalogo)
        Intervencion(id: id, etiqueta: etiquetaDe(id), esfuerzo: esfuerzoDe(id), icono: iconosPalanca[id] ?? escenariosBackend[id]?.icono ?? 'spa', descripcion: descripcionDe(id)),
    ];

    final anchoHoy = (mc['ancho_banda_hoy'] as num?)?.toDouble() ?? 0;
    final voi = ((mc['valor_de_informacion'] as List?) ?? const [])
        .map((v) => ValorDeInformacion.fromJson((v as Map).cast<String, dynamic>()))
        .toList();

    final String incertidumbre;
    if (inferidos.isEmpty) {
      incertidumbre = 'Usé tus 9 biomarcadores; la banda de proyección es la más angosta que puedo darte.';
    } else if (anchoHoy > 0) {
      incertidumbre =
          '${inferidos.length} de 9 biomarcadores fueron imputados con medianas poblacionales por edad y sexo; por eso la banda arranca ancha ya hoy (${Fmt.decimal(anchoHoy)} años entre P10 y P90) y se ensancha en la proyección.';
    } else {
      incertidumbre = '${inferidos.length} de 9 biomarcadores fueron imputados con medianas poblacionales por edad y sexo; la banda de proyección es más ancha en consecuencia.';
    }

    return SimulacionResultado(
      id: 'sim_${creado.millisecondsSinceEpoch.toRadixString(36)}',
      creadoEn: creado,
      edadCronologica: edadCronologica,
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
      incertidumbre: incertidumbre,
      descargo: 'Estimación de riesgo poblacional, no diagnóstico. Consulta a un profesional para decisiones clínicas.',
      escenarios: escenarios,
      muestraTrayectorias: muestra,
      catalogo: catalogo,
      biomarcadoresUsados: usados,
      valorDeInformacion: voi,
      anchoBandaHoy: anchoHoy,
      fuenteCurvas: delMotor ? 'motor' : 'interpolada',
    );
  }

  /// Etiqueta de un escenario a partir de sus palancas: "Ejercicio aeróbico
  /// regular + dormir 8 horas". `null` si no hay palancas.
  static String? etiquetaCombo(List<String> ids, String Function(String id) etiquetaDe) {
    if (ids.isEmpty) return null;
    final partes = ids.map(etiquetaDe).toList();
    if (partes.length == 1) return partes.first;
    String minuscula(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
    return '${partes.first} + ${partes.sublist(1).map(minuscula).join(' + ')}';
  }

  /// Palancas de una clave de escenario cuando el backend no manda
  /// `intervenciones` (forma vieja): `a+b+c`, `combinada` o una sola.
  static List<String> _partesLegado(String k) {
    if (k == 'combinada') return const ['ejercicio_aerobico', 'dieta_mediterranea', 'cesacion_tabaco'];
    return k.split('+').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Brecha 0–1 por palanca según los hábitos de la app (misma regla que
  /// `interventions.brechas_desde_habitos` del backend, en el vocabulario
  /// interno de la app). Solo para estimar cuántos escenarios correrá el
  /// backend; el que decide es él.
  static Map<String, double> brechasLocales(Map<String, dynamic> habitos) {
    double nivel3(String? v, {required bool adversoAlto}) => switch (v) {
      'alta' || 'alto' => adversoAlto ? 1 : 0,
      'media' || 'medio' => 0.5,
      'baja' || 'bajo' => adversoAlto ? 0 : 1,
      _ => 1,
    };
    final ejercicio = '${habitos['ejercicio'] ?? habitos['actividad'] ?? ''}';
    final actividad = switch (ejercicio) { 'nulo' || 'bajo' || 'baja' => 1.0, 'moderado' || 'media' => 0.5, 'alto' || 'alta' => 0.0, _ => 1.0 };
    final sueno = (habitos['sueno_h'] as num?)?.toDouble();
    final alcohol = switch ('${habitos['alcohol'] ?? ''}') { 'alto' => 1.0, 'moderado' => 0.5, 'ocasional' || 'nunca' => 0.0, _ => 0.0 };
    return {
      'ejercicio_aerobico': actividad,
      'dieta_mediterranea': nivel3(habitos['alimentacion'] as String?, adversoAlto: false),
      'cesacion_tabaco': habitos['tabaco'] == true ? 1.0 : 0.0,
      'sueno_8h': sueno == null ? 1.0 : ((7.5 - sueno) / 1.5).clamp(0.0, 1.0),
      'reducir_estres': nivel3(habitos['estres'] as String?, adversoAlto: true),
      'reducir_alcohol': alcohol,
    };
  }

  /// Cuántos escenarios corre el backend por defecto: la base + las palancas
  /// que aplican + sus combinaciones de 2 y 3.
  static int escenariosEstimados(Map<String, dynamic> habitos) {
    final k = brechasLocales(habitos).values.where((g) => g > 0).length;
    int c(int n, int r) => r > n ? 0 : List.generate(r, (i) => (n - i) / (i + 1)).fold<double>(1, (a, b) => a * b).round();
    return 1 + k + c(k, 2) + c(k, 3);
  }

  static double _m(Map<String, dynamic> e) => (e['edad_biologica_mediana'] as num).toDouble();
  static double _sd(Map<String, dynamic> e) => (((e['edad_biologica_p90'] as num) - (e['edad_biologica_p10'] as num)) / 2.56).toDouble();
  static double _phi(double z) => 0.5 * (1 + MockEngine.erf(z / math.sqrt2));

  /// Curva de hoy al horizonte cuando el backend solo da percentiles al
  /// horizonte (forma vieja): mediana lineal, banda ∝ √t.
  static Curva _curva(double hoy, Map<String, dynamic> e) {
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
    return 'Tu gemelo empezaría por ${e.etiqueta[0].toLowerCase()}${e.etiqueta.substring(1)} antes que por cualquier otra cosa.';
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
