import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/env.dart';
import 'token_store.dart';

/// Error de API con un mensaje listo para mostrar. El backend responde
/// `{"detail": "mensaje en español"}` para todo lo que rechaza a propósito y
/// la lista estructurada de FastAPI para fallos de validación (422).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fields = const {}});

  final int statusCode;
  final String message;

  /// Errores por campo en un 422 de validación: `{ "weight_kg": "..." }`.
  final Map<String, String> fields;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Única puerta hacia el backend. Manda `Authorization: Bearer <token>` con
/// el token de `/auth/login` guardado en [TokenStore]. Ver `apps/backend/API.md`.
class ApiClient {
  ApiClient(this._tokens, {http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      baseUrl = baseUrl ?? Env.apiBaseUrl;

  final TokenStore _tokens;
  final http.Client _http;
  final String baseUrl;

  /// Se invoca cuando el backend responde 401 con un token guardado: la
  /// sesión fue revocada o venció → cerrar sesión localmente.
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({bool auth = true, bool json = true}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (auth) {
      final t = _tokens.token;
      if (t == null) throw ApiException(401, 'No hay sesión activa.');
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  static const _timeout = Duration(seconds: 90);

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) async {
    final res = await _http.get(_uri(path, query), headers: _headers(auth: auth)).timeout(_timeout);
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body, bool auth = true, Duration? timeout}) async {
    final res = await _http
        .post(_uri(path), headers: _headers(auth: auth), body: body == null ? null : jsonEncode(body))
        .timeout(timeout ?? _timeout);
    return _decode(res);
  }

  /// POST que devuelve bytes (p. ej. el PDF de `/me/health-context/reporte.pdf`).
  /// Un error del backend llega como JSON `{"detail": …}` y se traduce igual
  /// que en los demás métodos.
  Future<Uint8List> postBytes(String path, {Object? body, String accept = 'application/octet-stream', Duration? timeout}) async {
    final headers = _headers()..['Accept'] = accept;
    final res = await _http
        .post(_uri(path), headers: headers, body: body == null ? null : jsonEncode(body))
        .timeout(timeout ?? _timeout);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    _decode(res); // lanza ApiException con el mensaje del backend
    throw ApiException(res.statusCode, 'No pude generar el archivo. Intenta de nuevo.');
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final res = await _http.patch(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)).timeout(_timeout);
    return _decode(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _http.put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)).timeout(_timeout);
    return _decode(res);
  }

  Future<void> delete(String path) async {
    final res = await _http.delete(_uri(path), headers: _headers()).timeout(_timeout);
    _decode(res);
  }

  /// Multipart con un solo archivo. El backend espera un `Content-Type` real
  /// (pdf/png/jpeg/webp) — lo inferimos de la extensión salvo que se pase
  /// [contentType] (el audio del micrófono lo hace: `/me/voice/stt` rechaza
  /// con 415 lo que no declare ser audio).
  Future<dynamic> upload(String path, {required String filePath, String field = 'file', MediaType? contentType}) async {
    final req = http.MultipartRequest('POST', _uri(path));
    req.headers.addAll(_headers(json: false));
    req.files.add(await http.MultipartFile.fromPath(field, filePath, contentType: contentType ?? _mediaType(filePath)));
    final streamed = await _http.send(req).timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  static MediaType _mediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => MediaType('application', 'pdf'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'jpg' || 'jpeg' || 'heic' || 'heif' => MediaType('image', 'jpeg'),
      _ => MediaType('image', 'jpeg'),
    };
  }

  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic body;
    if (res.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        body = res.body;
      }
    }
    if (ok) return body;

    var message = 'Algo no salió como esperaba. Intenta de nuevo en un momento.';
    final fields = <String, String>{};
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List) {
        // FastAPI 422: [{loc: [body, weight_kg], msg: ...}]
        for (final e in detail) {
          if (e is Map) {
            final loc = (e['loc'] as List?)?.map((x) => '$x').toList() ?? const [];
            final field = loc.isNotEmpty ? loc.last : '';
            final msg = '${e['msg'] ?? ''}'.replaceFirst(RegExp(r'^Value error, '), '');
            if (field.isNotEmpty) fields[field] = msg;
          }
        }
        if (fields.isNotEmpty) message = fields.values.first;
      }
    } else if (res.statusCode == 401) {
      message = 'Tu sesión venció. Vuelve a entrar.';
    } else if (res.statusCode == 429) {
      message = 'Estoy respondiendo muchas preguntas a la vez. Dame unos segundos.';
    } else if (res.statusCode == 503) {
      message = 'Mi parte pensante no está disponible en este momento. Intenta más tarde.';
    } else if (res.statusCode >= 500) {
      message = 'El servidor está despertando. Dame unos segundos y vuelve a intentar.';
    }
    if (res.statusCode == 401 && _tokens.token != null) onUnauthorized?.call();
    throw ApiException(res.statusCode, message, fields: fields);
  }
}
