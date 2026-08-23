import 'biomarcador.dart';

/// Input de `POST /simular` — exactamente la spec §3.
class SimulacionInput {
  const SimulacionInput({
    required this.demografia,
    required this.objetivos,
    required this.historialFamiliar,
    required this.biomarcadores,
    required this.habitos,
    this.opcionales = const {'suplementos': [], 'prueba_genetica': null, 'foto': null},
    this.datosFaltantes = const [],
    this.notasIncertidumbre,
  });

  final Map<String, dynamic> demografia;
  final List<String> objetivos;
  final List<String> historialFamiliar;
  final List<Biomarcador> biomarcadores;
  final Map<String, dynamic> habitos;
  final Map<String, dynamic> opcionales;
  final List<String> datosFaltantes;
  final String? notasIncertidumbre;

  int get edad => (demografia['edad'] as num).toInt();
  String get sexo => '${demografia['sexo_biologico'] ?? 'F'}';

  Map<String, dynamic> toJson() => {
    'demografia': demografia,
    'objetivos': objetivos,
    'historial_familiar': historialFamiliar,
    'biomarcadores': biomarcadores.map((b) => b.toJson()).toList(),
    'habitos_moduladores': habitos,
    'opcionales': opcionales,
    'datos_faltantes': datosFaltantes,
    'notas_incertidumbre': notasIncertidumbre,
  };

  factory SimulacionInput.fromJson(Map<String, dynamic> j) => SimulacionInput(
    demografia: (j['demografia'] as Map).cast<String, dynamic>(),
    objetivos: ((j['objetivos'] as List?) ?? const []).map((e) => '$e').toList(),
    historialFamiliar: ((j['historial_familiar'] as List?) ?? const []).map((e) => '$e').toList(),
    biomarcadores: ((j['biomarcadores'] as List?) ?? const [])
        .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    habitos: (j['habitos_moduladores'] as Map).cast<String, dynamic>(),
    opcionales: (j['opcionales'] as Map?)?.cast<String, dynamic>() ?? const {},
    datosFaltantes: ((j['datos_faltantes'] as List?) ?? const []).map((e) => '$e').toList(),
    notasIncertidumbre: j['notas_incertidumbre'] as String?,
  );
}

/// Curva con percentiles por año (spec §6/§8).
class Curva {
  const Curva({required this.anios, required this.mediana, required this.p10, required this.p90});

  final List<int> anios;
  final List<double> mediana;
  final List<double> p10;
  final List<double> p90;

  double get final_ => mediana.last;

  Map<String, dynamic> toJson() => {'anios': anios, 'mediana': mediana, 'p10': p10, 'p90': p90};

  factory Curva.fromJson(Map<String, dynamic> j) => Curva(
    anios: ((j['anios'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
    mediana: _d(j['mediana']),
    p10: _d(j['p10']),
    p90: _d(j['p90']),
  );

  static List<double> _d(dynamic l) => ((l as List?) ?? const []).map((e) => (e as num).toDouble()).toList();
}

/// Una intervención del catálogo (spec §5/§6).
class Intervencion {
  const Intervencion({required this.id, required this.etiqueta, required this.esfuerzo, required this.icono, required this.descripcion});

  final String id;
  final String etiqueta;
  final int esfuerzo;

  /// Nombre de icono Material (`Icons.<x>`) sugerido por la API; la app lo mapea.
  final String icono;
  final String descripcion;

  Map<String, dynamic> toJson() => {'id': id, 'etiqueta': etiqueta, 'esfuerzo': esfuerzo, 'icono': icono, 'descripcion': descripcion};

  factory Intervencion.fromJson(Map<String, dynamic> j) => Intervencion(
    id: '${j['id']}',
    etiqueta: '${j['etiqueta'] ?? j['id']}',
    esfuerzo: (j['esfuerzo'] as num?)?.toInt() ?? 2,
    icono: '${j['icono'] ?? 'spa'}',
    descripcion: '${j['descripcion'] ?? ''}',
  );

  String get esfuerzoLabel => switch (esfuerzo) { <= 2 => 'esfuerzo bajo', 3 => 'esfuerzo medio', _ => 'esfuerzo alto' };
}

/// Un escenario del barrido (spec §6) con las extensiones del contrato.
class Escenario {
  const Escenario({
    required this.intervenciones,
    required this.etiqueta,
    required this.aniosGanados,
    required this.rango,
    required this.esfuerzo,
    required this.ratio,
    required this.pctMejoran,
    required this.curva,
  });

  final List<String> intervenciones;
  final String etiqueta;
  final double aniosGanados;
  final List<double> rango;
  final int esfuerzo;
  final double ratio;
  final int pctMejoran;
  final Curva curva;

  String get esfuerzoLabel => switch (esfuerzo) { <= 2 => 'esfuerzo bajo', <= 4 => 'esfuerzo medio', _ => 'esfuerzo alto' };

  Map<String, dynamic> toJson() => {
    'intervenciones': intervenciones,
    'etiqueta': etiqueta,
    'anios_ganados': aniosGanados,
    'rango': rango,
    'esfuerzo': esfuerzo,
    'ratio_impacto_esfuerzo': ratio,
    'pct_futuros_que_mejoran': pctMejoran,
    'curva': curva.toJson(),
  };

  factory Escenario.fromJson(Map<String, dynamic> j) => Escenario(
    intervenciones: ((j['intervenciones'] as List?) ?? const []).map((e) => '$e').toList(),
    etiqueta: '${j['etiqueta'] ?? ''}',
    aniosGanados: (j['anios_ganados'] as num?)?.toDouble() ?? 0,
    rango: Curva._d(j['rango']),
    esfuerzo: (j['esfuerzo'] as num?)?.toInt() ?? 0,
    ratio: (j['ratio_impacto_esfuerzo'] as num? ?? j['ratio'] as num?)?.toDouble() ?? 0,
    pctMejoran: (j['pct_futuros_que_mejoran'] as num?)?.toInt() ?? 0,
    curva: Curva.fromJson((j['curva'] as Map).cast<String, dynamic>()),
  );
}

class ShapDriver {
  const ShapDriver({required this.variable, required this.contribucion, required this.direccion});
  final String variable;
  final double contribucion;

  /// mejora | empeora
  final String direccion;

  Map<String, dynamic> toJson() => {'variable': variable, 'contribucion': contribucion, 'direccion': direccion};
  factory ShapDriver.fromJson(Map<String, dynamic> j) => ShapDriver(
    variable: '${j['variable']}',
    contribucion: (j['contribucion'] as num?)?.toDouble() ?? 0,
    direccion: '${j['direccion'] ?? (((j['contribucion'] as num?) ?? 0) < 0 ? 'mejora' : 'empeora')}',
  );
}

/// Cuánto angostaría la banda medir un biomarcador hoy imputado
/// (`/montecarlo.valor_de_informacion`).
class ValorDeInformacion {
  const ValorDeInformacion({required this.nombre, required this.reduccionAnios, required this.fraccion});
  final String nombre;

  /// Años que se angosta la banda P10–P90 al horizonte si se mide.
  final double reduccionAnios;

  /// Parte de la reducción total (suma 1 entre los imputados).
  final double fraccion;

  Map<String, dynamic> toJson() => {'nombre': nombre, 'reduccion_banda_anios': reduccionAnios, 'fraccion': fraccion};
  factory ValorDeInformacion.fromJson(Map<String, dynamic> j) => ValorDeInformacion(
    nombre: '${j['nombre']}',
    reduccionAnios: (j['reduccion_banda_anios'] as num?)?.toDouble() ?? 0,
    fraccion: (j['fraccion'] as num?)?.toDouble() ?? 0,
  );
}

/// Output de `POST /simular` — spec §8 + extensiones (API_CONTRACT.md §3).
class SimulacionResultado {
  const SimulacionResultado({
    required this.id,
    required this.creadoEn,
    required this.edadCronologica,
    required this.edadBiologicaHoy,
    required this.baseline,
    required this.mejorDecision,
    required this.veredicto,
    required this.porque,
    required this.shap,
    required this.percentilPoblacional,
    required this.mensajePoblacional,
    required this.incertidumbre,
    required this.descargo,
    required this.escenarios,
    required this.muestraTrayectorias,
    required this.catalogo,
    this.biomarcadoresUsados = const [],
    this.valorDeInformacion = const [],
    this.anchoBandaHoy = 0,
    this.fuenteCurvas = 'interpolada',
  });

  final String id;
  final DateTime creadoEn;
  final int edadCronologica;
  final double edadBiologicaHoy;
  final Curva baseline;
  final Escenario mejorDecision;
  final String veredicto;
  final String porque;
  final List<ShapDriver> shap;
  final int percentilPoblacional;
  final String mensajePoblacional;
  final String incertidumbre;
  final String descargo;
  final List<Escenario> escenarios;
  final List<List<double>> muestraTrayectorias;
  final List<Intervencion> catalogo;
  final List<Biomarcador> biomarcadoresUsados;

  /// Qué biomarcador imputado angostaría más la banda si se midiera (del
  /// motor). Vacío si los 9 están medidos o el backend no lo expone.
  final List<ValorDeInformacion> valorDeInformacion;

  /// P90 − P10 de la edad biológica HOY: 0 con los 9 medidos; la
  /// incertidumbre de lo imputado si no.
  final double anchoBandaHoy;

  /// `motor` = curvas/trayectorias/años ganados reales del backend (pareados);
  /// `interpolada` = aproximación local (backend viejo); `mock` = motor mock.
  final String fuenteCurvas;

  double get delta => edadBiologicaHoy - edadCronologica;

  /// ¿Las curvas y deltas salen del motor (no de una aproximación local)?
  bool get curvasDelMotor => fuenteCurvas == 'motor' || fuenteCurvas == 'mock';

  Intervencion? intervencion(String id) => catalogo.where((i) => i.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'id': id,
    'creado_en': creadoEn.toIso8601String(),
    'edad_cronologica': edadCronologica,
    'edad_biologica_hoy': edadBiologicaHoy,
    'trayectoria_baseline': baseline.toJson(),
    'mejor_decision': {
      'intervenciones': mejorDecision.intervenciones,
      'anios_ganados': mejorDecision.aniosGanados,
      'rango': mejorDecision.rango,
      'esfuerzo': mejorDecision.esfuerzo,
      'ratio_impacto_esfuerzo': mejorDecision.ratio,
    },
    'veredicto_gemelo': veredicto,
    'porque': porque,
    'shap_top_drivers': shap.map((e) => e.toJson()).toList(),
    'comparacion_poblacional': {'fuente': 'NHANES', 'percentil_edad_biologica': percentilPoblacional, 'mensaje': mensajePoblacional},
    'incertidumbre': incertidumbre,
    'descargo': descargo,
    'escenarios': escenarios.map((e) => e.toJson()).toList(),
    'muestra_trayectorias': muestraTrayectorias,
    'intervenciones_catalogo': catalogo.map((e) => e.toJson()).toList(),
    'biomarcadores_usados': biomarcadoresUsados.map((e) => e.toJson()).toList(),
    'valor_de_informacion': valorDeInformacion.map((e) => e.toJson()).toList(),
    'ancho_banda_hoy': anchoBandaHoy,
    'fuente_curvas': fuenteCurvas,
  };

  /// Versión compacta para el chat (`POST /me/health-context/chat`, campo
  /// `resultado`): lo mismo que [toJson] sin `muestra_trayectorias` (el
  /// grueso del payload, que el agente nunca lee) y con las curvas a un
  /// decimal. Queda en unos pocos KB.
  Map<String, dynamic> toChatJson() {
    final j = toJson()..remove('muestra_trayectorias');
    j['trayectoria_baseline'] = _curvaCompacta(baseline);
    j['escenarios'] = [for (final e in escenarios) e.toJson()..['curva'] = _curvaCompacta(e.curva)];
    return j;
  }

  static Map<String, dynamic> _curvaCompacta(Curva c) => {
    'anios': c.anios,
    'mediana': [for (final v in c.mediana) (v * 10).round() / 10],
    'p10': [for (final v in c.p10) (v * 10).round() / 10],
    'p90': [for (final v in c.p90) (v * 10).round() / 10],
  };

  factory SimulacionResultado.fromJson(Map<String, dynamic> j) {
    final escenarios = ((j['escenarios'] as List?) ?? const [])
        .map((e) => Escenario.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final md = (j['mejor_decision'] as Map?)?.cast<String, dynamic>() ?? const {};
    final baseline = Curva.fromJson((j['trayectoria_baseline'] as Map).cast<String, dynamic>());
    final mejor = escenarios.isNotEmpty
        ? escenarios.first
        : Escenario(
            intervenciones: ((md['intervenciones'] as List?) ?? const []).map((e) => '$e').toList(),
            etiqueta: '',
            aniosGanados: (md['anios_ganados'] as num?)?.toDouble() ?? 0,
            rango: Curva._d(md['rango']),
            esfuerzo: (md['esfuerzo'] as num?)?.toInt() ?? 0,
            ratio: (md['ratio_impacto_esfuerzo'] as num?)?.toDouble() ?? 0,
            pctMejoran: 0,
            curva: baseline,
          );
    final cp = (j['comparacion_poblacional'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SimulacionResultado(
      id: '${j['id'] ?? 'sim_local'}',
      creadoEn: DateTime.tryParse('${j['creado_en']}') ?? DateTime.now(),
      edadCronologica: (j['edad_cronologica'] as num).toInt(),
      edadBiologicaHoy: (j['edad_biologica_hoy'] as num).toDouble(),
      baseline: baseline,
      mejorDecision: mejor,
      veredicto: '${j['veredicto_gemelo'] ?? ''}',
      porque: '${j['porque'] ?? ''}',
      shap: ((j['shap_top_drivers'] as List?) ?? const [])
          .map((e) => ShapDriver.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      percentilPoblacional: (cp['percentil_edad_biologica'] as num?)?.toInt() ?? 50,
      mensajePoblacional: '${cp['mensaje'] ?? ''}',
      incertidumbre: '${j['incertidumbre'] ?? ''}',
      descargo: '${j['descargo'] ?? 'Estimación de riesgo poblacional, no diagnóstico.'}',
      escenarios: escenarios,
      muestraTrayectorias: ((j['muestra_trayectorias'] as List?) ?? const [])
          .map((t) => ((t as List).map((e) => (e as num).toDouble()).toList()))
          .toList(),
      catalogo: ((j['intervenciones_catalogo'] as List?) ?? const [])
          .map((e) => Intervencion.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      biomarcadoresUsados: ((j['biomarcadores_usados'] as List?) ?? const [])
          .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      valorDeInformacion: ((j['valor_de_informacion'] as List?) ?? const [])
          .map((e) => ValorDeInformacion.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      anchoBandaHoy: (j['ancho_banda_hoy'] as num?)?.toDouble() ?? 0,
      fuenteCurvas: '${j['fuente_curvas'] ?? 'interpolada'}',
    );
  }
}

/// Progreso de una simulación en curso (polling a `GET /simulaciones/{id}` o
/// el motor mock corriendo en el dispositivo).
class SimulacionProgreso {
  const SimulacionProgreso({required this.fraccion, required this.vidas, required this.totalVidas, this.trayectoriasParciales = const [], this.resultado});

  final double fraccion;
  final int vidas;
  final int totalVidas;

  /// Trayectorias ya listas para dibujar mientras corre.
  final List<List<double>> trayectoriasParciales;
  final SimulacionResultado? resultado;

  bool get lista => resultado != null;
}

/// Resumen para el historial (`GET /me/simulaciones`).
class SimulacionResumen {
  const SimulacionResumen({required this.id, required this.creadoEn, required this.edadBiologicaHoy, required this.mejorIntervenciones, required this.aniosGanados});
  final String id;
  final DateTime creadoEn;
  final double edadBiologicaHoy;
  final List<String> mejorIntervenciones;
  final double aniosGanados;

  factory SimulacionResumen.fromResultado(SimulacionResultado r) => SimulacionResumen(
    id: r.id,
    creadoEn: r.creadoEn,
    edadBiologicaHoy: r.edadBiologicaHoy,
    mejorIntervenciones: r.mejorDecision.intervenciones,
    aniosGanados: r.mejorDecision.aniosGanados,
  );
}
