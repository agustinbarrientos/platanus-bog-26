import '../../core/env.dart';
import '../api/api_client.dart';
import '../models/biomarcador.dart';
import 'demo_data.dart';

/// Resultado de leer un examen. `biomarcadores` = lo que quedó guardado en el
/// backend tras esta lectura (merge por nombre); `leidos` = lo extraído en esta
/// llamada; `advertencias` = valores que Claude vio pero no pasaron validación.
typedef LecturaExamen = ({
  List<Biomarcador> biomarcadores,
  List<Biomarcador> leidos,
  List<String> noEncontrados,
  List<String> advertencias,
  String? fechaExamen,
  String? notas,
});

/// `POST /me/health-context/biomarkers/extract` (multipart `file`): Claude
/// (haiku) lee el PDF/foto, el backend valida unidades/rangos y **guarda**
/// directamente en health-context. Con `USE_MOCK_ENGINE` devuelve el examen
/// demo tras una latencia creíble.
class ExamsRepository {
  ExamsRepository(this._api);
  final ApiClient _api;

  Future<LecturaExamen> extraer(String filePath) async {
    if (Env.useMockEngine) {
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final leidos = DemoData.lecturaExamen();
      return (
        biomarcadores: leidos,
        leidos: leidos,
        noEncontrados: _faltantes(leidos),
        advertencias: const <String>[],
        fechaExamen: '2026-07',
        notas: null,
      );
    }
    final j = (await _api.upload('/me/health-context/biomarkers/extract', filePath: filePath, field: 'file') as Map).cast<String, dynamic>();
    List<Biomarcador> parse(String k, {String confianza = 'alta'}) => ((j[k] as List?) ?? const [])
        .map((e) => Biomarcador.fromJson((e as Map).cast<String, dynamic>()).copyWith(confianza: confianza))
        .toList();
    final guardados = parse('guardados');
    final todos = parse('biomarcadores');
    final advert = ((j['advertencias'] as List?) ?? const []).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final def = BiomarcadorDef.byId('${m['nombre']}');
      return '${def?.nombre ?? m['nombre']}: leí ${m['valor_reportado']} ${m['unidad_reportada']} pero no lo guardé (${m['razon']}).';
    }).toList();
    return (
      biomarcadores: todos,
      leidos: guardados,
      noEncontrados: _faltantes(todos),
      advertencias: advert,
      fechaExamen: null,
      notas: j['notas'] as String?,
    );
  }

  static List<String> _faltantes(List<Biomarcador> tengo) {
    final ids = tengo.map((b) => b.nombre).toSet();
    return BiomarcadorDef.phenoAgeDefs.map((d) => d.id).where((id) => !ids.contains(id)).toList();
  }
}
