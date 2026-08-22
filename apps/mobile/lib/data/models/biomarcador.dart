/// Un biomarcador en la forma de la spec §3.
class Biomarcador {
  const Biomarcador({
    required this.nombre,
    required this.valor,
    required this.unidad,
    this.fecha,
    this.fuente = 'manual',
    this.confianza,
  });

  final String nombre;
  final double valor;
  final String unidad;

  /// "2026-07"
  final String? fecha;

  /// documento | manual | inferido
  final String fuente;

  /// alta | media | baja — solo cuando viene de `/examenes/extraer`.
  final String? confianza;

  bool get inferido => fuente == 'inferido';

  Biomarcador copyWith({double? valor, String? unidad, String? fuente, String? confianza, String? fecha}) =>
      Biomarcador(
        nombre: nombre,
        valor: valor ?? this.valor,
        unidad: unidad ?? this.unidad,
        fecha: fecha ?? this.fecha,
        fuente: fuente ?? this.fuente,
        confianza: confianza ?? this.confianza,
      );

  Map<String, dynamic> toJson() => {
    'nombre': nombre,
    'valor': valor,
    'unidad': unidad,
    if (fecha != null) 'fecha': fecha,
    'fuente': fuente,
    if (confianza != null) 'confianza': confianza,
  };

  factory Biomarcador.fromJson(Map<String, dynamic> j) => Biomarcador(
    nombre: '${j['nombre']}',
    valor: (j['valor'] as num).toDouble(),
    unidad: '${j['unidad'] ?? ''}',
    fecha: j['fecha'] as String?,
    fuente: '${j['fuente'] ?? 'manual'}',
    confianza: j['confianza'] as String?,
  );
}

/// Catálogo de los 9 biomarcadores PhenoAge (spec §4) con unidades del usuario
/// (las que trae un laboratorio en Colombia) y rangos plausibles para validar.
class BiomarcadorDef {
  const BiomarcadorDef({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.min,
    required this.max,
    required this.nucleo,
    required this.ayuda,
  });

  final String id;
  final String nombre;
  final String unidad;
  final double min;
  final double max;

  /// Los 6 del "núcleo mínimo" de la spec §1; los otros 3 se imputan si faltan.
  final bool nucleo;
  final String ayuda;

  static const all = <BiomarcadorDef>[
    BiomarcadorDef(id: 'albumina', nombre: 'Albúmina', unidad: 'g/dL', min: 2.0, max: 6.0, nucleo: true, ayuda: 'Proteína del hígado. Suele venir en el perfil hepático.'),
    BiomarcadorDef(id: 'creatinina', nombre: 'Creatinina', unidad: 'mg/dL', min: 0.3, max: 4.0, nucleo: true, ayuda: 'Marca cómo filtran tus riñones.'),
    BiomarcadorDef(id: 'glucosa', nombre: 'Glucosa en ayunas', unidad: 'mg/dL', min: 50, max: 300, nucleo: true, ayuda: 'Azúcar en sangre tras 8 h sin comer.'),
    BiomarcadorDef(id: 'hs_CRP', nombre: 'Proteína C reactiva (hs-CRP)', unidad: 'mg/L', min: 0.05, max: 50, nucleo: true, ayuda: 'Inflamación de bajo grado. La ultrasensible (hs).'),
    BiomarcadorDef(id: 'rdw', nombre: 'RDW', unidad: '%', min: 9, max: 25, nucleo: true, ayuda: 'Amplitud de los glóbulos rojos. Viene en el hemograma.'),
    BiomarcadorDef(id: 'leucocitos', nombre: 'Leucocitos', unidad: '10³/µL', min: 1.5, max: 25, nucleo: true, ayuda: 'Glóbulos blancos totales. Viene en el hemograma.'),
    BiomarcadorDef(id: 'linfocitos_pct', nombre: 'Linfocitos', unidad: '%', min: 5, max: 70, nucleo: false, ayuda: 'Porcentaje de linfocitos en el hemograma.'),
    BiomarcadorDef(id: 'vcm', nombre: 'Volumen corpuscular medio (VCM)', unidad: 'fL', min: 60, max: 120, nucleo: false, ayuda: 'Tamaño promedio de los glóbulos rojos.'),
    BiomarcadorDef(id: 'fosfatasa_alcalina', nombre: 'Fosfatasa alcalina', unidad: 'U/L', min: 20, max: 400, nucleo: false, ayuda: 'Enzima del hígado y hueso.'),
  ];

  static BiomarcadorDef? byId(String id) => all.where((d) => d.id == id).firstOrNull;

  /// Medianas de referencia (aprox. NHANES adultos) para imputar/mostrar
  /// como "inferido". El backend usa las suyas por edad/sexo; estas son solo
  /// para que la UI tenga algo que mostrar sin conexión.
  static const medianas = <String, double>{
    'albumina': 4.3,
    'creatinina': 0.85,
    'glucosa': 95,
    'hs_CRP': 1.8,
    'rdw': 13.0,
    'leucocitos': 6.5,
    'linfocitos_pct': 30,
    'vcm': 90,
    'fosfatasa_alcalina': 70,
  };
}
