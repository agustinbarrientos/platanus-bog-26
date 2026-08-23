import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/env.dart';
import '../api/api_client.dart';
import '../models/reporte.dart';

/// El reporte de salud orientativo del backend (`/me/health-context/reporte`
/// en JSON para la pantalla "Tu reporte", `/reporte.pdf` para descargarlo).
/// Siempre sin cuerpo: el backend recalcula con los defaults del motor, que
/// son los mismos que usó la simulación, así el PDF coincide con lo que la
/// persona vio. Nada se guarda en el servidor; el PDF va al directorio
/// temporal del dispositivo solo para abrir la hoja de compartir.
class ReportRepository {
  ReportRepository(this._api);
  final ApiClient _api;

  static const _mensajeMock =
      'El reporte sale del motor real del servidor; con el modo demo sin red no lo puedo generar.';

  Future<Reporte> obtener() async {
    if (Env.useMockEngine) throw ApiException(503, _mensajeMock);
    final j = await _api.post('/me/health-context/reporte', timeout: const Duration(seconds: 180));
    return Reporte.fromJson((j as Map).cast<String, dynamic>());
  }

  /// Descarga el PDF (completo o resumen de 1 página) y lo deja en un archivo
  /// temporal. Devuelve el archivo.
  Future<File> descargarPdf({bool resumen = false}) async {
    if (Env.useMockEngine) throw ApiException(503, _mensajeMock);
    final bytes = await _api.postBytes(
      '/me/health-context/reporte.pdf',
      body: {'resumen': resumen},
      accept: 'application/pdf',
      timeout: const Duration(seconds: 180),
    );
    final dir = await getTemporaryDirectory();
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/moirai-${resumen ? 'resumen' : 'reporte'}-$fecha.pdf');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Hoja de compartir del sistema: guardar en Archivos, mandarlo por correo
  /// o mensaje al médico, imprimirlo.
  Future<void> compartir(File f, {bool resumen = false}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'application/pdf')],
        subject: resumen ? 'Moirai · resumen para la consulta' : 'Moirai · reporte de salud orientativo',
        text: 'Documento orientativo, no diagnóstico. Para compartir con un profesional de salud.',
      ),
    );
  }
}
