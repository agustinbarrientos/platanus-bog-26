import '../../core/env.dart';
import '../api/api_client.dart';
import '../models/biomarcador.dart';
import 'demo_data.dart';

/// Lectura de exámenes (`POST /examenes/extraer`). Mientras el backend no lo
/// tenga, devuelve la lectura del examen demo con una latencia creíble.
class ExamsRepository {
  ExamsRepository(this._api);
  final ApiClient _api;

  Future<({List<Biomarcador> biomarcadores, List<String> noEncontrados, String? fechaExamen})> extraer(String filePath) async {
    if (Env.useMockEngine) {
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final leidos = DemoData.lecturaExamen();
      final ids = leidos.map((b) => b.nombre).toSet();
      return (
        biomarcadores: leidos,
        noEncontrados: BiomarcadorDef.all.map((d) => d.id).where((id) => !ids.contains(id)).toList(),
        fechaExamen: '2026-07',
      );
    }
    final j = (await _api.upload('/examenes/extraer', filePath: filePath) as Map).cast<String, dynamic>();
    return (
      biomarcadores: ((j['biomarcadores'] as List?) ?? const [])
          .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      noEncontrados: ((j['no_encontrados'] as List?) ?? const []).map((e) => '$e').toList(),
      fechaExamen: j['fecha_examen'] as String?,
    );
  }
}
