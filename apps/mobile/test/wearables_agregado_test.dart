import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:moirai/data/repositories/wearables_repository.dart';

/// El bug que originó esto: a Health Connect le escriben varias apps y la
/// misma noche/caminata queda registrada por cada una. Sumar duraciones
/// multiplicaba el resultado por el número de fuentes.
HealthDataPoint punto(DateTime de, DateTime a) => HealthDataPoint(
  uuid: '$de-$a',
  value: NumericHealthValue(numericValue: 1),
  type: HealthDataType.SLEEP_ASLEEP,
  unit: HealthDataUnit.MINUTE,
  dateFrom: de,
  dateTo: a,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: 'd',
  sourceId: 's',
  sourceName: 'n',
);

void main() {
  final dia = DateTime(2026, 8, 22);
  final finDia = dia.add(const Duration(days: 1));

  test('un solo tramo cuenta sus minutos', () {
    final r = WearablesRepository.minutosUnidos(
      [punto(dia.add(const Duration(hours: 1)), dia.add(const Duration(hours: 7)))],
      dia,
      finDia,
    );
    expect(r, 360);
  });

  test('dos apps que registran la misma noche no la duplican', () {
    final de = dia.add(const Duration(hours: 1));
    final a = dia.add(const Duration(hours: 7));
    final r = WearablesRepository.minutosUnidos([punto(de, a), punto(de, a)], dia, finDia);
    expect(r, 360, reason: 'la misma noche vista por dos fuentes son 6 h, no 12');
  });

  test('tramos que se solapan parcialmente se unen', () {
    final r = WearablesRepository.minutosUnidos([
      punto(dia.add(const Duration(hours: 1)), dia.add(const Duration(hours: 5))),
      punto(dia.add(const Duration(hours: 4)), dia.add(const Duration(hours: 7))),
    ], dia, finDia);
    expect(r, 360, reason: '01:00–07:00 con un solape de una hora');
  });

  test('tramos separados sí se suman', () {
    final r = WearablesRepository.minutosUnidos([
      punto(dia.add(const Duration(hours: 1)), dia.add(const Duration(hours: 3))),
      punto(dia.add(const Duration(hours: 5)), dia.add(const Duration(hours: 6))),
    ], dia, finDia);
    expect(r, 180);
  });

  test('lo que cruza la medianoche se recorta al día', () {
    // 22:00 del día anterior a 06:00 de este: al día solo le tocan 6 h.
    final r = WearablesRepository.minutosUnidos(
      [punto(dia.subtract(const Duration(hours: 2)), dia.add(const Duration(hours: 6)))],
      dia,
      finDia,
    );
    expect(r, 360, reason: 'antes se contaba entero en los dos días');
  });

  test('sin datos son cero minutos, no un error', () {
    expect(WearablesRepository.minutosUnidos([], dia, finDia), 0);
  });
}
