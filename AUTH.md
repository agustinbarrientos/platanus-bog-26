# Auth — what the Flutter app has to do

One rule: **the app talks to the API and nothing else.** No database client, no
Supabase SDK, no keys in the bundle. Supabase is where the API keeps its rows;
the app never hears about it.

```
Flutter  ──email + password──▶  FastAPI  ──▶  Postgres
         ◀──────  token  ───────
```

The whole scheme is one header:

```
Authorization: Bearer <token>
```

Sign in, store the token, send it on everything after that. There is no refresh
flow, no cookies, no CSRF header, and CORS does not apply to a native app.

Base URL:

- deployed: `https://platanus-bog-26.onrender.com`
- local: `http://localhost:8000` — on the Android emulator that is
  `http://10.0.2.2:8000`, since `localhost` there means the emulator itself

## Three things to know

**Store the token in the keychain**, not `SharedPreferences`.
`flutter_secure_storage` uses the iOS keychain and Android EncryptedSharedPrefs.
`SharedPreferences` is a plaintext file readable on a rooted device, and this
token opens someone's medical record.

**The token is shown exactly once.** Only a hash of it is stored server-side,
so it cannot be looked up again — if you lose it, the user signs in again.

**It lasts 90 days and is revocable.** No refresh logic to write. `POST
/auth/logout` kills it on the next request, so signing out actually signs out.

## The client

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  Api(this.baseUrl);
  final String baseUrl;
  final _storage = const FlutterSecureStorage();

  Future<String?> get _token => _storage.read(key: 'token');

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final token = auth ? await _token : null;
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 204) return null;

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      // `detail` is a string for our own errors and a list for validation
      // failures, so flatten both into something showable.
      final detail = decoded['detail'];
      throw ApiException(
        response.statusCode,
        detail is String ? detail : (detail as List).first['msg'] as String,
      );
    }
    return decoded as Map<String, dynamic>;
  }

  Future<void> _startSession(Map<String, dynamic> session) =>
      _storage.write(key: 'token', value: session['token'] as String);

  Future<void> signUp(String email, String password) async {
    final s = await _send('POST', '/auth/signup',
        body: {'email': email, 'password': password}, auth: false);
    await _startSession(s!);
  }

  Future<void> signIn(String email, String password) async {
    final s = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password}, auth: false);
    await _startSession(s!);
  }

  Future<void> signOut() async {
    try {
      await _send('POST', '/auth/logout');
    } on ApiException {
      // The token was already dead. Clearing it locally is the whole job.
    }
    await _storage.delete(key: 'token');
  }

  /// True when a stored token still works — what the splash screen asks before
  /// deciding between the login screen and the form.
  Future<bool> hasSession() async {
    if (await _token == null) return false;
    try {
      await _send('GET', '/auth/session');
      return true;
    } on ApiException {
      await _storage.delete(key: 'token');
      return false;
    }
  }

  Future<Map<String, dynamic>> me() async => (await _send('GET', '/me'))!;

  Future<Map<String, dynamic>> save(Map<String, dynamic> fields) async =>
      (await _send('PATCH', '/me', body: fields))!;
}
```

Using it:

```dart
final api = Api(const String.fromEnvironment('API_BASE_URL'));

await api.signUp('ana@moirai.test', 'una-clave-larga-123');

final me = await api.me();
final updated = await api.save({'weight_kg': 71.5});   // one field at a time
setState(() => progress = '${updated['answered'].length} de ${updated['total']}');
```

`http` is enough for this. `dio` is fine too — the only thing that matters is
that the `Authorization` header goes on every authenticated call, which is why
it belongs in one wrapper rather than at each call site.

Android needs `<uses-permission android:name="android.permission.INTERNET"/>`
in `AndroidManifest.xml`, and iOS needs nothing as long as the API is https.

## Endpoints

### Auth

| Route | Body | Auth | What it does |
| --- | --- | --- | --- |
| `POST /auth/signup` | `{email, password}` | — | Creates the account, returns a token, creates the profile row. `409` if the email is taken. |
| `POST /auth/login` | `{email, password}` | — | `401` on a wrong email *or* password, with the same message either way. |
| `GET /auth/session` | — | token | `200` + the user if the token is live, `401` if not. |
| `POST /auth/logout` | — | token | Kills this device's token. |
| `POST /auth/logout-all` | — | token | Kills every token on the account. |
| `POST /auth/password` | `{current_password, new_password}` | token | Changes it, signs out every device, returns a fresh token. |
| `POST /auth/delete-account` | `{password}` | token | Deletes the account, the profile, and every token. |

`signup`, `login` and `password` all return:

```json
{
  "user": { "id": "991d025c-…", "email": "ana@moirai.test", "created_at": "…" },
  "token": "IrX3Zq…",
  "token_type": "bearer",
  "expires_at": "2026-11-20T14:03:11Z"
}
```

### Profile

| Route | Auth | What it does |
| --- | --- | --- |
| `GET /me` | token | The user and their profile. |
| `PATCH /me` | token | Save any subset of the fields. Same response shape as `GET`. |
| `DELETE /me` | token | Erase the health data, keep the account. |
| `GET /health` | — | Liveness. Ping it before a demo to wake the instance. |

Every `/me` response carries `answered`, `remaining`, `total` and `complete`
alongside the profile, so the progress counter is computed server-side and
cannot drift from what is actually stored.

| Field | Type | Accepted |
| --- | --- | --- |
| `full_name` | string | 1–120 characters, trimmed |
| `date_of_birth` | string | `"1991-11-02"`, must give an age of 18–120 |
| `height_cm` | number | 100–250 |
| `weight_kg` | number | 25–350 |
| `blood_type` | enum | `A+` `A-` `B+` `B-` `AB+` `AB-` `O+` `O-` |
| `sex_at_birth` | enum | `female` `male` `intersex` |
| `age` | number | read-only, derived from `date_of_birth`, never send it |

`PATCH /me` is partial: `{"weight_kg": 74.2}` leaves every other field
untouched, and `{"blood_type": null}` clears that one field only. Anything
outside the ranges returns `422` with a per-field message you can show inline.
An unknown field name is also a `422` — the API rejects what it does not
recognise rather than silently dropping it.

## Status codes worth handling

| Code | Meaning | What to do |
| --- | --- | --- |
| `401` | No token, or it was revoked or expired | Clear the stored token, show the login screen |
| `409` | Email already registered | "Ya existe una cuenta con ese correo." |
| `422` | Validation | Show `detail` next to the field |
| `503` | Database unreachable | Retry; it is usually a cold Render instance |

Error messages come back in Spanish and are safe to show as they are.

## Two things that will bite

**The first request after idle takes 30–50 seconds.** Render's free tier sleeps
after about fifteen minutes. Do not block the splash screen on it — call
`GET /health` when the app opens and let the UI render meanwhile.

**`localhost` on the Android emulator is the emulator.** Use `10.0.2.2` to
reach your Mac. On a physical phone, use your machine's LAN IP and make sure
both are on the same network.

## Poking at it by hand

```bash
API=https://platanus-bog-26.onrender.com

TOKEN=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"ana@moirai.test","password":"una-clave-larga-123"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")

curl -s "$API/me" -H "Authorization: Bearer $TOKEN"
```

Live docs at `/docs` — click **Authorize** and paste the token with no `Bearer`
prefix.

## How it works, briefly

The token is 48 random bytes, stored server-side only as a SHA-256 and checked
against the database on every request. That costs one indexed row read and buys
the thing a self-contained token cannot give you: revocation that takes effect
immediately, so logging out, changing a password, or deleting an account all
stop working *now* rather than whenever a token would have expired.

Passwords are hashed with argon2id and never logged, returned, or forwarded. A
login for an unknown email costs the same time and returns the same message as
a wrong password, so the endpoint cannot be used to find out who has an account
— which for a health service is itself sensitive.
