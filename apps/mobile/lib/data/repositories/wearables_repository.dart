import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../core/env.dart';
import '../api/api_client.dart';
import 'profile_repository.dart';

/// Por qué no se pudo conectar. Cada caso tiene una salida distinta, así que
/// no se colapsan todos en un `false`.
enum EstadoConexion {
  ok,

  /// El teléfono no tiene Health Connect (Android < 14 sin instalarlo).
  noDisponible,

  /// Está, pero el sistema pide actualizarlo antes de dar acceso.
  actualizarProveedor,

  /// El usuario dijo que no, o no marcó ningún permiso en la pantalla.
  permisoNegado,

  /// Falla técnica: plugin no registrado, plataforma sin soporte, etc.
  error,
}

class ResultadoConexion {
  const ResultadoConexion(this.estado, {this.detalle});
  final EstadoConexion estado;

  /// Texto crudo del error, solo para diagnóstico; nunca se le muestra tal cual.
  final String? detalle;

  bool get ok => estado == EstadoConexion.ok;

  /// Qué le digo al usuario, en primera persona y con la salida al lado.
  String mensaje(String proveedor) => switch (estado) {
    EstadoConexion.ok => '',
    EstadoConexion.noDisponible =>
      'Este teléfono todavía no tiene $proveedor, que es por donde leo el reloj o la pulsera. Puedo llevarte a instalarlo.',
    EstadoConexion.actualizarProveedor =>
      '$proveedor necesita una actualización antes de darme acceso. Puedo llevarte a la tienda.',
    EstadoConexion.permisoNegado =>
      'No me diste permiso de lectura en $proveedor. Ábrelo, busca Moirai y activa sueño, pasos, ejercicio y frecuencia cardiaca en reposo.',
    EstadoConexion.error =>
      'No pude hablar con $proveedor en este dispositivo. Puedes seguir sin esto: los datos del reloj afinan tus hábitos, no cambian el resultado.',
  };

  /// Si tiene sentido ofrecer el botón que abre la tienda.
  bool get puedeInstalar => estado == EstadoConexion.noDisponible || estado == EstadoConexion.actualizarProveedor;
}

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

  String get proveedorLabel => Platform.isIOS ? 'Salud' : 'Health Connect';

  Future<void> configure() async {
    try {
      await _health.configure();
    } catch (_) {}
  }

  /// Pide permisos de lectura. Cada falla dice por qué: "no me deja" sin razón
  /// no le sirve a nadie, y cada motivo se arregla distinto.
  Future<ResultadoConexion> conectar() async {
    try {
      await configure();
      if (Platform.isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        switch (status) {
          case HealthConnectSdkStatus.sdkUnavailable:
            return const ResultadoConexion(EstadoConexion.noDisponible);
          case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
            return const ResultadoConexion(EstadoConexion.actualizarProveedor);
          default:
            break;
        }
      }
      final perms = List.filled(_types.length, HealthDataAccess.READ);
      final ok = await _health.requestAuthorization(_types, permissions: perms);
      return ResultadoConexion(ok ? EstadoConexion.ok : EstadoConexion.permisoNegado);
    } catch (e) {
      // Si el plugin no quedó registrado (p. ej. la MainActivity no extiende
      // FlutterFragmentActivity) esto llega como MissingPluginException.
      return ResultadoConexion(EstadoConexion.error, detalle: e.toString());
    }
  }

  /// Manda al usuario a instalar/actualizar Health Connect desde la tienda.
  Future<void> instalarProveedor() async {
    try {
      await _health.installHealthConnect();
    } catch (_) {}
  }

  /// Últimos `dias` días agregados por día.
  ///
  /// Ojo con el doble conteo: a Health Connect le escriben varias apps a la
  /// vez (Fitbit, la de fábrica del teléfono, el sensor del propio celular) y
  /// la MISMA caminata queda registrada por cada una. Sumar los registros
  /// crudos multiplica los pasos por el número de apps —8.000 se vuelven
  /// 22.000—. `removeDuplicates` no salva: su `==` incluye `uuid` y
  /// `sourceId`, así que dos copias de la misma caminata nunca le parecen
  /// iguales.
  ///
  /// Por eso los pasos se piden con `getTotalStepsInInterval`, que por debajo
  /// usa la agregación de Health Connect (`StepsRecord.COUNT_TOTAL`) y
  /// resuelve los solapes con la lista de prioridad de apps del usuario: el
  /// mismo número que le muestra su app de salud. Sueño y ejercicio, que son
  /// intervalos, se unen en vez de sumarse, por la misma razón.
  Future<List<DiaWearable>> leer({int dias = 14}) async {
    final hoy = DateTime.now();
    final medianoche = DateTime(hoy.year, hoy.month, hoy.day);
    final start = medianoche.subtract(Duration(days: dias - 1));
    final out = <DiaWearable>[];
    try {
      final points = await _health.getHealthDataFromTypes(types: _types, startTime: start, endTime: hoy);
      for (var d = 0; d < dias; d++) {
        final day = start.add(Duration(days: d));
        final next = day.add(const Duration(days: 1));
        final fin = next.isAfter(hoy) ? hoy : next;

        // Pasos: agregado de la plataforma, no suma de registros crudos.
        int? pasos;
        try {
          final total = await _health.getTotalStepsInInterval(day, fin);
          if (total != null && total > 0) pasos = total;
        } catch (_) {}

        final delDia = points.where((p) => p.dateFrom.isBefore(fin) && p.dateTo.isAfter(day));
        final suenoMin = minutosUnidos(delDia.where((p) => p.type == HealthDataType.SLEEP_ASLEEP), day, fin);
        final ejercicioMin = minutosUnidos(delDia.where((p) => p.type == HealthDataType.WORKOUT), day, fin);
        final rhr = <double>[
          for (final p in delDia.where((p) => p.type == HealthDataType.RESTING_HEART_RATE))
            if (p.value case NumericHealthValue v) v.numericValue.toDouble(),
        ];

        out.add(DiaWearable(
          fecha: day,
          suenoH: suenoMin > 0 ? (suenoMin / 60 * 10).round() / 10 : null,
          pasos: pasos,
          minutosEjercicio: ejercicioMin > 0 ? ejercicioMin : null,
          fcReposo: rhr.isEmpty ? null : (rhr.reduce((a, b) => a + b) / rhr.length).round(),
        ));
      }
    } catch (_) {}
    return out;
  }

  /// Minutos cubiertos por [puntos] dentro de [desde]–[hasta], uniendo los
  /// intervalos que se solapan. Si Fitbit y el teléfono registran la misma
  /// noche, cuenta una sola vez; y recorta lo que cruza la medianoche para que
  /// no se sume entero en los dos días.
  @visibleForTesting
  static int minutosUnidos(Iterable<HealthDataPoint> puntos, DateTime desde, DateTime hasta) {
    final tramos = <(DateTime, DateTime)>[];
    for (final p in puntos) {
      final a = p.dateFrom.isBefore(desde) ? desde : p.dateFrom;
      final b = p.dateTo.isAfter(hasta) ? hasta : p.dateTo;
      if (b.isAfter(a)) tramos.add((a, b));
    }
    if (tramos.isEmpty) return 0;
    tramos.sort((x, y) => x.$1.compareTo(y.$1));
    var total = 0;
    var (ini, fin) = tramos.first;
    for (final (a, b) in tramos.skip(1)) {
      if (a.isAfter(fin)) {
        total += fin.difference(ini).inMinutes;
        ini = a;
        fin = b;
      } else if (b.isAfter(fin)) {
        fin = b;
      }
    }
    return total + fin.difference(ini).inMinutes;
  }

  /// Recalcula los hábitos en el dispositivo y los sube con
  /// `PATCH /me/health-context` (API_CONTRACT.md §4).
  ///
  /// No existe `POST /wearables/sincronizar`: el backend nunca lo implementó y
  /// llamarlo devolvía 404, que subía como excepción y se comía toda la
  /// conexión del reloj justo cuando SÍ había datos que leer.
  Future<Map<String, dynamic>> sincronizar(List<DiaWearable> dias) async {
    final conDatos = dias.where((d) => d.suenoH != null || d.pasos != null).toList();
    final habitos = _habitosLocales(conDatos);
    if (Env.useMockEngine || habitos.isEmpty) return habitos;

    // `habitos` se mezcla campo a campo en el backend, y `actividad` es el
    // nombre que espera (`ejercicio` es el vocabulario interno de la app).
    final patch = <String, dynamic>{
      if (habitos['sueno_h'] != null) 'sueno_h': habitos['sueno_h'],
      if (habitos['ejercicio'] != null) 'actividad': ProfileRepository.actividadDesde(habitos['ejercicio'] as String),
    };
    try {
      if (patch.isNotEmpty) await _api.patch('/me/health-context', body: {'habitos': patch});
    } catch (_) {
      // Leí el reloj de verdad: que no se pierda por un problema de red. El
      // onboarding y el perfil vuelven a sincronizar los hábitos después.
    }
    return habitos;
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
