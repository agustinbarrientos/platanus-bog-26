/// `GET /me/voice/estado`: si este despliegue del backend puede hablar y
/// escuchar. La app lo pregunta una vez al abrir el chat y esconde el
/// altavoz y el micrófono si no — mejor que descubrir un 503 en vivo.
class EstadoVoz {
  const EstadoVoz({required this.disponible, required this.modeloTts, required this.modeloStt, required this.maxCaracteres});

  final bool disponible;
  final String modeloTts;
  final String modeloStt;

  /// Techo de caracteres por síntesis; por encima el backend recorta en la
  /// última frase que quepa.
  final int maxCaracteres;

  /// Lo que se asume cuando no se pudo preguntar (sin red, backend viejo):
  /// no hay voz remota. La app cae a la voz del dispositivo, no a un error.
  static const nula = EstadoVoz(disponible: false, modeloTts: '', modeloStt: '', maxCaracteres: 0);

  factory EstadoVoz.fromJson(Map<String, dynamic> j) => EstadoVoz(
    disponible: j['disponible'] == true,
    modeloTts: '${j['modelo_tts'] ?? ''}',
    modeloStt: '${j['modelo_stt'] ?? ''}',
    maxCaracteres: (j['max_caracteres'] as num?)?.toInt() ?? 0,
  );
}
