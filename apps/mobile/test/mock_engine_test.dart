import 'package:flutter_test/flutter_test.dart';
import 'package:moirai/data/mock/mock_engine.dart';
import 'package:moirai/data/repositories/demo_data.dart';

/// Tests de la spec §9 sobre el motor mock (mismos invariantes que el backend
/// debe cumplir): edad biológica plausible, signos correctos, abanico que se
/// ensancha, mejor decisión con mayor ratio.
void main() {
  final perfil = DemoData.perfil();

  test('Capa 1: PhenoAge del caso de prueba cae en rango plausible (20–50)', () {
    final (estado, _, faltantes) = MockEngine.preparar(perfil.biomarcadores);
    final pa = MockEngine.phenoAge(estado, 34);
    expect(faltantes, containsAll(['linfocitos_pct', 'vcm', 'fosfatasa_alcalina']));
    expect(pa, inInclusiveRange(20, 50));
  });

  test('Capa 2+3: sin intervención envejece más que con buenas intervenciones; el abanico se ensancha', () async {
    final engine = MockEngine(n: 120);
    final progreso = await engine.simular(perfil).last;
    final r = progreso.resultado!;
    expect(r.baseline.mediana.last, greaterThan(r.baseline.mediana.first));
    final ancho0 = r.baseline.p90.first - r.baseline.p10.first;
    final anchoN = r.baseline.p90.last - r.baseline.p10.last;
    expect(anchoN, greaterThan(ancho0));
    expect(r.escenarios, isNotEmpty);
    expect(r.mejorDecision.aniosGanados, greaterThan(0));
    // Ranking por ratio.
    for (var i = 1; i < r.escenarios.length; i++) {
      expect(r.escenarios[i - 1].ratio, greaterThanOrEqualTo(r.escenarios[i].ratio));
    }
    // Máximo 3 intervenciones por combo (spec §12).
    expect(r.escenarios.every((e) => e.intervenciones.length <= 3), isTrue);
    // Output bien formado (spec §8).
    final json = r.toJson();
    expect(json['edad_biologica_hoy'], isA<num>());
    expect((json['trayectoria_baseline'] as Map)['mediana'], hasLength(11));
    expect(json['descargo'], contains('no diagnóstico'));
  });
}
