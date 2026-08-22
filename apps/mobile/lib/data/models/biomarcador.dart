/// Un biomarcador tal como lo guarda el backend (`/me/health-context`):
/// `nombre` del vocabulario fijo, `unidad` exacta de la tabla de `API.md`.
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

  /// "2026-07" (solo local; el backend no lo guarda).
  final String? fecha;

  /// documento | manual | reportado | calculado | inferido (texto libre en el backend).
  final String fuente;

  /// alta | media | baja — solo en la pantalla de confirmación.
  final String? confianza;

  bool get inferido => fuente == 'inferido';

  Biomarcador copyWith({double? valor, String? unidad, String? fuente, String? confianza, String? fecha}) => Biomarcador(
    nombre: nombre,
    valor: valor ?? this.valor,
    unidad: unidad ?? this.unidad,
    fecha: fecha ?? this.fecha,
    fuente: fuente ?? this.fuente,
    confianza: confianza ?? this.confianza,
  );

  /// JSON para el backend (solo los 4 campos que acepta: `extra="forbid"`).
  Map<String, dynamic> toApiJson() => {'nombre': nombre, 'valor': valor, 'unidad': unidad, 'fuente': fuente};

  /// JSON local (incluye fecha/confianza).
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

/// Vocabulario fijo del backend (`BIOMARKER_SPECS`): 9 de PhenoAge + 3 para
/// otros modelos. Unidades y rangos EXACTOS del backend (un nombre/unidad
/// distinto es 422).
class BiomarcadorDef {
  const BiomarcadorDef({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.min,
    required this.max,
    required this.nucleo,
    required this.phenoAge,
    required this.ayuda,
  });

  final String id;
  final String nombre;
  final String unidad;
  final double min;
  final double max;

  /// Los 6 del "núcleo mínimo" de la spec §1.
  final bool nucleo;

  /// ¿Entra en la fórmula PhenoAge? (9 sí, 3 no).
  final bool phenoAge;
  final String ayuda;

  static const all = <BiomarcadorDef>[
    BiomarcadorDef(id: 'albumina', nombre: 'Albúmina', unidad: 'g/dL', min: 1.5, max: 6.0, nucleo: true, phenoAge: true, ayuda: 'Proteína del hígado. Suele venir en el perfil hepático.'),
    BiomarcadorDef(id: 'creatinina', nombre: 'Creatinina', unidad: 'mg/dL', min: 0.2, max: 15, nucleo: true, phenoAge: true, ayuda: 'Marca cómo filtran tus riñones.'),
    BiomarcadorDef(id: 'glucosa', nombre: 'Glucosa en ayunas', unidad: 'mg/dL', min: 30, max: 600, nucleo: true, phenoAge: true, ayuda: 'Azúcar en sangre tras 8 h sin comer.'),
    BiomarcadorDef(id: 'hs_CRP', nombre: 'Proteína C reactiva (hs-CRP)', unidad: 'mg/L', min: 0.01, max: 200, nucleo: true, phenoAge: true, ayuda: 'Inflamación de bajo grado. La ultrasensible (hs).'),
    BiomarcadorDef(id: 'rdw', nombre: 'RDW', unidad: '%', min: 10, max: 25, nucleo: true, phenoAge: true, ayuda: 'Amplitud de los glóbulos rojos. Viene en el hemograma.'),
    BiomarcadorDef(id: 'leucocitos', nombre: 'Leucocitos', unidad: '10^3/uL', min: 1, max: 50, nucleo: true, phenoAge: true, ayuda: 'Glóbulos blancos totales. Viene en el hemograma.'),
    BiomarcadorDef(id: 'linfocitos_pct', nombre: 'Linfocitos', unidad: '%', min: 1, max: 90, nucleo: false, phenoAge: true, ayuda: 'Porcentaje de linfocitos en el hemograma.'),
    BiomarcadorDef(id: 'vcm', nombre: 'Volumen corpuscular medio (VCM)', unidad: 'fL', min: 50, max: 130, nucleo: false, phenoAge: true, ayuda: 'Tamaño promedio de los glóbulos rojos.'),
    BiomarcadorDef(id: 'fosfatasa_alcalina', nombre: 'Fosfatasa alcalina', unidad: 'U/L', min: 20, max: 500, nucleo: false, phenoAge: true, ayuda: 'Enzima del hígado y hueso.'),
    BiomarcadorDef(id: 'colesterol_total', nombre: 'Colesterol total', unidad: 'mg/dL', min: 50, max: 500, nucleo: false, phenoAge: false, ayuda: 'No entra en PhenoAge; lo uso para otros modelos.'),
    BiomarcadorDef(id: 'presion_sistolica', nombre: 'Presión sistólica', unidad: 'mmHg', min: 60, max: 260, nucleo: false, phenoAge: false, ayuda: 'El número de arriba del tensiómetro.'),
    BiomarcadorDef(id: 'imc', nombre: 'IMC', unidad: 'kg/m2', min: 10, max: 80, nucleo: false, phenoAge: false, ayuda: 'Lo calculo con tu estatura y peso.'),
  ];

  /// Solo los 9 de PhenoAge (lo que piden las pantallas de exámenes).
  static List<BiomarcadorDef> get phenoAgeDefs => all.where((d) => d.phenoAge).toList();

  static BiomarcadorDef? byId(String id) => all.where((d) => d.id == id).firstOrNull;

  /// Unidad "bonita" para mostrar (el backend usa ASCII).
  static String unidadBonita(String u) => switch (u) {
    '10^3/uL' => '10³/µL',
    'kg/m2' => 'kg/m²',
    _ => u,
  };

  /// Medianas de referencia (aprox. adultos) para imputar/mostrar como
  /// "inferido" sin conexión. El backend usa las suyas por edad/sexo.
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
