import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moirai/data/api/api_client.dart';
import 'package:moirai/data/api/token_store.dart';
import 'package:moirai/data/models/voz.dart';
import 'package:moirai/data/repositories/voice_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// La capa de voz vista desde la app: qué se le pide al backend, qué se
/// cachea y qué pasa cuando no puede hablar. Sin plugins de audio — lo que
/// se prueba aquí es el contrato con `/me/voice`, que es lo que se rompe en
/// silencio.
class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;

  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('moirai_voz_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<VoiceRepository> repo(MockClient client) async {
    final tokens = TokenStore();
    await tokens.save(token: 'tok', userId: 'u1', email: 'a@b.co');
    return VoiceRepository(ApiClient(tokens, client: client, baseUrl: 'http://x'));
  }

  // ── EstadoVoz ───────────────────────────────────────────────────────────

  test('EstadoVoz se arma del JSON del backend', () {
    final e = EstadoVoz.fromJson({
      'disponible': true,
      'modelo_tts': 'eleven_flash_v2_5',
      'modelo_stt': 'scribe_v2',
      'max_caracteres': 1500,
    });
    expect(e.disponible, isTrue);
    expect(e.modeloTts, 'eleven_flash_v2_5');
    expect(e.maxCaracteres, 1500);
  });

  test('EstadoVoz tolera un backend viejo que no manda los campos', () {
    final e = EstadoVoz.fromJson({});
    expect(e.disponible, isFalse);
    expect(e.maxCaracteres, 0);
  });

  test('EstadoVoz.nula no está disponible', () {
    expect(EstadoVoz.nula.disponible, isFalse);
  });

  // ── estado() ────────────────────────────────────────────────────────────

  test('estado() lee /me/voice/estado', () async {
    String? path;
    final r = await repo(MockClient((req) async {
      path = req.url.path;
      return http.Response(
        jsonEncode({'disponible': true, 'modelo_tts': 'eleven_flash_v2_5', 'modelo_stt': 'scribe_v2', 'max_caracteres': 1500}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final e = await r.estado();
    expect(path, '/me/voice/estado');
    expect(e.disponible, isTrue);
  });

  test('estado() cae a nula si el backend no responde (nunca lanza)', () async {
    final r = await repo(MockClient((_) async => http.Response('{"detail":"boom"}', 500)));
    expect((await r.estado()).disponible, isFalse);

    final sinRed = await repo(MockClient((_) async => throw const SocketException('sin red')));
    expect((await sinRed.estado()).disponible, isFalse);
  });

  // ── audioDe() ───────────────────────────────────────────────────────────

  test('audioDe pide el MP3 con el texto tal cual y lo guarda', () async {
    Map<String, dynamic>? body;
    String? accept;
    final r = await repo(MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      accept = req.headers['Accept'];
      return http.Response.bytes([0x49, 0x44, 0x33, 0x04], 200);
    }));

    final ruta = await r.audioDe('Ejercicio es tu palanca #1: +2,4 años.');

    // El texto va sin tocar: la normalización para voz la hace el backend.
    expect(body!['texto'], 'Ejercicio es tu palanca #1: +2,4 años.');
    expect(accept, 'audio/mpeg');
    expect(File(ruta).existsSync(), isTrue);
    expect(await File(ruta).length(), 4);
  });

  test('audioDe no vuelve a sintetizar el mismo texto (cachea = no gasta créditos)', () async {
    var llamadas = 0;
    final r = await repo(MockClient((_) async {
      llamadas++;
      return http.Response.bytes([1, 2, 3], 200);
    }));

    final a = await r.audioDe('la misma respuesta');
    final b = await r.audioDe('la misma respuesta');

    expect(llamadas, 1);
    expect(a, b);
  });

  test('audioDe sí sintetiza dos textos distintos', () async {
    var llamadas = 0;
    final r = await repo(MockClient((_) async {
      llamadas++;
      return http.Response.bytes([1], 200);
    }));

    final a = await r.audioDe('una respuesta');
    final b = await r.audioDe('otra respuesta');

    expect(llamadas, 2);
    expect(a, isNot(b));
  });

  test('audioDe propaga el 402 para que la app caiga a la voz del teléfono', () async {
    final r = await repo(MockClient((_) async => http.Response(
          jsonEncode({'detail': 'se acabaron los créditos de voz'}),
          402,
          headers: {'content-type': 'application/json'},
        )));

    expect(
      () => r.audioDe('hola'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 402)),
    );
  });

  test('un MP3 vacío en caché no se reusa: se vuelve a pedir', () async {
    var llamadas = 0;
    final r = await repo(MockClient((_) async {
      llamadas++;
      return http.Response.bytes([9, 9], 200);
    }));

    final ruta = await r.audioDe('respuesta');
    await File(ruta).writeAsBytes([]); // síntesis interrumpida a medias
    await r.audioDe('respuesta');

    expect(llamadas, 2);
  });

  // ── transcribir() ───────────────────────────────────────────────────────

  test('transcribir manda el audio a /me/voice/stt y devuelve la pregunta', () async {
    String? path;
    String? cuerpo;
    final r = await repo(MockClient((req) async {
      path = req.url.path;
      cuerpo = utf8.decode(req.bodyBytes, allowMalformed: true);
      return http.Response(
        jsonEncode({'texto': '  ¿Por qué el ejercicio?  ', 'idioma': 'spa', 'confianza_idioma': 0.98}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final audio = File('${tmp.path}/pregunta.m4a')..writeAsBytesSync([0, 1, 2, 3]);
    final texto = await r.transcribir(audio.path);

    expect(path, '/me/voice/stt');
    expect(texto, '¿Por qué el ejercicio?');
    // El campo se llama `audio` y va declarado como audio: el backend
    // responde 415 a cualquier otra cosa.
    expect(cuerpo, contains('name="audio"'));
    expect(cuerpo, contains('audio/m4a'));
  });

  // ── limpiarCache() ──────────────────────────────────────────────────────

  test('limpiarCache borra los MP3 y deja lo demás en paz', () async {
    final r = await repo(MockClient((_) async => http.Response.bytes([7], 200)));
    final ruta = await r.audioDe('algo que dije');
    final ajeno = File('${tmp.path}/otra_cosa.txt')..writeAsStringSync('no es mío');

    await r.limpiarCache();

    expect(File(ruta).existsSync(), isFalse);
    expect(ajeno.existsSync(), isTrue);
  });
}
