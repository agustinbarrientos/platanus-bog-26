import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moirai/data/api/api_client.dart';
import 'package:moirai/data/api/token_store.dart';
import 'package:moirai/data/repositories/auth_repository.dart';

/// Cerrar sesión no puede depender de la red: la sesión local se borra de
/// inmediato y la revocación va en segundo plano con el token que había.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TokenStore> conSesion() async {
    final t = TokenStore();
    await t.save(token: 'tok-123', userId: 'u1', email: 'a@b.co');
    return t;
  }

  test('borra la sesión local sin esperar al backend y manda el token al revocar', () async {
    final tokens = await conSesion();
    final completer = Completer<http.Response>();
    String? authHeader;
    final client = MockClient((req) {
      authHeader = req.headers['Authorization'];
      return completer.future; // el backend "nunca" responde (cold start)
    });
    final repo = AuthRepository(ApiClient(tokens, client: client, baseUrl: 'http://x'), tokens);

    await repo.signOut().timeout(const Duration(seconds: 2));

    expect(tokens.hasSession, isFalse);
    expect(tokens.token, isNull);
    expect(authHeader, 'Bearer tok-123');
    completer.complete(http.Response('', 204));
  });

  test('si el backend falla igual queda cerrada la sesión', () async {
    final tokens = await conSesion();
    final client = MockClient((_) async => http.Response('{"detail":"boom"}', 500));
    final repo = AuthRepository(ApiClient(tokens, client: client, baseUrl: 'http://x'), tokens);

    await repo.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(tokens.hasSession, isFalse);
  });
}
