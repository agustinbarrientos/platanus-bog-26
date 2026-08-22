/// Respuesta de `GET/PATCH /me` (ver `apps/backend/API.md`).
/// El backend calcula el progreso (`answered`/`remaining`/`total`), la app no.
class Me {
  const Me({
    required this.email,
    required this.profile,
    required this.answered,
    required this.remaining,
    required this.total,
    required this.complete,
  });

  final String? email;
  final Profile profile;
  final List<String> answered;
  final List<String> remaining;
  final int total;
  final bool complete;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    email: j['email'] as String?,
    profile: Profile.fromJson((j['profile'] as Map?)?.cast<String, dynamic>() ?? const {}),
    answered: ((j['answered'] as List?) ?? const []).map((e) => '$e').toList(),
    remaining: ((j['remaining'] as List?) ?? const []).map((e) => '$e').toList(),
    total: (j['total'] as num?)?.toInt() ?? 0,
    complete: j['complete'] == true,
  );
}

/// `sex_at_birth`: el backend solo acepta "F" o "M".
enum SexAtBirth {
  female('F', 'Femenino'),
  male('M', 'Masculino');

  const SexAtBirth(this.api, this.label);
  final String api;
  final String label;

  static SexAtBirth? fromApi(String? v) {
    if (v == null) return null;
    final u = v.toUpperCase();
    if (u == 'F' || u == 'FEMALE') return SexAtBirth.female;
    if (u == 'M' || u == 'MALE') return SexAtBirth.male;
    return null;
  }

  /// Código de la spec §3 (`sexo_biologico`): "F" | "M".
  String get specCode => api;
}

const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Perfil del backend (`/me`): 6 campos. El resto del onboarding va a
/// `/me/health-context` (ver `OnboardingData`).
class Profile {
  const Profile({
    this.userId,
    this.fullName,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.bloodType,
    this.sexAtBirth,
    this.age,
  });

  final String? userId;
  final String? fullName;
  final DateTime? dateOfBirth;
  final double? heightCm;
  final double? weightKg;
  final String? bloodType;
  final SexAtBirth? sexAtBirth;
  final int? age;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    userId: j['user_id'] as String?,
    fullName: j['full_name'] as String?,
    dateOfBirth: j['date_of_birth'] == null ? null : DateTime.tryParse('${j['date_of_birth']}'),
    heightCm: (j['height_cm'] as num?)?.toDouble(),
    weightKg: (j['weight_kg'] as num?)?.toDouble(),
    bloodType: j['blood_type'] as String?,
    sexAtBirth: SexAtBirth.fromApi(j['sex_at_birth'] as String?),
    age: (j['age'] as num?)?.toInt(),
  );

  Profile copyWith({
    String? fullName,
    DateTime? dateOfBirth,
    double? heightCm,
    double? weightKg,
    String? bloodType,
    SexAtBirth? sexAtBirth,
    int? age,
  }) => Profile(
    userId: userId,
    fullName: fullName ?? this.fullName,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    bloodType: bloodType ?? this.bloodType,
    sexAtBirth: sexAtBirth ?? this.sexAtBirth,
    age: age ?? this.age,
  );

  /// Edad derivada localmente si el backend aún no la devolvió.
  int? get edad {
    if (age != null) return age;
    final d = dateOfBirth;
    if (d == null) return null;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  /// IMC a partir de estatura y peso (el backend lo acepta como biomarcador
  /// `imc`, fuente "calculado").
  double? get imc {
    final h = heightCm, w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100;
    return (w / (m * m) * 10).round() / 10;
  }
}
