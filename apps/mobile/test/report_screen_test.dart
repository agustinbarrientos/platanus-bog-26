import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moirai/app/providers.dart';
import 'package:moirai/data/models/reporte.dart';
import 'package:moirai/features/report/report_screen.dart';

/// "Tu reporte" pinta las 6 secciones del JSON de `/reporte` sin overflow ni
/// excepciones, y muestra los botones de descarga cuando hay datos.
void main() {
  final json = <String, dynamic>{
    'meta': {'id': 'rep_1', 'generado_en': '2026-08-22T20:11:03+00:00', 'version_motor': '0.3.0', 'semilla': 20260822, 'trayectorias_por_escenario': 5000, 'horizonte_anios': 10,
             'disclaimer': 'Documento orientativo, no diagnóstico. Compártelo con tu médico.', 'privacidad': 'Datos procesados de forma privada.', 'fuentes': ['Levine 2018', 'NHANES']},
    'persona': {'nombre': 'Ana Rueda', 'edad': 34, 'sexo': 'F', 'ancestria': 'mixta_latam'},
    'resumen': 'Tu edad biológica estimada es 28,9 años (tienes 34); lo que más la mueve es ejercicio aeróbico regular: +1,6 años.',
    'foto_hoy': {
      'edad_cronologica': 34, 'edad_biologica': 28.9, 'rango_hoy': {'p10': 26.6, 'mediana': 28.9, 'p90': 31.3}, 'aceleracion': -5.1, 'percentil_poblacional': 20.6, 'n_medidos': 6, 'n_inferidos': 3,
      'biomarcadores': [
        {'nombre': 'glucosa', 'etiqueta': 'Glucosa en ayunas', 'valor': 118, 'unidad': 'mg/dL', 'estado': 'borde', 'lado': 'alto', 'rango_referencia': '70–99 mg/dL (en ayunas)', 'fuente_rango': 'ADA', 'fuente': 'documento', 'contribucion_anios': 0.9, 'nota': null},
        {'nombre': 'hs_CRP', 'etiqueta': 'Proteína C reactiva (hs-CRP)', 'valor': 12.0, 'unidad': 'mg/L', 'estado': 'fuera', 'lado': 'alto', 'rango_referencia': '< 3 mg/L', 'fuente_rango': 'AHA', 'fuente': 'documento', 'contribucion_anios': 1.4, 'nota': 'Por encima de 10 mg/L suele reflejar un proceso agudo reciente; vale la pena repetir la medición.'},
        {'nombre': 'albumina', 'etiqueta': 'Albúmina', 'valor': 4.4, 'unidad': 'g/dL', 'estado': 'en_rango', 'lado': null, 'rango_referencia': '3,5–5,0 g/dL', 'fuente_rango': 'lab', 'fuente': 'documento', 'contribucion_anios': -0.9, 'nota': null},
        {'nombre': 'vcm', 'etiqueta': 'Volumen corpuscular medio (VCM)', 'valor': 90.7, 'unidad': 'fL', 'estado': 'inferido', 'lado': null, 'rango_referencia': '80–100 fL', 'fuente_rango': null, 'fuente': 'inferido', 'contribucion_anios': 0.0, 'nota': null},
      ],
      'nota_poblacional': 'Rangos de referencia de poblaciones europeas y estadounidenses.',
      'lectura': 'Tu edad biológica estimada (28,9) está 5,1 años por debajo de tu edad (34).',
    },
    'ejes': [
      {'id': 'inflamacion', 'nombre': 'Inflamación', 'nivel': 'atencion', 'nivel_texto': 'atención', 'aporte_anios': 1.4, 'explicacion': 'La proteína C reactiva está fuera del rango de referencia; por eso marco este eje para que un profesional lo evalúe.',
       'biomarcadores': [{'nombre': 'hs_CRP', 'etiqueta': 'Proteína C reactiva (hs-CRP)', 'valor': 12.0, 'medido': true, 'estado': 'fuera'}, {'nombre': 'leucocitos', 'etiqueta': 'Leucocitos', 'valor': null, 'medido': false, 'estado': 'inferido'}]},
      {'id': 'metabolico', 'nombre': 'Metabólico', 'nivel': 'a_vigilar', 'nivel_texto': 'a vigilar', 'aporte_anios': 0.9, 'explicacion': 'Glucosa en ayunas está en el borde del rango de referencia.', 'biomarcadores': [{'nombre': 'glucosa', 'etiqueta': 'Glucosa en ayunas', 'valor': 118, 'medido': true, 'estado': 'borde'}]},
      {'id': 'renal_hepatico', 'nombre': 'Renal y hepático', 'nivel': 'optimo', 'nivel_texto': 'en rango', 'aporte_anios': -0.9, 'explicacion': 'Lo que mediste está dentro de los rangos de referencia.', 'biomarcadores': [{'nombre': 'albumina', 'etiqueta': 'Albúmina', 'valor': 4.4, 'medido': true, 'estado': 'en_rango'}]},
      {'id': 'hematologico', 'nombre': 'Hematológico', 'nivel': 'sin_datos', 'nivel_texto': 'sin datos', 'aporte_anios': 0.0, 'explicacion': 'No tengo ningún dato medido de este eje.', 'biomarcadores': []},
      {'id': 'cardio_metabolico', 'nombre': 'Cardio-metabólico', 'nivel': 'sin_datos', 'nivel_texto': 'sin datos', 'aporte_anios': 0.0, 'explicacion': 'No tengo ningún dato medido de este eje.', 'biomarcadores': []},
    ],
    'futuros': {
      'horizonte_anios': 10,
      'curva_base': {'anios': [0, 10], 'p10': [26.6, 33.7], 'mediana': [28.9, 40.0], 'p90': [31.3, 46.1]},
      'sigues_igual': {'titulo': 'Si sigues igual', 'escenario': 'ninguna', 'nombre': 'Línea base', 'al_horizonte': {'p10': 33.7, 'mediana': 40.0, 'p90': 46.1}, 'anios_ganados': null, 'rango_ganados': null, 'texto': 'En 10 años tu edad biológica estaría alrededor de 40,0.'},
      'si_mejoras': {'titulo': 'Si mejoras', 'escenario': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'al_horizonte': {'p10': 32.0, 'mediana': 38.3, 'p90': 44.7}, 'anios_ganados': 1.6, 'rango_ganados': [0.6, 2.7], 'texto': 'Con ejercicio aeróbico regular la mediana baja a 38,3.'},
      'si_te_descuidas': {'titulo': 'Si te descuidas', 'escenario': null, 'nombre': 'Todo adverso', 'al_horizonte': {'p10': 36.6, 'mediana': 42.8, 'p90': 48.9}, 'anios_ganados': -2.8, 'rango_ganados': null, 'texto': 'No es una predicción: es la misma simulación con otros hábitos.'},
      'ranking': [
        {'escenario': 'ejercicio_aerobico+sueno_8h', 'nombre': 'Ejercicio aeróbico regular + dormir 8 horas', 'intervenciones': ['ejercicio_aerobico', 'sueno_8h'], 'anios_ganados': 1.9, 'anios_ganados_p10': 0.9, 'anios_ganados_p90': 3.0, 'pct_futuros_que_mejoran': 100, 'esfuerzo': 5, 'ratio_impacto_esfuerzo': 0.38, 'fuentes': ['Fedewa 2017', 'Irwin 2016']},
        {'escenario': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'intervenciones': ['ejercicio_aerobico'], 'anios_ganados': 1.6, 'anios_ganados_p10': 0.6, 'anios_ganados_p90': 2.7, 'pct_futuros_que_mejoran': 98, 'esfuerzo': 3, 'ratio_impacto_esfuerzo': 0.53, 'fuentes': ['Fedewa 2017']},
      ],
      'nota_incertidumbre': 'Estimación, no certeza: el rango refleja lo que no sé de ti.',
    },
    'recomendaciones': [
      {'id': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'que_hacer': '150 minutos a la semana de algo que te suba el pulso.', 'por_que': 'En tu simulación, baja la inflamación y la glucosa en ayunas.', 'anios_ganados': 1.6, 'rango_ganados': [0.6, 2.7], 'pct_futuros_que_mejoran': 98, 'esfuerzo': 3,
       'evidencia': [{'hallazgo': 'El entrenamiento físico sostenido se asocia con menor proteína C reactiva.', 'fuente': 'Fedewa MV, et al. Br J Sports Med 2017;51:670–676'}], 'habito': 'actividad física', 'brecha': 1.0},
      {'id': 'dieta_mediterranea', 'nombre': 'Dieta mediterránea', 'que_hacer': 'Más verduras, legumbres, pescado y aceite de oliva.', 'por_que': 'Baja la PCR y la glucosa.', 'anios_ganados': 0.7, 'rango_ganados': [0.2, 1.1], 'pct_futuros_que_mejoran': 98, 'esfuerzo': 3,
       'evidencia': [{'hallazgo': 'PREDIMED redujo la PCR 0,5–0,7 mg/L.', 'fuente': 'Estruch R, et al. Ann Intern Med 2006'}], 'habito': 'alimentación', 'brecha': 0.5},
    ],
    'consulta': {
      'disclaimer': 'Esto es orientación para que un profesional lo evalúe, no una conclusión.',
      'sugerencias': [
        {'eje': 'inflamacion', 'nombre': 'Inflamación', 'nivel': 'atencion', 'profesional': 'medicina general o medicina interna', 'texto': 'Conviene que un médico general o internista lo evalúe e investigue la causa.'},
        {'eje': 'metabolico', 'nombre': 'Metabólico', 'nivel': 'a_vigilar', 'profesional': 'medicina interna o endocrinología', 'texto': 'Valdría la pena una consulta para que lo evalúe con más detalle.'},
      ],
      'lleva_esto': 'Lleva este reporte a tu consulta.',
    },
    'afinar': {'ancho_banda_hoy': 4.7, 'faltantes': [{'nombre': 'vcm', 'etiqueta': 'Volumen corpuscular medio (VCM)', 'reduccion_banda_anios': 0.8, 'fraccion': 0.664}], 'nota': 'Hoy 3 de los 9 biomarcadores del reloj están imputados.'},
  };

  setUpAll(() => initializeDateFormatting('es_CO'));

  testWidgets('pinta las seis secciones sin overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reporteProvider.overrideWith((ref) async => Reporte.fromJson(json)),
          ultimoResultadoProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: ReportScreen()),
      ),
    );
    // La mascota anima en bucle: pumpAndSettle no termina nunca; avanzamos a mano.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Lo que le llevarías a tu médico'), findsOneWidget);
    expect(find.text('1 · Tu foto de hoy'), findsOneWidget);
    expect(find.text('2 · Los ejes de tu sistema'), findsOneWidget);
    expect(find.text('3 · Tus futuros a 10 años'), findsOneWidget);
    expect(find.text('4 · Qué puedes hacer'), findsOneWidget);
    expect(find.text('5 · Con quién consultar'), findsOneWidget);
    expect(find.text('6 · Qué datos ayudarían a afinar'), findsOneWidget);
    // Recomendaciones y ranking (más recomendaciones que el top de "Tu futuro").
    expect(find.text('1. Ejercicio aeróbico regular'), findsOneWidget);
    expect(find.text('2. Dieta mediterránea'), findsOneWidget);
    expect(find.textContaining(RegExp('si combinas palancas', caseSensitive: false)), findsOneWidget);
    expect(find.text('ya a medio camino'), findsOneWidget);
    // Triage orientativo y estados de biomarcadores.
    expect(find.text('medicina interna o endocrinología'), findsOneWidget);
    expect(find.text('fuera del rango (alto)'), findsOneWidget);
    expect(find.text('en el borde (alto)'), findsOneWidget);
    // Botones de descarga.
    expect(find.text('Descargar PDF'), findsOneWidget);
    expect(find.text('Resumen de 1 página'), findsOneWidget);
  });

  testWidgets('muestra el error y el botón de reintentar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reporteProvider.overrideWith((ref) async => throw Exception('boom')),
          ultimoResultadoProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: ReportScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Descargar PDF'), findsNothing);
  });
}
