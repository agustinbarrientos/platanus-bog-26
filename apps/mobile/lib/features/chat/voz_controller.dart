import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/providers.dart';
import '../../core/env.dart';
import '../../data/api/api_client.dart';

/// De dónde salió la voz que se está oyendo. Importa para el aviso: si es
/// del dispositivo, la persona merece saber por qué suena distinta.
enum VozFuente { remota, dispositivo }

/// Lo que la pantalla necesita saber para pintarse. `hablando` es el texto
/// exacto que se está leyendo, no un índice: el historial se reemplaza
/// entero en cada turno y un índice apuntaría a otra burbuja.
class VozEstado {
  const VozEstado({
    this.hablando,
    this.fuente = VozFuente.remota,
    this.preparando = false,
    this.grabando = false,
    this.transcribiendo = false,
    this.aviso,
  });

  final String? hablando;
  final VozFuente fuente;

  /// Sintetizando: ya se tocó el altavoz pero todavía no hay audio.
  final bool preparando;
  final bool grabando;
  final bool transcribiendo;

  /// Mensaje para la persona cuando algo no salió (sin micrófono, sin red).
  final String? aviso;

  bool get ocupado => preparando || transcribiendo;
  bool get leyendo => hablando != null;

  VozEstado copyWith({
    String? hablando,
    VozFuente? fuente,
    bool? preparando,
    bool? grabando,
    bool? transcribiendo,
    String? aviso,
    bool limpiarHablando = false,
    bool limpiarAviso = false,
  }) => VozEstado(
    hablando: limpiarHablando ? null : (hablando ?? this.hablando),
    fuente: fuente ?? this.fuente,
    preparando: preparando ?? this.preparando,
    grabando: grabando ?? this.grabando,
    transcribiendo: transcribiendo ?? this.transcribiendo,
    aviso: limpiarAviso ? null : (aviso ?? this.aviso),
  );
}

/// La voz de Moirai: leer respuestas en voz alta y escuchar preguntas.
///
/// Dos caminos para hablar, y la caída de uno al otro es silenciosa a
/// propósito:
///
/// - **Remoto** (`/me/voice/tts`, ElevenLabs detrás): la voz de Moirai.
/// - **Dispositivo** (`flutter_tts`): cuando no hay voz configurada en el
///   backend, cuando se acabaron los créditos (`402`) o cuando la app corre
///   en modo demo sin red (`USE_MOCK_ENGINE`). Suena a robot del sistema,
///   pero suena — y en una demo eso vale más que un mensaje de error.
///
/// Solo se cae en silencio por las causas *esperadas*. Un fallo real (sin
/// internet, backend caído) sí produce aviso: esconderlo haría creer que la
/// voz del sistema es la voz del producto.
class VozNotifier extends Notifier<VozEstado> {
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  final _rec = AudioRecorder();

  StreamSubscription<PlayerState>? _sub;
  bool _ttsListo = false;

  @override
  VozEstado build() {
    _sub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _terminar();
    });
    _tts.setCompletionHandler(_terminar);
    _tts.setCancelHandler(_terminar);

    ref.onDispose(() {
      _sub?.cancel();
      _player.dispose();
      _tts.stop();
      _rec.dispose();
    });
    return const VozEstado();
  }

  void _terminar() {
    if (state.leyendo || state.preparando) {
      state = state.copyWith(limpiarHablando: true, preparando: false);
    }
  }

  // ── Hablar ────────────────────────────────────────────────────────────

  /// Toca el altavoz de una respuesta: la lee, o la calla si ya la estaba
  /// leyendo. Nunca deja dos voces encimadas.
  Future<void> alternar(String texto) async {
    if (state.hablando == texto) return detener();
    await hablar(texto);
  }

  Future<void> hablar(String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    await detener();
    state = state.copyWith(hablando: t, preparando: true, limpiarAviso: true);

    if (Env.useMockEngine || !ref.read(vozDisponibleProvider)) {
      return _hablarLocal(t);
    }

    try {
      final ruta = await ref.read(voiceRepositoryProvider).audioDe(t);
      if (state.hablando != t) return; // lo cancelaron mientras sintetizaba
      state = state.copyWith(preparando: false, fuente: VozFuente.remota);
      await _player.setFilePath(ruta);
      await _player.play();
    } on ApiException catch (e) {
      // 402 sin créditos · 503 voz no configurada → la voz del sistema, sin
      // ruido. Cualquier otra cosa sí se cuenta.
      if (e.statusCode == 402 || e.statusCode == 503) return _hablarLocal(t);
      state = state.copyWith(limpiarHablando: true, preparando: false, aviso: e.message);
    } catch (_) {
      state = state.copyWith(
        limpiarHablando: true,
        preparando: false,
        aviso: 'No pude leerte esto en voz alta. Revisa tu conexión.',
      );
    }
  }

  Future<void> _hablarLocal(String texto) async {
    try {
      if (!_ttsListo) {
        // Español de la región más cercana que tenga instalada el teléfono.
        for (final l in ['es-CO', 'es-MX', 'es-US', 'es-ES', 'es']) {
          if (await _tts.isLanguageAvailable(l) == true) {
            await _tts.setLanguage(l);
            break;
          }
        }
        await _tts.setSpeechRate(0.5);
        await _tts.setPitch(1.05);
        _ttsListo = true;
      }
      state = state.copyWith(preparando: false, fuente: VozFuente.dispositivo);
      await _tts.speak(texto);
    } catch (_) {
      state = state.copyWith(
        limpiarHablando: true,
        preparando: false,
        aviso: 'Este teléfono no tiene una voz en español instalada.',
      );
    }
  }

  Future<void> detener() async {
    if (!state.leyendo && !state.preparando) return;
    state = state.copyWith(limpiarHablando: true, preparando: false);
    await _player.stop();
    await _tts.stop();
  }

  // ── Escuchar ──────────────────────────────────────────────────────────

  /// Empieza a grabar. `false` si no hay permiso de micrófono — el aviso ya
  /// quedó en el estado.
  Future<bool> grabar() async {
    if (state.grabando) return true;
    try {
      if (!await _rec.hasPermission()) {
        state = state.copyWith(aviso: 'Necesito permiso para usar el micrófono y poder escucharte.');
        return false;
      }
      await detener();
      final dir = await getTemporaryDirectory();
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, noiseSuppress: true),
        // Se sobrescribe en cada grabación: nunca queda más de una en disco.
        path: '${dir.path}/moirai_pregunta.m4a',
      );
      state = state.copyWith(grabando: true, limpiarAviso: true);
      return true;
    } catch (_) {
      state = state.copyWith(grabando: false, aviso: 'No pude encender el micrófono.');
      return false;
    }
  }

  /// Corta la grabación y la transcribe. Devuelve la pregunta, o `null` si
  /// no se entendió nada o falló.
  Future<String?> detenerYTranscribir() async {
    if (!state.grabando) return null;
    String? ruta;
    try {
      ruta = await _rec.stop();
    } catch (_) {
      ruta = null;
    }
    state = state.copyWith(grabando: false);
    if (ruta == null) return null;

    state = state.copyWith(transcribiendo: true);
    try {
      final texto = await ref.read(voiceRepositoryProvider).transcribir(ruta);
      state = state.copyWith(transcribiendo: false);
      if (texto.isEmpty) {
        state = state.copyWith(aviso: 'No alcancé a escucharte. Prueba otra vez, un poco más cerca.');
        return null;
      }
      return texto;
    } on ApiException catch (e) {
      state = state.copyWith(transcribiendo: false, aviso: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(transcribiendo: false, aviso: 'No pude entender lo que dijiste. ¿Tienes internet?');
      return null;
    }
  }

  /// Descarta la grabación en curso (el usuario soltó fuera del botón).
  Future<void> cancelarGrabacion() async {
    if (!state.grabando) return;
    try {
      await _rec.cancel();
    } catch (_) {
      // El archivo temporal se sobrescribe en la próxima grabación.
    }
    state = state.copyWith(grabando: false);
  }

  void limpiarAviso() => state = state.copyWith(limpiarAviso: true);
}

final vozProvider = NotifierProvider<VozNotifier, VozEstado>(VozNotifier.new);
