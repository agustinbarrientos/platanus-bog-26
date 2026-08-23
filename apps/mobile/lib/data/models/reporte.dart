/// El reporte de salud orientativo (`POST /me/health-context/reporte`, ver
/// `apps/backend/API.md` → "Health report"). Espejo de `ReporteOut`: lo
/// mismo que imprime el PDF, para mostrarlo en "Tu reporte" antes de
/// descargarlo. Todo viene del motor real; la app no calcula nada aquí.
class Reporte {
  const Reporte({
    required this.id,
    required this.generadoEn,
    required this.versionMotor,
    required this.semilla,
    required this.trayectorias,
    required this.horizonte,
    required this.disclaimer,
    required this.privacidad,
    required this.fuentes,
    required this.nombre,
    required this.edad,
    required this.resumen,
    required this.fotoHoy,
    required this.ejes,
    required this.futuros,
    required this.recomendaciones,
    required this.consulta,
    required this.afinar,
  });

  final String id;
  final DateTime generadoEn;
  final String versionMotor;
  final int semilla;
  final int trayectorias;
  final int horizonte;
  final String disclaimer;
  final String privacidad;
  final List<String> fuentes;
  final String? nombre;
  final int edad;
  final String resumen;
  final FotoHoy fotoHoy;
  final List<EjeReporte> ejes;
  final FuturosReporte futuros;
  final List<Recomendacion> recomendaciones;
  final ConsultaReporte consulta;
  final AfinarReporte afinar;

  factory Reporte.fromJson(Map<String, dynamic> j) {
    final meta = _m(j['meta']);
    final persona = _m(j['persona']);
    return Reporte(
      id: '${meta['id'] ?? ''}',
      generadoEn: DateTime.tryParse('${meta['generado_en'] ?? ''}') ?? DateTime.now(),
      versionMotor: '${meta['version_motor'] ?? ''}',
      semilla: _i(meta['semilla']),
      trayectorias: _i(meta['trayectorias_por_escenario']),
      horizonte: _i(meta['horizonte_anios'], 10),
      disclaimer: '${meta['disclaimer'] ?? ''}',
      privacidad: '${meta['privacidad'] ?? ''}',
      fuentes: _ls(meta['fuentes']),
      nombre: persona['nombre'] as String?,
      edad: _i(persona['edad']),
      resumen: '${j['resumen'] ?? ''}',
      fotoHoy: FotoHoy.fromJson(_m(j['foto_hoy'])),
      ejes: _l(j['ejes']).map(EjeReporte.fromJson).toList(),
      futuros: FuturosReporte.fromJson(_m(j['futuros'])),
      recomendaciones: _l(j['recomendaciones']).map(Recomendacion.fromJson).toList(),
      consulta: ConsultaReporte.fromJson(_m(j['consulta'])),
      afinar: AfinarReporte.fromJson(_m(j['afinar'])),
    );
  }
}

class FotoHoy {
  const FotoHoy({
    required this.edadCronologica,
    required this.edadBiologica,
    required this.rangoHoyP10,
    required this.rangoHoyP90,
    required this.aceleracion,
    required this.percentil,
    required this.nMedidos,
    required this.nInferidos,
    required this.biomarcadores,
    required this.notaPoblacional,
    required this.lectura,
  });

  final int edadCronologica;
  final double edadBiologica;
  final double rangoHoyP10;
  final double rangoHoyP90;
  final double aceleracion;
  final double percentil;
  final int nMedidos;
  final int nInferidos;
  final List<BiomarcadorReporte> biomarcadores;
  final String notaPoblacional;
  final String lectura;

  bool get tieneBandaHoy => (rangoHoyP90 - rangoHoyP10).abs() > 0.05;

  factory FotoHoy.fromJson(Map<String, dynamic> j) {
    final r = _m(j['rango_hoy']);
    return FotoHoy(
      edadCronologica: _i(j['edad_cronologica']),
      edadBiologica: _d(j['edad_biologica']),
      rangoHoyP10: _d(r['p10']),
      rangoHoyP90: _d(r['p90']),
      aceleracion: _d(j['aceleracion']),
      percentil: _d(j['percentil_poblacional']),
      nMedidos: _i(j['n_medidos']),
      nInferidos: _i(j['n_inferidos']),
      biomarcadores: _l(j['biomarcadores']).map(BiomarcadorReporte.fromJson).toList(),
      notaPoblacional: '${j['nota_poblacional'] ?? ''}',
      lectura: '${j['lectura'] ?? ''}',
    );
  }
}

class BiomarcadorReporte {
  const BiomarcadorReporte({
    required this.nombre,
    required this.etiqueta,
    required this.valor,
    required this.unidad,
    required this.estado,
    required this.lado,
    required this.rangoReferencia,
    required this.fuente,
    required this.contribucionAnios,
    required this.nota,
  });

  final String nombre;
  final String etiqueta;
  final double valor;
  final String unidad;

  /// `en_rango` | `borde` | `fuera` | `inferido` | `sin_rango`.
  final String estado;
  final String? lado;
  final String? rangoReferencia;

  /// `documento` | `reportado` | `calculado` | `inferido`.
  final String fuente;
  final double contribucionAnios;
  final String? nota;

  bool get inferido => estado == 'inferido';
  bool get marcado => estado == 'borde' || estado == 'fuera';

  factory BiomarcadorReporte.fromJson(Map<String, dynamic> j) => BiomarcadorReporte(
    nombre: '${j['nombre']}',
    etiqueta: '${j['etiqueta'] ?? j['nombre']}',
    valor: _d(j['valor']),
    unidad: '${j['unidad'] ?? ''}',
    estado: '${j['estado'] ?? ''}',
    lado: j['lado'] as String?,
    rangoReferencia: j['rango_referencia'] as String?,
    fuente: '${j['fuente'] ?? ''}',
    contribucionAnios: _d(j['contribucion_anios']),
    nota: j['nota'] as String?,
  );
}

class EjeReporte {
  const EjeReporte({required this.id, required this.nombre, required this.nivel, required this.nivelTexto, required this.aporteAnios, required this.explicacion, required this.biomarcadores});
  final String id;
  final String nombre;

  /// `optimo` | `a_vigilar` | `atencion` | `sin_datos`.
  final String nivel;
  final String nivelTexto;
  final double aporteAnios;
  final String explicacion;
  final List<String> biomarcadores;

  bool get marcado => nivel == 'a_vigilar' || nivel == 'atencion';

  factory EjeReporte.fromJson(Map<String, dynamic> j) => EjeReporte(
    id: '${j['id']}',
    nombre: '${j['nombre'] ?? j['id']}',
    nivel: '${j['nivel'] ?? 'sin_datos'}',
    nivelTexto: '${j['nivel_texto'] ?? ''}',
    aporteAnios: _d(j['aporte_anios']),
    explicacion: '${j['explicacion'] ?? ''}',
    biomarcadores: _l(j['biomarcadores']).map((b) => '${b['etiqueta'] ?? b['nombre']}${b['medido'] == true ? '' : ' (inferido)'}').toList(),
  );
}

class EscenarioClave {
  const EscenarioClave({required this.titulo, required this.nombre, required this.mediana, required this.p10, required this.p90, required this.aniosGanados, required this.rangoGanados, required this.texto});
  final String titulo;
  final String nombre;
  final double mediana;
  final double p10;
  final double p90;
  final double? aniosGanados;
  final List<double>? rangoGanados;
  final String texto;

  factory EscenarioClave.fromJson(Map<String, dynamic> j) {
    final a = _m(j['al_horizonte']);
    return EscenarioClave(
      titulo: '${j['titulo'] ?? ''}',
      nombre: '${j['nombre'] ?? ''}',
      mediana: _d(a['mediana']),
      p10: _d(a['p10']),
      p90: _d(a['p90']),
      aniosGanados: j['anios_ganados'] == null ? null : _d(j['anios_ganados']),
      rangoGanados: j['rango_ganados'] == null ? null : _ld(j['rango_ganados']),
      texto: '${j['texto'] ?? ''}',
    );
  }
}

class RankingItem {
  const RankingItem({required this.escenario, required this.nombre, required this.intervenciones, required this.aniosGanados, required this.p10, required this.p90, required this.pctMejoran, required this.esfuerzo, required this.ratio, required this.fuentes});
  final String escenario;
  final String nombre;
  final List<String> intervenciones;
  final double aniosGanados;
  final double p10;
  final double p90;
  final double pctMejoran;
  final int esfuerzo;
  final double ratio;
  final List<String> fuentes;

  factory RankingItem.fromJson(Map<String, dynamic> j) => RankingItem(
    escenario: '${j['escenario']}',
    nombre: '${j['nombre'] ?? j['escenario']}',
    intervenciones: _ls(j['intervenciones']),
    aniosGanados: _d(j['anios_ganados']),
    p10: _d(j['anios_ganados_p10']),
    p90: _d(j['anios_ganados_p90']),
    pctMejoran: _d(j['pct_futuros_que_mejoran']),
    esfuerzo: _i(j['esfuerzo']),
    ratio: _d(j['ratio_impacto_esfuerzo']),
    fuentes: _ls(j['fuentes']),
  );
}

class FuturosReporte {
  const FuturosReporte({required this.horizonte, required this.sigueIgual, required this.siMejoras, required this.siTeDescuidas, required this.ranking, required this.notaIncertidumbre});
  final int horizonte;
  final EscenarioClave sigueIgual;
  final EscenarioClave? siMejoras;
  final EscenarioClave? siTeDescuidas;
  final List<RankingItem> ranking;
  final String notaIncertidumbre;

  factory FuturosReporte.fromJson(Map<String, dynamic> j) => FuturosReporte(
    horizonte: _i(j['horizonte_anios'], 10),
    sigueIgual: EscenarioClave.fromJson(_m(j['sigues_igual'])),
    siMejoras: j['si_mejoras'] == null ? null : EscenarioClave.fromJson(_m(j['si_mejoras'])),
    siTeDescuidas: j['si_te_descuidas'] == null ? null : EscenarioClave.fromJson(_m(j['si_te_descuidas'])),
    ranking: _l(j['ranking']).map(RankingItem.fromJson).toList(),
    notaIncertidumbre: '${j['nota_incertidumbre'] ?? ''}',
  );
}

class EvidenciaReporte {
  const EvidenciaReporte({required this.hallazgo, required this.fuente});
  final String hallazgo;
  final String fuente;
  factory EvidenciaReporte.fromJson(Map<String, dynamic> j) => EvidenciaReporte(hallazgo: '${j['hallazgo'] ?? ''}', fuente: '${j['fuente'] ?? ''}');
}

class Recomendacion {
  const Recomendacion({required this.id, required this.nombre, required this.queHacer, required this.porQue, required this.aniosGanados, required this.rangoGanados, required this.pctMejoran, required this.esfuerzo, required this.evidencia, required this.habito, required this.brecha});
  final String id;
  final String nombre;
  final String queHacer;
  final String porQue;
  final double aniosGanados;
  final List<double> rangoGanados;
  final double pctMejoran;
  final int esfuerzo;
  final List<EvidenciaReporte> evidencia;
  final String habito;
  final double brecha;

  factory Recomendacion.fromJson(Map<String, dynamic> j) => Recomendacion(
    id: '${j['id']}',
    nombre: '${j['nombre'] ?? j['id']}',
    queHacer: '${j['que_hacer'] ?? ''}',
    porQue: '${j['por_que'] ?? ''}',
    aniosGanados: _d(j['anios_ganados']),
    rangoGanados: _ld(j['rango_ganados']),
    pctMejoran: _d(j['pct_futuros_que_mejoran']),
    esfuerzo: _i(j['esfuerzo']),
    evidencia: _l(j['evidencia']).map(EvidenciaReporte.fromJson).toList(),
    habito: '${j['habito'] ?? ''}',
    brecha: _d(j['brecha'], 1),
  );
}

class SugerenciaConsulta {
  const SugerenciaConsulta({required this.eje, required this.nombre, required this.nivel, required this.profesional, required this.texto});
  final String eje;
  final String nombre;
  final String nivel;
  final String profesional;
  final String texto;
  factory SugerenciaConsulta.fromJson(Map<String, dynamic> j) => SugerenciaConsulta(
    eje: '${j['eje']}',
    nombre: '${j['nombre'] ?? ''}',
    nivel: '${j['nivel'] ?? ''}',
    profesional: '${j['profesional'] ?? ''}',
    texto: '${j['texto'] ?? ''}',
  );
}

class ConsultaReporte {
  const ConsultaReporte({required this.disclaimer, required this.sugerencias, required this.llevaEsto});
  final String disclaimer;
  final List<SugerenciaConsulta> sugerencias;
  final String llevaEsto;
  factory ConsultaReporte.fromJson(Map<String, dynamic> j) => ConsultaReporte(
    disclaimer: '${j['disclaimer'] ?? ''}',
    sugerencias: _l(j['sugerencias']).map(SugerenciaConsulta.fromJson).toList(),
    llevaEsto: '${j['lleva_esto'] ?? ''}',
  );
}

class FaltanteReporte {
  const FaltanteReporte({required this.nombre, required this.etiqueta, required this.reduccionAnios, required this.fraccion});
  final String nombre;
  final String etiqueta;
  final double? reduccionAnios;
  final double? fraccion;
  factory FaltanteReporte.fromJson(Map<String, dynamic> j) => FaltanteReporte(
    nombre: '${j['nombre']}',
    etiqueta: '${j['etiqueta'] ?? j['nombre']}',
    reduccionAnios: j['reduccion_banda_anios'] == null ? null : _d(j['reduccion_banda_anios']),
    fraccion: j['fraccion'] == null ? null : _d(j['fraccion']),
  );
}

class AfinarReporte {
  const AfinarReporte({required this.anchoBandaHoy, required this.faltantes, required this.nota});
  final double anchoBandaHoy;
  final List<FaltanteReporte> faltantes;
  final String nota;
  factory AfinarReporte.fromJson(Map<String, dynamic> j) => AfinarReporte(
    anchoBandaHoy: _d(j['ancho_banda_hoy']),
    faltantes: _l(j['faltantes']).map(FaltanteReporte.fromJson).toList(),
    nota: '${j['nota'] ?? ''}',
  );
}

// ── helpers ───────────────────────────────────────────────────────────────
Map<String, dynamic> _m(dynamic v) => (v as Map?)?.cast<String, dynamic>() ?? const {};
List<Map<String, dynamic>> _l(dynamic v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
List<String> _ls(dynamic v) => ((v as List?) ?? const []).map((e) => '$e').toList();
List<double> _ld(dynamic v) => ((v as List?) ?? const []).map((e) => (e as num).toDouble()).toList();
double _d(dynamic v, [double def = 0]) => (v as num?)?.toDouble() ?? def;
int _i(dynamic v, [int def = 0]) => (v as num?)?.toInt() ?? def;
