import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moirai/data/repositories/demo_data.dart';
import 'package:moirai/data/repositories/simulation_repository.dart';

/// `SimulationRepository.armarResultado`: cómo se traduce lo que devuelven
/// `/phenoage` + `/montecarlo` (forma nueva del backend, y la vieja) a la
/// forma de la spec §8 que consumen las pantallas.
void main() {
  final input = DemoData.perfil();

  Map<String, dynamic> curva(double hoy, double fin, double ancho) {
    final anios = List.generate(11, (i) => i);
    return {
      'anios': anios,
      'mediana': [for (final t in anios) hoy + (fin - hoy) * t / 10],
      'p10': [for (final t in anios) hoy + (fin - hoy) * t / 10 - ancho / 2 * t / 10],
      'p90': [for (final t in anios) hoy + (fin - hoy) * t / 10 + ancho / 2 * t / 10],
    };
  }

  final ph = {
    'edad_cronologica': 34,
    'edad_biologica': 28.89,
    'aceleracion': -5.11,
    'aceleracion_referencia': -0.75,
    'percentil_poblacional': 20.6,
    'campos_inferidos': ['fosfatasa_alcalina', 'linfocitos_pct', 'vcm'],
    'valores_usados': {'albumina': 4.4, 'creatinina': 0.8, 'glucosa': 92, 'hs_CRP': 2.1, 'rdw': 13.1, 'leucocitos': 6.2, 'fosfatasa_alcalina': 80, 'linfocitos_pct': 30, 'vcm': 90.7},
    'contribuciones': {'albumina': -0.9, 'creatinina': -1.1, 'glucosa': -0.3, 'hs_CRP': -0.1, 'rdw': -1.5, 'leucocitos': -0.5, 'fosfatasa_alcalina': 0.0, 'linfocitos_pct': 0.0, 'vcm': 0.0},
  };

  Map<String, dynamic> esc(String key, List<String> ids, double ganados, double lo, double hi, double pct, int esfuerzo, {bool aplica = true}) => {
    'escenario': key,
    'nombre': 'backend: $key',
    'intervenciones': ids,
    'descripcion': 'desc',
    'esfuerzo': esfuerzo,
    'aplica': aplica,
    'edad_biologica_p10': 33.7 - ganados,
    'edad_biologica_mediana': 40.0 - ganados,
    'edad_biologica_p90': 46.1 - ganados,
    'curva': curva(28.89, 40.0 - ganados, 12.4),
    'anios_ganados': ganados,
    'anios_ganados_p10': lo,
    'anios_ganados_p90': hi,
    'pct_futuros_que_mejoran': pct,
    'ratio_impacto_esfuerzo': esfuerzo == 0 ? 0 : ganados / esfuerzo,
  };

  final mcNuevo = {
    'edad_cronologica': 34,
    'horizonte_anios': 10,
    'trayectorias_por_escenario': 5000,
    'semilla': 20260822,
    'campos_inferidos': ['fosfatasa_alcalina', 'linfocitos_pct', 'vcm'],
    'ancho_banda_hoy': 4.73,
    'habitos_usados': {'sueno_h': 6, 'tabaco': false, 'actividad': 'baja', 'alimentacion': 'media', 'estres': 'alto'},
    'brechas': {'actividad': 1.0, 'alimentacion': 0.5, 'tabaco': 0.0, 'sueno': 1.0, 'estres': 1.0, 'alcohol': null},
    'palancas': [
      {'id': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'descripcion': '150 min', 'esfuerzo': 3, 'habito': 'actividad', 'brecha': 1.0, 'brecha_efectiva': 1.0, 'aplica': true, 'efectos_anuales': {'glucosa': -0.9}},
      {'id': 'dieta_mediterranea', 'nombre': 'Dieta mediterránea', 'descripcion': 'verduras', 'esfuerzo': 3, 'habito': 'alimentacion', 'brecha': 0.5, 'brecha_efectiva': 0.5, 'aplica': true, 'efectos_anuales': {'glucosa': -0.6}},
      {'id': 'cesacion_tabaco', 'nombre': 'Cesación de tabaco', 'descripcion': 'cero', 'esfuerzo': 4, 'habito': 'tabaco', 'brecha': 0.0, 'brecha_efectiva': 0.0, 'aplica': false, 'efectos_anuales': {'vcm': -0.15}},
      {'id': 'sueno_8h', 'nombre': 'Dormir 8 horas', 'descripcion': 'hora fija', 'esfuerzo': 2, 'habito': 'sueno', 'brecha': 1.0, 'brecha_efectiva': 1.0, 'aplica': true, 'efectos_anuales': {'glucosa': -0.2}},
      {'id': 'reducir_estres', 'nombre': 'Reducir el estrés', 'descripcion': 'pausas', 'esfuerzo': 2, 'habito': 'estres', 'brecha': 1.0, 'brecha_efectiva': 1.0, 'aplica': true, 'efectos_anuales': {'hs_CRP': -0.04}},
      {'id': 'reducir_alcohol', 'nombre': 'Bajar el alcohol', 'descripcion': 'ocasional', 'esfuerzo': 2, 'habito': 'alcohol', 'brecha': null, 'brecha_efectiva': 0.0, 'aplica': false, 'efectos_anuales': {'vcm': -0.2}},
    ],
    'escenarios': [
      esc('ninguna', [], 0, 0, 0, 0, 0),
      esc('dieta_mediterranea', ['dieta_mediterranea'], 0.66, 0.23, 1.12, 97.8, 3),
      esc('ejercicio_aerobico', ['ejercicio_aerobico'], 1.59, 0.56, 2.73, 97.7, 3),
      esc('ejercicio_aerobico+sueno_8h', ['ejercicio_aerobico', 'sueno_8h'], 1.85, 0.89, 3.04, 100, 5),
      esc('cesacion_tabaco', ['cesacion_tabaco'], 0, 0, 0, 0, 4, aplica: false),
    ],
    'muestra_trayectorias': List.generate(40, (i) => List.generate(11, (t) => 28.89 + t * 1.1 + (i % 5) * 0.3)),
    'valor_de_informacion': [
      {'nombre': 'vcm', 'reduccion_banda_anios': 0.74, 'fraccion': 0.8},
      {'nombre': 'linfocitos_pct', 'reduccion_banda_anios': 0.16, 'fraccion': 0.17},
      {'nombre': 'fosfatasa_alcalina', 'reduccion_banda_anios': 0.03, 'fraccion': 0.03},
    ],
    'contribuciones_habitos': [
      {'habito': 'actividad', 'palanca': 'ejercicio_aerobico', 'brecha': 1.0, 'contribucion': 1.11, 'direccion': 'empeora'},
      {'habito': 'tabaco', 'palanca': 'cesacion_tabaco', 'brecha': 0.0, 'contribucion': -1.48, 'direccion': 'mejora'},
      {'habito': 'estres', 'palanca': 'reducir_estres', 'brecha': 1.0, 'contribucion': 0.05, 'direccion': 'empeora'},
    ],
  };

  test('forma nueva: curvas, años ganados pareados, catálogo, VOI y "por qué" salen del motor', () {
    final r = SimulationRepository.armarResultado(input: input, ph: ph, mc: mcNuevo, ahora: DateTime(2026, 8, 22));
    expect(r.fuenteCurvas, 'motor');
    expect(r.curvasDelMotor, isTrue);
    expect(r.edadBiologicaHoy, 28.9);
    expect(r.anchoBandaHoy, 4.73);
    expect(r.baseline.mediana, hasLength(11));
    expect(r.baseline.mediana.last, closeTo(40.0, 1e-9));

    // Ordenadas por ratio; la que no aplica no entra.
    expect(r.escenarios.map((e) => e.intervenciones.join('+')), ['ejercicio_aerobico', 'ejercicio_aerobico+sueno_8h', 'dieta_mediterranea']);
    final ej = r.escenarios.first;
    expect(ej.etiqueta, 'Ejercicio aeróbico regular');
    expect(ej.aniosGanados, 1.6);
    expect(ej.rango, [0.6, 2.7]);
    expect(ej.pctMejoran, 98);
    expect(ej.esfuerzo, 3);
    expect(ej.ratio, closeTo(0.53, 0.01));
    expect(r.escenarios[1].etiqueta, 'Ejercicio aeróbico regular + dormir 8 horas');
    expect(r.escenarios[1].esfuerzo, 5);
    expect(r.mejorDecision, same(ej));
    expect(r.veredicto, contains('ejercicio aeróbico regular'));

    // Trayectorias reales del motor, no sintéticas.
    expect(r.muestraTrayectorias, hasLength(40));
    expect(r.muestraTrayectorias.first.first, 28.89);

    // Catálogo con las 6 palancas (para el detalle), etiquetas de la app.
    expect(r.catalogo.map((c) => c.id), containsAll(['ejercicio_aerobico', 'reducir_alcohol', 'sueno_8h']));
    expect(r.intervencion('cesacion_tabaco')!.etiqueta, 'Dejar el tabaco');
    expect(r.intervencion('sueno_8h')!.esfuerzo, 2);

    // "Por qué": biomarcadores (hoy) + hábitos (10 años), ordenados por |contribución|.
    expect(r.shap.first.variable, 'rdw');
    expect(r.shap.map((d) => d.variable), contains('tabaco'));
    expect(r.shap.map((d) => d.variable), contains('actividad'));
    expect(r.shap.map((d) => d.variable), isNot(contains('estres'))); // 0,05 < umbral
    expect(r.shap.firstWhere((d) => d.variable == 'tabaco').direccion, 'mejora');
    expect(r.shap.length, lessThanOrEqualTo(6));

    expect(r.percentilPoblacional, 21);
    expect(r.valorDeInformacion.first.nombre, 'vcm');
    expect(r.valorDeInformacion.first.reduccionAnios, 0.74);
    expect(r.incertidumbre, contains('3 de 9'));
    expect(r.incertidumbre, contains('4,7'));
    expect(r.biomarcadoresUsados.where((b) => b.inferido).map((b) => b.nombre), containsAll(['vcm', 'linfocitos_pct', 'fosfatasa_alcalina']));

    // Sobrevive al viaje por JSON (historial local y chat).
    final otra = jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>;
    expect(otra['fuente_curvas'], 'motor');
    expect((otra['valor_de_informacion'] as List).length, 3);
    expect(r.toChatJson().containsKey('muestra_trayectorias'), isFalse);
  });

  test('forma vieja (solo percentiles al horizonte): aproxima como antes y lo marca', () {
    final mcViejo = {
      'edad_cronologica': 34,
      'horizonte_anios': 10,
      'trayectorias_por_escenario': 5000,
      'campos_inferidos': ['fosfatasa_alcalina', 'linfocitos_pct', 'vcm'],
      'escenarios': [
        {'escenario': 'ninguna', 'nombre': 'Sin intervención (línea base)', 'edad_biologica_p10': 33.5, 'edad_biologica_mediana': 39.6, 'edad_biologica_p90': 45.5},
        {'escenario': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'edad_biologica_p10': 31.8, 'edad_biologica_mediana': 37.8, 'edad_biologica_p90': 43.8},
        {'escenario': 'combinada', 'nombre': 'Ejercicio + dieta mediterránea + cesación de tabaco', 'edad_biologica_p10': 30.0, 'edad_biologica_mediana': 36.0, 'edad_biologica_p90': 42.0},
      ],
    };
    final phViejo = Map<String, dynamic>.from(ph)..remove('contribuciones')..remove('percentil_poblacional')..remove('aceleracion_referencia');
    final r = SimulationRepository.armarResultado(input: input, ph: phViejo, mc: mcViejo, ahora: DateTime(2026, 8, 22));
    expect(r.fuenteCurvas, 'interpolada');
    expect(r.curvasDelMotor, isFalse);
    expect(r.baseline.mediana.first, closeTo(28.89, 1e-9));
    expect(r.baseline.mediana.last, closeTo(39.6, 1e-9));
    final ej = r.escenarios.firstWhere((e) => e.intervenciones.length == 1);
    expect(ej.aniosGanados, 1.8);
    expect(ej.rango[0], lessThan(ej.aniosGanados));
    expect(ej.rango[1], greaterThan(ej.aniosGanados));
    expect(ej.pctMejoran, inInclusiveRange(50, 100));
    expect(ej.esfuerzo, 3); // tabla local
    final combo = r.escenarios.firstWhere((e) => e.intervenciones.length == 3);
    expect(combo.intervenciones, ['ejercicio_aerobico', 'dieta_mediterranea', 'cesacion_tabaco']);
    expect(combo.esfuerzo, 10);
    expect(combo.etiqueta, 'Ejercicio aeróbico regular + dieta mediterránea + dejar el tabaco');
    expect(r.shap, isNotEmpty); // aproximación local
    expect(r.valorDeInformacion, isEmpty);
    expect(r.muestraTrayectorias, hasLength(60)); // sintéticas
    expect(r.catalogo.map((c) => c.id), containsAll(SimulationRepository.escenariosBackend.keys));
  });

  test('estimación local de escenarios sigue la regla de aplicabilidad del backend', () {
    // Demo: sueño 6 h, ejercicio bajo, alcohol moderado, alimentación media,
    // no fuma, estrés alto → 5 palancas → 1 + 5 + 10 + 10.
    expect(SimulationRepository.escenariosEstimados(input.habitos), 26);
    final buenos = {'sueno_h': 8, 'ejercicio': 'alto', 'alcohol': 'nunca', 'alimentacion': 'alta', 'tabaco': false, 'estres': 'baja'};
    expect(SimulationRepository.escenariosEstimados(buenos), 1);
    expect(SimulationRepository.brechasLocales(buenos).values.every((g) => g == 0), isTrue);
    final malos = {'sueno_h': 5, 'ejercicio': 'nulo', 'alcohol': 'alto', 'alimentacion': 'baja', 'tabaco': true, 'estres': 'alta'};
    expect(SimulationRepository.escenariosEstimados(malos), 1 + 6 + 15 + 20);
  });
}
