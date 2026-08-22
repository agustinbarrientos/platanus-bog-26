/// Respuesta real de `GET/PATCH /me` del backend (ver `AUTH.md`).
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

enum SexAtBirth {
  female('female', 'Femenino'),
  male('male', 'Masculino'),
  intersex('intersex', 'Intersexual');

  const SexAtBirth(this.api, this.label);
  final String api;
  final String label;

  static SexAtBirth? fromApi(String? v) =>
      v == null ? null : SexAtBirth.values.where((e) => e.api == v).firstOrNull;

  /// Código de la spec §3 (`sexo_biologico`): "F" | "M".
  String get specCode => this == SexAtBirth.male ? 'M' : 'F';
}

const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Perfil tal como lo guarda el backend hoy (6 campos). El resto del
/// onboarding (objetivos, historial, hábitos, suplementos…) vive en
/// `OnboardingData` hasta que el backend lo acepte — ver `API_CONTRACT.md`.
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
}
