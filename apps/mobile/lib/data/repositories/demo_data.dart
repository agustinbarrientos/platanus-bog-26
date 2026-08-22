import '../models/biomarcador.dart';
import '../models/simulacion.dart';

/// Caso demo precargado (spec §9 y §11 paso 9): la red de seguridad del pitch.
/// Nunca depender del upload en vivo.
abstract final class DemoData {
  static SimulacionInput perfil() => SimulacionInput(
    demografia: const {
      'edad': 34,
      'sexo_biologico': 'F',
      'peso_kg': 62,
      'estatura_cm': 164,
      'nacionalidad': 'CO',
      'ancestria_reportada': 'mixta_latam',
    },
    objetivos: const ['energia', 'prevencion', 'longevidad'],
    historialFamiliar: const ['diabetes_t2', 'cardiovascular'],
    biomarcadores: const [
      Biomarcador(nombre: 'albumina', valor: 4.4, unidad: 'g/dL', fecha: '2026-07', fuente: 'documento'),
      Biomarcador(nombre: 'creatinina', valor: 0.8, unidad: 'mg/dL', fecha: '2026-07', fuente: 'documento'),
      Biomarcador(nombre: 'glucosa', valor: 92, unidad: 'mg/dL', fecha: '2026-07', fuente: 'documento'),
      Biomarcador(nombre: 'hs_CRP', valor: 2.1, unidad: 'mg/L', fecha: '2026-07', fuente: 'documento'),
      Biomarcador(nombre: 'rdw', valor: 13.1, unidad: '%', fecha: '2026-07', fuente: 'documento'),
      Biomarcador(nombre: 'leucocitos', valor: 6.2, unidad: '10³/µL', fecha: '2026-07', fuente: 'documento'),
    ],
    habitos: const {
      'sueno_h': 6,
      'sueno_calidad': 'media',
      'ejercicio': 'bajo',
      'alcohol': 'moderado',
      'alimentacion': 'media',
      'tabaco': false,
      'estres': 'alta',
    },
    datosFaltantes: const ['fosfatasa_alcalina', 'linfocitos_pct', 'vcm'],
    notasIncertidumbre: '3 biomarcadores imputados de medianas NHANES por edad/sexo',
  );

  /// Lo que devolvería `/examenes/extraer` para el examen de ejemplo.
  static List<Biomarcador> lecturaExamen() => const [
    Biomarcador(nombre: 'albumina', valor: 4.4, unidad: 'g/dL', fecha: '2026-07', fuente: 'documento', confianza: 'alta'),
    Biomarcador(nombre: 'creatinina', valor: 0.8, unidad: 'mg/dL', fecha: '2026-07', fuente: 'documento', confianza: 'alta'),
    Biomarcador(nombre: 'glucosa', valor: 92, unidad: 'mg/dL', fecha: '2026-07', fuente: 'documento', confianza: 'alta'),
    Biomarcador(nombre: 'hs_CRP', valor: 2.1, unidad: 'mg/L', fecha: '2026-07', fuente: 'documento', confianza: 'media'),
    Biomarcador(nombre: 'rdw', valor: 13.1, unidad: '%', fecha: '2026-07', fuente: 'documento', confianza: 'baja'),
    Biomarcador(nombre: 'leucocitos', valor: 6.2, unidad: '10³/µL', fecha: '2026-07', fuente: 'documento', confianza: 'alta'),
  ];
}
