/// Datos del onboarding que hoy **no** caben en `/me` (el backend solo guarda
/// nombre, nacimiento, estatura, peso, tipo de sangre y sexo). Se persisten
/// localmente y se mandan a `PUT /me/perfil` cuando exista (API_CONTRACT.md §1).
/// Los valores de los catálogos son los del contrato, tal cual.
class OnboardingData {
  const OnboardingData({
    this.nacionalidad,
    this.paisResidencia,
    this.ancestria,
    this.objetivos = const {},
    this.historialFamiliar = const [],
    this.suenoH,
    this.suenoCalidad,
    this.ejercicio,
    this.alcohol,
    this.alcoholFrecuencia,
    this.alimentacion,
    this.alimentacionPatron = const {},
    this.tabaco,
    this.estres,
    this.suplementos = const [],
    this.wearableConectado = false,
    this.wearableProveedor,
    this.fotoPath,
    this.geneticaPath,
    this.completo = false,
  });

  final String? nacionalidad;
  final String? paisResidencia;
  final String? ancestria;
  final Set<String> objetivos;
  final List<FamiliarCondicion> historialFamiliar;
  final double? suenoH;
  final String? suenoCalidad; // baja | media | alta
  final String? ejercicio; // nulo | bajo | moderado | alto
  final String? alcohol; // nunca | ocasional | moderado | alto
  final String? alcoholFrecuencia; // nunca | mensual | 2_3_por_semana | casi_diario | diario
  final String? alimentacion; // baja | media | alta
  final Set<String> alimentacionPatron;
  final bool? tabaco;
  final String? estres; // baja | media | alta
  final List<Suplemento> suplementos;
  final bool wearableConectado;
  final String? wearableProveedor; // health_connect | healthkit
  final String? fotoPath;
  final String? geneticaPath;
  final bool completo;

  OnboardingData copyWith({
    String? nacionalidad,
    String? paisResidencia,
    String? ancestria,
    Set<String>? objetivos,
    List<FamiliarCondicion>? historialFamiliar,
    double? suenoH,
    String? suenoCalidad,
    String? ejercicio,
    String? alcohol,
    String? alcoholFrecuencia,
    String? alimentacion,
    Set<String>? alimentacionPatron,
    bool? tabaco,
    String? estres,
    List<Suplemento>? suplementos,
    bool? wearableConectado,
    String? wearableProveedor,
    String? fotoPath,
    String? geneticaPath,
    bool? completo,
    bool clearFoto = false,
    bool clearGenetica = false,
  }) => OnboardingData(
    nacionalidad: nacionalidad ?? this.nacionalidad,
    paisResidencia: paisResidencia ?? this.paisResidencia,
    ancestria: ancestria ?? this.ancestria,
    objetivos: objetivos ?? this.objetivos,
    historialFamiliar: historialFamiliar ?? this.historialFamiliar,
    suenoH: suenoH ?? this.suenoH,
    suenoCalidad: suenoCalidad ?? this.suenoCalidad,
    ejercicio: ejercicio ?? this.ejercicio,
    alcohol: alcohol ?? this.alcohol,
    alcoholFrecuencia: alcoholFrecuencia ?? this.alcoholFrecuencia,
    alimentacion: alimentacion ?? this.alimentacion,
    alimentacionPatron: alimentacionPatron ?? this.alimentacionPatron,
    tabaco: tabaco ?? this.tabaco,
    estres: estres ?? this.estres,
    suplementos: suplementos ?? this.suplementos,
    wearableConectado: wearableConectado ?? this.wearableConectado,
    wearableProveedor: wearableProveedor ?? this.wearableProveedor,
    fotoPath: clearFoto ? null : (fotoPath ?? this.fotoPath),
    geneticaPath: clearGenetica ? null : (geneticaPath ?? this.geneticaPath),
    completo: completo ?? this.completo,
  );

  Map<String, dynamic> toJson() => {
    'nacionalidad': nacionalidad,
    'pais_residencia': paisResidencia,
    'ancestria_reportada': ancestria,
    'objetivos': objetivos.toList(),
    'historial_familiar': historialFamiliar.map((e) => e.toJson()).toList(),
    'habitos_moduladores': {
      'sueno_h': suenoH,
      'sueno_calidad': suenoCalidad,
      'ejercicio': ejercicio,
      'alcohol': alcohol,
      'alcohol_frecuencia': alcoholFrecuencia,
      'alimentacion': alimentacion,
      'alimentacion_patron': alimentacionPatron.toList(),
      'tabaco': tabaco,
      'estres': estres,
    },
    'suplementos': suplementos.map((e) => e.toJson()).toList(),
    'wearable': {'proveedor': wearableProveedor, 'conectado': wearableConectado},
    'foto_path': fotoPath,
    'genetica_path': geneticaPath,
    'onboarding_completo': completo,
  };

  factory OnboardingData.fromJson(Map<String, dynamic> j) {
    final h = (j['habitos_moduladores'] as Map?)?.cast<String, dynamic>() ?? const {};
    final w = (j['wearable'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OnboardingData(
      nacionalidad: j['nacionalidad'] as String?,
      paisResidencia: j['pais_residencia'] as String?,
      ancestria: j['ancestria_reportada'] as String?,
      objetivos: ((j['objetivos'] as List?) ?? const []).map((e) => '$e').toSet(),
      historialFamiliar: ((j['historial_familiar'] as List?) ?? const [])
          .map((e) => FamiliarCondicion.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      suenoH: (h['sueno_h'] as num?)?.toDouble(),
      suenoCalidad: h['sueno_calidad'] as String?,
      ejercicio: h['ejercicio'] as String?,
      alcohol: h['alcohol'] as String?,
      alcoholFrecuencia: h['alcohol_frecuencia'] as String?,
      alimentacion: h['alimentacion'] as String?,
      alimentacionPatron: ((h['alimentacion_patron'] as List?) ?? const []).map((e) => '$e').toSet(),
      tabaco: h['tabaco'] as bool?,
      estres: h['estres'] as String?,
      suplementos: ((j['suplementos'] as List?) ?? const [])
          .map((e) => Suplemento.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      wearableConectado: w['conectado'] == true,
      wearableProveedor: w['proveedor'] as String?,
      fotoPath: j['foto_path'] as String?,
      geneticaPath: j['genetica_path'] as String?,
      completo: j['onboarding_completo'] == true,
    );
  }

  /// Los hábitos en la forma de la spec §3 (`habitos_moduladores`).
  Map<String, dynamic> get habitosSpec => {
    'sueno_h': suenoH ?? 7,
    'sueno_calidad': suenoCalidad ?? 'media',
    'ejercicio': ejercicio ?? 'bajo',
    'alcohol': alcohol ?? 'ocasional',
    'alimentacion': alimentacion ?? 'media',
    'tabaco': tabaco ?? false,
    'estres': estres ?? 'media',
  };
}

class FamiliarCondicion {
  const FamiliarCondicion({required this.condicion, this.parentesco});
  final String condicion;
  final String? parentesco;

  Map<String, dynamic> toJson() => {'condicion': condicion, 'parentesco': parentesco};
  factory FamiliarCondicion.fromJson(Map<String, dynamic> j) =>
      FamiliarCondicion(condicion: '${j['condicion']}', parentesco: j['parentesco'] as String?);
}

class Suplemento {
  const Suplemento({required this.nombre, this.dosis, this.frecuencia});
  final String nombre;
  final String? dosis;
  final String? frecuencia;

  Map<String, dynamic> toJson() => {'nombre': nombre, 'dosis': dosis, 'frecuencia': frecuencia};
  factory Suplemento.fromJson(Map<String, dynamic> j) => Suplemento(
    nombre: '${j['nombre']}',
    dosis: j['dosis'] as String?,
    frecuencia: j['frecuencia'] as String?,
  );
}

/// Catálogos (valores API → etiqueta). Mantener sincronizados con API_CONTRACT.md.
abstract final class Catalogos {
  static const objetivos = <String, String>{
    'energia': 'Más energía',
    'prevencion': 'Prevención',
    'longevidad': 'Longevidad',
    'fertilidad': 'Fertilidad',
    'rendimiento': 'Rendimiento físico',
    'sueno': 'Dormir mejor',
    'peso': 'Peso saludable',
    'salud_mental': 'Salud mental',
  };

  static const condicionesFamiliares = <String, String>{
    'diabetes_t2': 'Diabetes tipo 2',
    'cardiovascular': 'Infarto o enfermedad del corazón',
    'hipertension': 'Presión alta',
    'cancer': 'Cáncer',
    'alzheimer': 'Alzheimer o demencia',
    'obesidad': 'Obesidad',
    'tiroides': 'Tiroides',
    'ninguna': 'Ninguna que yo sepa',
  };

  static const parentescos = <String, String>{
    'madre': 'Madre',
    'padre': 'Padre',
    'hermano': 'Hermano/a',
    'abuelo': 'Abuelo/a',
    'otro': 'Otro familiar',
  };

  static const nivelBMA = <String, String>{'baja': 'Baja', 'media': 'Media', 'alta': 'Alta'};

  static const ejercicio = <String, String>{
    'nulo': 'Casi nada',
    'bajo': 'Poco (1–2 veces/sem)',
    'moderado': 'Moderado (3–4 veces/sem)',
    'alto': 'Mucho (5+ veces/sem)',
  };

  static const alcoholFrecuencia = <String, String>{
    'nunca': 'Nunca',
    'mensual': 'Alguna vez al mes',
    '2_3_por_semana': '2–3 veces por semana',
    'casi_diario': 'Casi todos los días',
    'diario': 'Todos los días',
  };

  /// Mapea frecuencia → nivel `alcohol` de la spec.
  static String alcoholNivel(String? frecuencia) => switch (frecuencia) {
    'nunca' => 'nunca',
    'mensual' => 'ocasional',
    '2_3_por_semana' => 'moderado',
    'casi_diario' || 'diario' => 'alto',
    _ => 'ocasional',
  };

  static const alimentacionPatron = <String, String>{
    'frutas_verduras_diario': 'Frutas y verduras a diario',
    'ultraprocesados_frecuentes': 'Ultraprocesados seguido',
    'poca_fibra': 'Poca fibra',
    'azucar_alto': 'Mucha azúcar',
    'proteina_suficiente': 'Proteína suficiente',
    'come_tarde': 'Como muy tarde en la noche',
  };

  static const ancestria = <String, String>{
    'mixta_latam': 'Mixta latinoamericana',
    'europea': 'Europea',
    'africana': 'Africana',
    'indigena': 'Indígena',
    'asiatica': 'Asiática',
    'otra': 'Otra',
    'prefiero_no_decir': 'Prefiero no decir',
  };

  static const suplementosComunes = <String, String>{
    'vitamina_d': 'Vitamina D',
    'omega_3': 'Omega 3',
    'magnesio': 'Magnesio',
    'creatina': 'Creatina',
    'proteina': 'Proteína',
    'multivitaminico': 'Multivitamínico',
    'hierro': 'Hierro',
    'probioticos': 'Probióticos',
    'melatonina': 'Melatonina',
  };

  static const paises = <String, String>{
    'CO': 'Colombia',
    'MX': 'México',
    'AR': 'Argentina',
    'CL': 'Chile',
    'PE': 'Perú',
    'EC': 'Ecuador',
    'VE': 'Venezuela',
    'UY': 'Uruguay',
    'BO': 'Bolivia',
    'PY': 'Paraguay',
    'BR': 'Brasil',
    'US': 'Estados Unidos',
    'ES': 'España',
    'OT': 'Otro',
  };
}
