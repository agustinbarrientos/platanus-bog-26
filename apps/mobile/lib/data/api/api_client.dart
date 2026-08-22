import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';

/// Error de API con un mensaje listo para mostrar (viene del `detail` del
/// backend, que debe estar en español y en tono amable).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fields = const {}});

  final int statusCode;
  final String message;

  /// Errores por campo en un 422 de FastAPI: `{ "weight_kg": "..." }`.
  final Map<String, String> fields;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Única puerta hacia el backend. Lee el token de Supabase **en cada request**
/// (se refresca solo cada hora) y lo manda como `Authorization: Bearer`.
/// Ver `AUTH.md` y `API_CONTRACT.md`.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      baseUrl = baseUrl ?? Env.apiBaseUrl;

  final http.Client _http;
  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers({bool auth = true, bool json = true}) async {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (auth) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw ApiException(401, 'No hay sesión activa.');
      h['Authorization'] = 'Bearer ${session.accessToken}';
    }
    return h;
  }

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) async {
    final res = await _http.get(_uri(path, query), headers: await _headers(auth: auth));
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body, bool auth = true}) async {
    final res = await _http.post(
      _uri(path),
      headers: await _headers(auth: auth),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final res = await _http.patch(
      _uri(path),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _http.put(
      _uri(path),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<void> delete(String path) async {
    final res = await _http.delete(_uri(path), headers: await _headers());
    _decode(res);
  }

  /// Multipart con un solo archivo en el campo `archivo`.
  Future<dynamic> upload(String path, {required String filePath, String field = 'archivo'}) async {
    final req = http.MultipartRequest('POST', _uri(path));
    req.headers.addAll(await _headers(json: false));
    req.files.add(await http.MultipartFile.fromPath(field, filePath));
    final streamed = await _http.send(req).timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic body;
    if (res.body.isNotEmpty) {
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
    } else if (res.statusCode >= 500) {
      message = 'El servidor está despertando. Dame unos segundos y vuelve a intentar.';
    }
    throw ApiException(res.statusCode, message, fields: fields);
  }
}
