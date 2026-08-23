import 'package:flutter_test/flutter_test.dart';
import 'package:moirai/data/models/reporte.dart';

/// `Reporte.fromJson`: la forma de `POST /me/health-context/reporte`
/// (ver `apps/backend/API.md` → "Health report") tal como la pinta la
/// pantalla "Tu reporte". Tolera campos nulos (escenario "si mejoras" ausente,
/// valor de información sin datos).
void main() {
  final json = <String, dynamic>{
    'meta': {
      'id': 'rep_7f3a9c21',
      'generado_en': '2026-08-22T20:11:03+00:00',
      'version_motor': '0.3.0',
      'semilla': 20260822,
      'trayectorias_por_escenario': 5000,
      'horizonte_anios': 10,
      'disclaimer': 'Documento orientativo, no diagnóstico.',
      'privacidad': 'Datos procesados de forma privada.',
      'fuentes': ['Levine 2018', 'NHANES'],
    },
    'persona': {'nombre': 'Ana Rueda', 'edad': 34, 'sexo': 'F', 'ancestria': 'mixta_latam'},
    'resumen': 'Tu edad biológica estimada es 28,9 años.',
    'foto_hoy': {
      'edad_cronologica': 34,
      'edad_biologica': 28.9,
      'rango_hoy': {'p10': 26.6, 'mediana': 28.9, 'p90': 31.3},
      'aceleracion': -5.1,
      'percentil_poblacional': 20.6,
      'n_medidos': 6,
      'n_inferidos': 3,
      'biomarcadores': [
        {'nombre': 'glucosa', 'etiqueta': 'Glucosa en ayunas', 'valor': 118, 'unidad': 'mg/dL', 'estado': 'borde', 'lado': 'alto', 'rango_referencia': '70–99 mg/dL', 'fuente_rango': 'ADA', 'fuente': 'documento', 'contribucion_anios': 0.9, 'nota': null},
        {'nombre': 'vcm', 'etiqueta': 'VCM', 'valor': 90.7, 'unidad': 'fL', 'estado': 'inferido', 'lado': null, 'rango_referencia': '80–100 fL', 'fuente_rango': null, 'fuente': 'inferido', 'contribucion_anios': 0.0, 'nota': null},
      ],
      'nota_poblacional': 'Rangos de poblaciones europeas y estadounidenses.',
      'lectura': 'Tu edad biológica estimada está por debajo de tu edad.',
    },
    'ejes': [
      {'id': 'metabolico', 'nombre': 'Metabólico', 'nivel': 'a_vigilar', 'nivel_texto': 'a vigilar', 'aporte_anios': 0.9, 'explicacion': 'Glucosa en el borde.',
       'biomarcadores': [{'nombre': 'glucosa', 'etiqueta': 'Glucosa en ayunas', 'valor': 118, 'medido': true, 'estado': 'borde'}, {'nombre': 'imc', 'etiqueta': 'IMC', 'valor': null, 'medido': false, 'estado': 'inferido'}]},
      {'id': 'cardio_metabolico', 'nombre': 'Cardio-metabólico', 'nivel': 'sin_datos', 'nivel_texto': 'sin datos', 'aporte_anios': 0.0, 'explicacion': 'Sin datos.', 'biomarcadores': []},
    ],
    'futuros': {
      'horizonte_anios': 10,
      'curva_base': {'anios': [0, 10], 'p10': [26.6, 33.7], 'mediana': [28.9, 40.0], 'p90': [31.3, 46.1]},
      'sigues_igual': {'titulo': 'Si sigues igual', 'escenario': 'ninguna', 'nombre': 'Línea base', 'al_horizonte': {'p10': 33.7, 'mediana': 40.0, 'p90': 46.1}, 'anios_ganados': null, 'rango_ganados': null, 'texto': 'En 10 años…'},
      'si_mejoras': null,
      'si_te_descuidas': {'titulo': 'Si te descuidas', 'escenario': null, 'nombre': 'Todo adverso', 'al_horizonte': {'p10': 36.6, 'mediana': 42.8, 'p90': 48.9}, 'anios_ganados': -2.8, 'rango_ganados': null, 'texto': 'No es una predicción.'},
      'ranking': [
        {'escenario': 'ejercicio_aerobico+sueno_8h', 'nombre': 'Ejercicio + dormir 8 horas', 'intervenciones': ['ejercicio_aerobico', 'sueno_8h'], 'anios_ganados': 1.9, 'anios_ganados_p10': 0.9, 'anios_ganados_p90': 3.0, 'pct_futuros_que_mejoran': 100, 'esfuerzo': 5, 'ratio_impacto_esfuerzo': 0.38, 'fuentes': ['Fedewa 2017', 'Irwin 2016']},
      ],
      'nota_incertidumbre': 'Estimación, no certeza.',
    },
    'recomendaciones': [
      {'id': 'ejercicio_aerobico', 'nombre': 'Ejercicio aeróbico regular', 'que_hacer': '150 minutos a la semana.', 'por_que': 'Baja la PCR.', 'anios_ganados': 1.6, 'rango_ganados': [0.6, 2.7], 'pct_futuros_que_mejoran': 98, 'esfuerzo': 3,
       'evidencia': [{'hallazgo': 'Menor PCR con entrenamiento.', 'fuente': 'Fedewa MV, et al. Br J Sports Med 2017'}], 'habito': 'actividad física', 'brecha': 1.0},
    ],
    'consulta': {
      'disclaimer': 'Orientación, no una conclusión.',
      'sugerencias': [{'eje': 'metabolico', 'nombre': 'Metabólico', 'nivel': 'a_vigilar', 'profesional': 'medicina interna o endocrinología', 'texto': 'Valdría la pena una consulta para que lo evalúe.'}],
      'lleva_esto': 'Lleva este reporte a tu consulta.',
    },
    'afinar': {
      'ancho_banda_hoy': 4.7,
      'faltantes': [{'nombre': 'vcm', 'etiqueta': 'VCM', 'reduccion_banda_anios': 0.8, 'fraccion': 0.664}, {'nombre': 'rdw', 'etiqueta': 'RDW', 'reduccion_banda_anios': null, 'fraccion': null}],
      'nota': 'Hoy 3 de 9 están imputados.',
    },
  };

  test('parsea todas las secciones', () {
    final r = Reporte.fromJson(json);
    expect(r.id, 'rep_7f3a9c21');
    expect(r.generadoEn.toUtc().year, 2026);
    expect(r.semilla, 20260822);
    expect(r.nombre, 'Ana Rueda');
    expect(r.edad, 34);
    expect(r.fuentes, hasLength(2));

    expect(r.fotoHoy.edadBiologica, 28.9);
    expect(r.fotoHoy.tieneBandaHoy, isTrue);
    expect(r.fotoHoy.biomarcadores.first.marcado, isTrue);
    expect(r.fotoHoy.biomarcadores.first.lado, 'alto');
    expect(r.fotoHoy.biomarcadores.last.inferido, isTrue);

    expect(r.ejes.first.marcado, isTrue);
    expect(r.ejes.first.biomarcadores, ['Glucosa en ayunas', 'IMC (inferido)']);
    expect(r.ejes.last.nivel, 'sin_datos');

    expect(r.futuros.siMejoras, isNull);
    expect(r.futuros.siTeDescuidas!.aniosGanados, -2.8);
    expect(r.futuros.sigueIgual.aniosGanados, isNull);
    expect(r.futuros.ranking.single.intervenciones, ['ejercicio_aerobico', 'sueno_8h']);
    expect(r.futuros.ranking.single.fuentes, hasLength(2));

    expect(r.recomendaciones.single.rangoGanados, [0.6, 2.7]);
    expect(r.recomendaciones.single.evidencia.single.fuente, contains('2017'));
    expect(r.recomendaciones.single.brecha, 1.0);

    expect(r.consulta.sugerencias.single.profesional, contains('endocrinología'));
    expect(r.afinar.faltantes.first.reduccionAnios, 0.8);
    expect(r.afinar.faltantes.last.reduccionAnios, isNull);
  });

  test('tolera un JSON mínimo', () {
    final r = Reporte.fromJson({
      'meta': {}, 'persona': {}, 'foto_hoy': {}, 'ejes': [], 'futuros': {'sigues_igual': {}}, 'recomendaciones': [], 'consulta': {}, 'afinar': {},
    });
    expect(r.nombre, isNull);
    expect(r.horizonte, 10);
    expect(r.fotoHoy.biomarcadores, isEmpty);
    expect(r.futuros.ranking, isEmpty);
    expect(r.fotoHoy.tieneBandaHoy, isFalse);
  });
}
