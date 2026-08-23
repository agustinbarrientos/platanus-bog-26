import 'package:flutter_test/flutter_test.dart';
import 'package:moirai/data/models/onboarding.dart';
import 'package:moirai/data/repositories/profile_repository.dart';

/// Lo que el onboarding sube a `PATCH /me/health-context`
/// (`ProfileRepository.healthContextPatchFrom`): en particular el registro
/// del chat (`demografia.perfil_conocimiento`), que el backend valida con
/// vocabulario cerrado.
void main() {
  test('perfil_conocimiento viaja en demografia y sobrevive el ida y vuelta local', () {
    const d = OnboardingData(ancestria: 'mixta_latam', perfilConocimiento: 'curioso');
    final patch = ProfileRepository.healthContextPatchFrom(d);
    expect(patch['demografia'], {'ancestria_reportada': 'mixta_latam', 'perfil_conocimiento': 'curioso'});

    final otraVez = OnboardingData.fromJson(d.toJson());
    expect(otraVez.perfilConocimiento, 'curioso');
  });

  test('sin perfil (o con uno fuera del catálogo) no se manda nada que el backend rechace', () {
    expect(ProfileRepository.healthContextPatchFrom(const OnboardingData()).containsKey('demografia'), isFalse);
    final raro = ProfileRepository.healthContextPatchFrom(const OnboardingData(perfilConocimiento: 'experto'));
    expect(raro.containsKey('demografia'), isFalse);
    for (final v in Catalogos.perfilConocimiento.keys) {
      final p = ProfileRepository.healthContextPatchFrom(OnboardingData(perfilConocimiento: v));
      expect((p['demografia'] as Map)['perfil_conocimiento'], v);
    }
  });
}
