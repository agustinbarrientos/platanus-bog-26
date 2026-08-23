import 'dart:math' as math;

import '../models/biomarcador.dart';
import '../models/simulacion.dart';

/// Motor **mock** en Dart: un port reducido de las tres capas de
/// `MOIRAI_ENGINE_SPEC.md` (PhenoAge → deriva anual → Monte Carlo → barrido).
///
/// Existe para que la app sea demostrable sin backend y para que la pantalla
/// "Simulando en vivo" tenga trayectorias reales que dibujar. El motor de
/// verdad vive en `apps/backend` (`POST /simular`); este replica su forma de
/// salida, no su rigor (N más chico, sin SHAP real, sin NHANES).
class MockEngine {
  MockEngine({this.n = 400, this.anios = 10, int? seed}) : _seed = seed ?? 7;

  final int n;
  final int anios;
  final int _seed;

  // ── Capa 1 — PhenoAge (Levine et al. 2018) ─────────────────────────────
  // Unidades del paper: albúmina g/L, creatinina µmol/L, glucosa mmol/L,
  // CRP en ln(mg/dL), linfocitos %, VCM fL, RDW %, fosfatasa alcalina U/L,
  // leucocitos 10³/µL, edad en años.
  static double phenoAge(Map<String, double> bm, double edad) {
    final alb = bm['albumina']! * 10; // g/dL → g/L
    final creat = bm['creatinina']! * 88.4; // mg/dL → µmol/L
    final gluc = bm['glucosa']! / 18.0; // mg/dL → mmol/L
    final crp = math.log(math.max(bm['hs_CRP']!, 0.01) / 10.0); // mg/L → mg/dL → ln
    final xb = -19.907 -
        0.0336 * alb +
        0.0095 * creat +
        0.1953 * gluc +
        0.0954 * crp -
        0.0120 * bm['linfocitos_pct']! +
        0.0268 * bm['vcm']! +
        0.3306 * bm['rdw']! +
        0.00188 * bm['fosfatasa_alcalina']! +
        0.0554 * bm['leucocitos']! +
        0.0804 * edad;
    const g = 0.0076927;
    final mortality = 1 - math.exp(-math.exp(xb) * (math.exp(120 * g) - 1) / g);
    final m = mortality.clamp(1e-9, 1 - 1e-9);
    return 141.50225 + math.log(-0.00553 * math.log(1 - m)) / 0.090165;
  }

  // ── Capa 2 — deriva anual (valores ilustrativos de la spec §5) ─────────
  static const derivaBase = <String, double>{
    'hs_CRP': 0.02,
    'glucosa': 0.3,
    'albumina': -0.01,
    'creatinina': 0.005,
    'rdw': 0.02,
    'leucocitos': 0.0,
    'linfocitos_pct': -0.05,
    'vcm': 0.05,
    'fosfatasa_alcalina': 0.2,
  };

  static const efectoIntervencion = <String, Map<String, double>>{
    'sueno_8h': {'hs_CRP': -0.05, 'glucosa': -0.2},
    'ejercicio_moderado': {'hs_CRP': -0.08, 'glucosa': -0.5, 'albumina': 0.005},
    'dejar_alcohol': {'hs_CRP': -0.03, 'creatinina': -0.002},
    'dieta_mejor': {'glucosa': -0.4, 'hs_CRP': -0.04},
    'reducir_estres': {'hs_CRP': -0.04},
  };

  static const catalogo = <Intervencion>[
    Intervencion(id: 'sueno_8h', etiqueta: 'Dormir 8 horas', esfuerzo: 2, icono: 'bedtime', descripcion: 'Acostarte a una hora fija y llegar a 8 horas casi todas las noches.'),
    Intervencion(id: 'ejercicio_moderado', etiqueta: 'Ejercicio moderado', esfuerzo: 3, icono: 'directions_walk', descripcion: '150 minutos a la semana de algo que te suba el pulso.'),
    Intervencion(id: 'dejar_alcohol', etiqueta: 'Dejar el alcohol', esfuerzo: 2, icono: 'no_drinks', descripcion: 'Cero o casi cero. Las copas del fin de semana también cuentan.'),
    Intervencion(id: 'dieta_mejor', etiqueta: 'Comer mejor', esfuerzo: 3, icono: 'restaurant', descripcion: 'Más fibra y menos ultraprocesados; no una dieta, un patrón.'),
    Intervencion(id: 'reducir_estres', etiqueta: 'Bajar el estrés', esfuerzo: 2, icono: 'self_improvement', descripcion: 'Un hábito diario que lo baje de verdad: pausas, respiración, terapia.'),
  ];

  static const _bmUsadas = ['albumina', 'creatinina', 'glucosa', 'hs_CRP', 'rdw', 'leucocitos', 'linfocitos_pct', 'vcm', 'fosfatasa_alcalina'];

  /// Completa los 9 biomarcadores con medianas y marca los imputados.
  static (Map<String, double>, List<Biomarcador>, List<String>) preparar(List<Biomarcador> entrada) {
    final estado = <String, double>{};
    final usados = <Biomarcador>[];
    final faltantes = <String>[];
    for (final id in _bmUsadas) {
      final b = entrada.where((e) => e.nombre == id).firstOrNull;
      if (b != null) {
        estado[id] = b.valor;
        usados.add(b);
      } else {
        final med = BiomarcadorDef.medianas[id]!;
        estado[id] = med;
        faltantes.add(id);
        usados.add(Biomarcador(nombre: id, valor: med, unidad: BiomarcadorDef.byId(id)!.unidad, fuente: 'inferido'));
      }
    }
    return (estado, usados, faltantes);
  }

  /// Qué intervenciones aplican según los hábitos actuales (no tiene sentido
  /// "dejar el alcohol" si nunca bebes).
  static List<String> aplicables(Map<String, dynamic> habitos) {
    final out = <String>[];
    final sueno = (habitos['sueno_h'] as num?)?.toDouble() ?? 7;
    if (sueno < 7.5) out.add('sueno_8h');
    final ej = '${habitos['ejercicio'] ?? 'bajo'}';
    if (ej == 'nulo' || ej == 'bajo') out.add('ejercicio_moderado');
    final alc = '${habitos['alcohol'] ?? 'ocasional'}';
    if (alc != 'nunca') out.add('dejar_alcohol');
    final ali = '${habitos['alimentacion'] ?? 'media'}';
    if (ali != 'alta') out.add('dieta_mejor');
    final est = '${habitos['estres'] ?? 'media'}';
    if (est != 'baja') out.add('reducir_estres');
    return out;
  }

  Map<String, double> _paso(Map<String, double> estado, List<String> interv, math.Random rng, Map<String, double> sigma) {
    final nuevo = <String, double>{};
    for (final e in estado.entries) {
      var cambio = derivaBase[e.key] ?? 0;
      for (final i in interv) {
        cambio += efectoIntervencion[i]?[e.key] ?? 0;
      }
      final ruido = _gauss(rng) * (sigma[e.key] ?? 0.05);
      var v = e.value + cambio + ruido;
      final def = BiomarcadorDef.byId(e.key);
      if (def != null) v = v.clamp(def.min, def.max);
      nuevo[e.key] = v;
    }
    return nuevo;
  }

  static double _gauss(math.Random r) {
    final u1 = math.max(r.nextDouble(), 1e-12), u2 = r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Corre N trayectorias y devuelve (matriz N×(anios+1) de edad biológica).
  /// `onProgress` se llama cada `cada` vidas para animar la UI.
  List<List<double>> montecarlo(
    Map<String, double> estado0,
    List<String> interv,
    double edad0, {
    required Map<String, double> sigma,
    required int seed,
  }) {
    final todas = <List<double>>[];
    for (var k = 0; k < n; k++) {
      // Misma semilla por vida k entre escenarios → contrafactuales pareados.
      final rng = math.Random(seed * 100003 + k);
      var estado = Map<String, double>.from(estado0);
      final fila = List<double>.filled(anios + 1, 0);
      for (var a = 0; a <= anios; a++) {
        fila[a] = phenoAge(estado, edad0 + a);
        if (a < anios) estado = _paso(estado, interv, rng, sigma);
      }
      todas.add(fila);
    }
    return todas;
  }

  static Curva percentiles(List<List<double>> m, int anios) {
    final med = <double>[], p10 = <double>[], p90 = <double>[];
    for (var a = 0; a <= anios; a++) {
      final col = m.map((f) => f[a]).toList()..sort();
      med.add(_q(col, .5));
      p10.add(_q(col, .1));
      p90.add(_q(col, .9));
    }
    return Curva(anios: List.generate(anios + 1, (i) => i), mediana: med, p10: p10, p90: p90);
  }

  static double _q(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final i = (p * (sorted.length - 1));
    final lo = i.floor(), hi = i.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
  }

  static String etiquetaCombo(List<String> ids) {
    final parts = ids.map((id) => catalogo.firstWhere((c) => c.id == id).etiqueta.toLowerCase()).toList();
    if (parts.isEmpty) return 'Seguir igual';
    final first = parts.first[0].toUpperCase() + parts.first.substring(1);
    if (parts.length == 1) return first;
    return '$first + ${parts.sublist(1).join(' + ')}';
  }

  /// Simulación completa. Emite progreso (vidas corridas, trayectorias del
  /// baseline listas para dibujar) y al final el resultado.
  Stream<SimulacionProgreso> simular(SimulacionInput input) async* {
    final (estado0, usados, faltantes) = preparar(input.biomarcadores);
    final edad0 = input.edad.toDouble();
    final sigma = <String, double>{
      for (final id in _bmUsadas)
        id: (derivaBase[id] ?? 0.1).abs() * 2 * (faltantes.contains(id) ? 1.8 : 1.0) + 0.01,
    };
    final interv = aplicables(input.habitos);

    // Combos de 1 a 3 (spec §12: nunca más de 3).
    final combos = <List<String>>[];
    for (var k = 1; k <= 3; k++) {
      combos.addAll(_combinaciones(interv, k));
    }
    final totalVidas = n * (combos.length + 1);
    var vidas = 0;

    // Baseline, en bloques para emitir progreso con trayectorias parciales.
    final baseM = <List<double>>[];
    const bloque = 40;
    for (var start = 0; start < n; start += bloque) {
      final parcial = MockEngine(n: math.min(bloque, n - start), anios: anios)
          ._correrDesde(estado0, const [], edad0, sigma, _seed, start);
      baseM.addAll(parcial);
      vidas += parcial.length;
      yield SimulacionProgreso(
        fraccion: vidas / totalVidas,
        vidas: vidas,
        totalVidas: totalVidas,
        trayectoriasParciales: baseM.length > 60 ? baseM.sublist(0, 60) : List.of(baseM),
      );
      await Future<void>.delayed(Duration.zero);
    }
    final baseline = percentiles(baseM, anios);
    final baseFinal = baseM.map((f) => f.last).toList();

    final escenarios = <Escenario>[];
    for (final combo in combos) {
      final m = montecarlo(estado0, combo, edad0, sigma: sigma, seed: _seed);
      vidas += n;
      final curva = percentiles(m, anios);
      final deltas = List<double>.generate(n, (k) => baseFinal[k] - m[k].last)..sort();
      final ganados = _q(deltas, .5);
      final esfuerzo = combo.fold<int>(0, (s, id) => s + catalogo.firstWhere((c) => c.id == id).esfuerzo);
      final mejoran = deltas.where((d) => d > 0).length * 100 ~/ n;
      escenarios.add(Escenario(
        intervenciones: combo,
        etiqueta: etiquetaCombo(combo),
        aniosGanados: r1(ganados),
        rango: [r1(_q(deltas, .1)), r1(_q(deltas, .9))],
        esfuerzo: esfuerzo,
        ratio: esfuerzo == 0 ? 0 : (ganados / esfuerzo * 100).round() / 100,
        pctMejoran: mejoran,
        curva: curva,
      ));
      yield SimulacionProgreso(
        fraccion: vidas / totalVidas,
        vidas: vidas,
        totalVidas: totalVidas,
        trayectoriasParciales: baseM.sublist(0, math.min(60, baseM.length)),
      );
      await Future<void>.delayed(Duration.zero);
    }
    escenarios.sort((a, b) => b.ratio.compareTo(a.ratio));

    final hoy = phenoAge(estado0, edad0);
    final mejor = escenarios.isNotEmpty
        ? escenarios.first
        : Escenario(intervenciones: const [], etiqueta: 'Seguir como vas', aniosGanados: 0, rango: const [0, 0], esfuerzo: 0, ratio: 0, pctMejoran: 0, curva: baseline);

    final shap = shapAprox(estado0, edad0, input.habitos);
    final top = shap.isNotEmpty ? shap.first : null;
    final pctPob = percentil(hoy - edad0);

    final resultado = SimulacionResultado(
      id: 'sim_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      creadoEn: DateTime.now(),
      edadCronologica: input.edad,
      edadBiologicaHoy: r1(hoy),
      baseline: baseline,
      mejorDecision: mejor,
      veredicto: veredicto(mejor),
      porque: porque(mejor, top),
      shap: shap,
      percentilPoblacional: pctPob,
      mensajePoblacional: pctPob > 55
          ? 'Tu edad biológica está por encima del promedio de tu grupo de edad y sexo.'
          : pctPob < 45
              ? 'Tu edad biológica está por debajo del promedio de tu grupo de edad y sexo.'
              : 'Tu edad biológica está cerca del promedio de tu grupo de edad y sexo.',
      incertidumbre: faltantes.isEmpty
          ? 'Usé tus 9 biomarcadores; la banda de proyección es la más angosta que puedo darte.'
          : '${faltantes.length} de 9 biomarcadores fueron imputados con medianas poblacionales; la banda de proyección es más ancha en consecuencia.',
      descargo: 'Estimación de riesgo poblacional, no diagnóstico. Consulta a un profesional para decisiones clínicas.',
      escenarios: escenarios,
      muestraTrayectorias: baseM.sublist(0, math.min(60, baseM.length)),
      catalogo: catalogo,
      biomarcadoresUsados: usados,
    );
    yield SimulacionProgreso(fraccion: 1, vidas: totalVidas, totalVidas: totalVidas, trayectoriasParciales: resultado.muestraTrayectorias, resultado: resultado);
  }

  List<List<double>> _correrDesde(Map<String, double> estado0, List<String> interv, double edad0, Map<String, double> sigma, int seed, int offset) {
    final out = <List<double>>[];
    for (var k = 0; k < n; k++) {
      final rng = math.Random(seed * 100003 + offset + k);
      var estado = Map<String, double>.from(estado0);
      final fila = List<double>.filled(anios + 1, 0);
      for (var a = 0; a <= anios; a++) {
        fila[a] = phenoAge(estado, edad0 + a);
        if (a < anios) estado = _paso(estado, interv, rng, sigma);
      }
      out.add(fila);
    }
    return out;
  }

  static Iterable<List<String>> _combinaciones(List<String> items, int k) sync* {
    if (k == 0) {
      yield const [];
      return;
    }
    for (var i = 0; i <= items.length - k; i++) {
      for (final rest in _combinaciones(items.sublist(i + 1), k - 1)) {
        yield [items[i], ...rest];
      }
    }
  }

  /// "SHAP" aproximado: contribución de cada variable = diferencia de PhenoAge
  /// al reemplazar esa variable por su mediana. Basta para decir "tu palanca
  /// dominante es la inflamación". El backend lo hace con shap real.
  static List<ShapDriver> shapAprox(Map<String, double> estado, double edad, Map<String, dynamic> habitos) {
    final base = phenoAge(estado, edad);
    final out = <ShapDriver>[];
    for (final e in estado.entries) {
      final alt = Map<String, double>.from(estado)..[e.key] = BiomarcadorDef.medianas[e.key]!;
      final c = base - phenoAge(alt, edad);
      if (c.abs() >= 0.15) out.add(ShapDriver(variable: e.key, contribucion: r1(c), direccion: c > 0 ? 'empeora' : 'mejora'));
    }
    // Hábitos: contribución ilustrativa por nivel.
    final sueno = (habitos['sueno_h'] as num?)?.toDouble() ?? 7;
    if (sueno < 7) out.add(ShapDriver(variable: 'sueno_h', contribucion: r1((7 - sueno) * 0.6), direccion: 'empeora'));
    if ('${habitos['estres']}' == 'alta') out.add(const ShapDriver(variable: 'estres', contribucion: 0.9, direccion: 'empeora'));
    if ('${habitos['ejercicio']}' == 'moderado' || '${habitos['ejercicio']}' == 'alto') {
      out.add(const ShapDriver(variable: 'ejercicio', contribucion: -1.1, direccion: 'mejora'));
    }
    if (habitos['tabaco'] == true) out.add(const ShapDriver(variable: 'tabaco', contribucion: 1.6, direccion: 'empeora'));
    out.sort((a, b) => b.contribucion.abs().compareTo(a.contribucion.abs()));
    return out.take(5).toList();
  }

  static int percentil(double delta) {
    // Delta edad biológica − cronológica ~ N(0, 6) en población general.
    final z = delta / 6.0;
    final p = 0.5 * (1 + erf(z / math.sqrt2));
    return (p * 100).round().clamp(1, 99);
  }

  static double erf(double x) {
    final t = 1 / (1 + 0.3275911 * x.abs());
    final y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x);
    return x >= 0 ? y : -y;
  }

  static String veredicto(Escenario e) {
    if (e.intervenciones.isEmpty) return 'Tu gemelo seguiría como vas: no encontré una palanca que mueva tu futuro lo suficiente.';
    final partes = e.intervenciones.map((id) => catalogo.firstWhere((c) => c.id == id).etiqueta.toLowerCase()).toList();
    final texto = partes.length == 1 ? partes.first : '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
    return 'Tu gemelo empezaría por $texto antes que por cualquier otra cosa.';
  }

  static const _nombreVar = <String, String>{
    'hs_CRP': 'la inflamación (hs-CRP)',
    'glucosa': 'la glucosa',
    'albumina': 'la albúmina',
    'creatinina': 'la creatinina',
    'rdw': 'el RDW',
    'leucocitos': 'los leucocitos',
    'linfocitos_pct': 'los linfocitos',
    'vcm': 'el VCM',
    'fosfatasa_alcalina': 'la fosfatasa alcalina',
    'sueno_h': 'el sueño',
    'sueno': 'el sueño',
    'estres': 'el estrés',
    'ejercicio': 'el ejercicio',
    'actividad': 'la actividad física',
    'alimentacion': 'la alimentación',
    'alcohol': 'el alcohol',
    'tabaco': 'el tabaco',
  };

  static String nombreVariable(String v) => _nombreVar[v] ?? v;

  static String porque(Escenario e, ShapDriver? top) {
    if (e.intervenciones.isEmpty) return 'Tus biomarcadores ya están cerca de donde las intervenciones dejan de mover la aguja.';
    final eje = top == null ? 'tu perfil' : nombreVariable(top.variable);
    return 'Es la combinación con más años ganados por unidad de esfuerzo. Actúa sobre $eje, que hoy es tu eje dominante de riesgo.';
  }

  static double r1(double v) => (v * 10).round() / 10;
}
