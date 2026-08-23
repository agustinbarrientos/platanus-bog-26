import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/voz.dart';

/// La voz de Moirai, a través del backend (`/me/voice`), nunca contra
/// ElevenLabs directo: la API key vive en el servidor porque un
/// `--dart-define` queda en texto plano dentro del APK.
///
/// El backend también normaliza el texto para que suene bien (`8.240` →
/// `8240`, `+2,4` → "más 2,4", `hs-CRP` → el nombre completo), así que aquí
/// se manda el `reply` tal cual llegó del chat.
///
/// El MP3 se guarda en un archivo temporal con el nombre derivado del texto:
/// volver a tocar el altavoz en la misma respuesta la reproduce sin gastar
/// créditos otra vez. En un plan gratis eso es la diferencia entre que la
/// demo aguante o no.
class VoiceRepository {
  VoiceRepository(this._api);
  final ApiClient _api;

  Directory? _cacheDir;

  Future<EstadoVoz> estado() async {
    try {
      final j = await _api.get('/me/voice/estado');
      return EstadoVoz.fromJson((j as Map).cast<String, dynamic>());
    } catch (_) {
      return EstadoVoz.nula;
    }
  }

  /// Ruta a un MP3 con [texto] leído en voz de Moirai. Lanza [ApiException]
  /// si el backend no puede: `402` sin créditos, `503` voz no configurada.
  Future<String> audioDe(String texto) async {
    final dir = _cacheDir ??= await getTemporaryDirectory();
    final archivo = File('${dir.path}/moirai_${md5.convert(utf8.encode(texto))}.mp3');
    if (await archivo.exists() && await archivo.length() > 0) return archivo.path;

    final bytes = await _api.postBytes(
      '/me/voice/tts',
      body: {'texto': texto},
      accept: 'audio/mpeg',
      timeout: const Duration(seconds: 60),
    );
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }

  /// Transcribe la grabación del micrófono para mandarla como pregunta.
  Future<String> transcribir(String rutaAudio) async {
    final j = await _api.upload(
      '/me/voice/stt',
      filePath: rutaAudio,
      field: 'audio',
      contentType: MediaType('audio', 'm4a'),
    );
    return '${(j as Map)['texto'] ?? ''}'.trim();
  }

  /// Borra los MP3 cacheados. Se llama al cerrar sesión: son respuestas
  /// sobre la salud de una persona y no tienen por qué sobrevivirla.
  Future<void> limpiarCache() async {
    try {
      final dir = _cacheDir ??= await getTemporaryDirectory();
      await for (final f in dir.list()) {
        if (f is File && f.path.contains('/moirai_') && f.path.endsWith('.mp3')) await f.delete();
      }
    } catch (_) {
      // Best-effort: no vale la pena molestar a nadie porque un temporal
      // no se pudo borrar.
    }
  }
}
