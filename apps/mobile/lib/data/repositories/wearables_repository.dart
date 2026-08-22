import 'dart:io';

import 'package:health/health.dart';

import '../../core/env.dart';
import '../api/api_client.dart';

/// Resumen diario que la app agrega localmente y manda a
/// `POST /wearables/sincronizar` (API_CONTRACT.md §4).
class DiaWearable {
  const DiaWearable({required this.fecha, this.suenoH, this.pasos, this.minutosEjercicio, this.fcReposo});
  final DateTime fecha;
  final double? suenoH;
  final int? pasos;
  final int? minutosEjercicio;
  final int? fcReposo;

  Map<String, dynamic> toJson() => {
    'fecha': '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}',
    'sueno_h': suenoH,
    'pasos': pasos,
    'minutos_ejercicio': minutosEjercicio,
    'fc_reposo': fcReposo,
  };
}

/// Lee Health Connect (Android) / HealthKit (iOS) con el paquete `health`.
/// Cualquier reloj o pulsera que sincronice con esas plataformas (Samsung,
/// Garmin, Fitbit, Xiaomi, Apple Watch, Oura…) llega por aquí sin OAuth ni
/// SDKs de terceros.
class WearablesRepository {
  WearablesRepository(this._api);
  final ApiClient _api;
  final _health = Health();

  static const _types = <HealthDataType>[
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.STEPS,
    HealthDataType.WORKOUT,
    HealthDataType.RESTING_HEART_RATE,
  ];

  String get proveedor => Platform.isIOS ? 'healthkit' : 'health_connect';

  Future<void> configure() async {
    try {
      await _health.configure();
    } catch (_) {}
  }

  /// Pide permisos de lectura. Devuelve `false` si el usuario los niega o si la
  /// plataforma no tiene Health Connect instalado.
  Future<bool> conectar() async {
    try {
      await configure();
      if (Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        if (status != HealthConnectSdkStatus.sdkAvailable) {
          await _health.installHealthConnect();
          return false;
        }
      }
      final perms = List.filled(_types.length, HealthDataAccess.READ);
      return await _health.requestAuthorization(_types, permissions: perms);
    } catch (_) {
      return false;
    }
  }

  /// Últimos `dias` días agregados por día.
  Future<List<DiaWearable>> leer({int dias = 14}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: dias));
    final out = <DiaWearable>[];
    try {
      final points = await _health.getHealthDataFromTypes(types: _types, startTime: start, endTime: now);
      final clean = _health.removeDuplicates(points);
      for (var d = 0; d < dias; d++) {
        final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: dias - 1 - d));
        final next = day.add(const Duration(days: 1));
        bool inDay(HealthDataPoint p) => p.dateFrom.isBefore(next) && p.dateTo.isAfter(day);
        double sleepMin = 0;
        int steps = 0;
        int workoutMin = 0;
        final rhr = <double>[];
        for (final p in clean.where(inDay)) {
          final v = p.value;
          switch (p.type) {
            case HealthDataType.SLEEP_ASLEEP:
              sleepMin += p.dateTo.difference(p.dateFrom).inMinutes;
            case HealthDataType.STEPS:
              if (v is NumericHealthValue) steps += v.numericValue.round();
            case HealthDataType.WORKOUT:
              workoutMin += p.dateTo.difference(p.dateFrom).inMinutes;
            case HealthDataType.RESTING_HEART_RATE:
              if (v is NumericHealthValue) rhr.add(v.numericValue.toDouble());
            default:
              break;
          }
        }
        out.add(DiaWearable(
          fecha: day,
          suenoH: sleepMin > 0 ? (sleepMin / 60 * 10).round() / 10 : null,
          pasos: steps > 0 ? steps : null,
          minutosEjercicio: workoutMin > 0 ? workoutMin : null,
          fcReposo: rhr.isEmpty ? null : (rhr.reduce((a, b) => a + b) / rhr.length).round(),
        ));
      }
    } catch (_) {}
    return out;
  }

  /// Manda los agregados al backend y devuelve los hábitos recalculados (o un
  /// cálculo local si el endpoint aún no existe).
  Future<Map<String, dynamic>> sincronizar(List<DiaWearable> dias) async {
    final conDatos = dias.where((d) => d.suenoH != null || d.pasos != null).toList();
    if (Env.useMockEngine || conDatos.isEmpty) {
      return _habitosLocales(conDatos);
    }
    final j = (await _api.post('/wearables/sincronizar', body: {
      'proveedor': proveedor,
      'dias': dias.map((d) => d.toJson()).toList(),
    }) as Map)
        .cast<String, dynamic>();
    return (j['habitos_actualizados'] as Map?)?.cast<String, dynamic>() ?? _habitosLocales(conDatos);
  }

  Map<String, dynamic> _habitosLocales(List<DiaWearable> dias) {
    final sue = dias.map((d) => d.suenoH).whereType<double>().toList();
    final ej = dias.map((d) => d.minutosEjercicio).whereType<int>().toList();
    final pasos = dias.map((d) => d.pasos).whereType<int>().toList();
    final out = <String, dynamic>{};
    if (sue.isNotEmpty) out['sueno_h'] = (sue.reduce((a, b) => a + b) / sue.length * 10).round() / 10;
    final minSem = ej.isEmpty ? 0 : ej.reduce((a, b) => a + b) / (dias.length / 7);
    final pasosProm = pasos.isEmpty ? 0 : pasos.reduce((a, b) => a + b) / pasos.length;
    if (ej.isNotEmpty || pasos.isNotEmpty) {
      out['ejercicio'] = minSem >= 300 || pasosProm >= 12000
          ? 'alto'
          : minSem >= 150 || pasosProm >= 8000
              ? 'moderado'
              : minSem >= 40 || pasosProm >= 4000
                  ? 'bajo'
                  : 'nulo';
    }
    return out;
  }
}
