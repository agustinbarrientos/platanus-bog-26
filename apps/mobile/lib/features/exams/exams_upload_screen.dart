import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../data/models/biomarcador.dart';
import '../../data/repositories/demo_data.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

enum _Estado { idle, leyendo, fallo }

/// Valores que Claude vio en el documento pero el backend no guardó (unidad o
/// rango fuera de lo que acepta). Ya vienen en texto legible. Los muestra la
/// pantalla de confirmación.
final advertenciasLecturaProvider = StateProvider<List<String>>((_) => const []);

/// A · Subir exámenes. Foto, archivo o a mano; todo opcional. Mientras lee,
/// la mascota trabaja en lugar de un spinner.
class ExamsUploadScreen extends ConsumerStatefulWidget {
  const ExamsUploadScreen({super.key});

  @override
  ConsumerState<ExamsUploadScreen> createState() => _ExamsUploadScreenState();
}

class _ExamsUploadScreenState extends ConsumerState<ExamsUploadScreen> {
  _Estado _estado = _Estado.idle;
  String? _aviso;
  MoTone _avisoTone = MoTone.watch;

  static const _fallo = 'No alcancé a leer bien ese archivo. Si quieres, escribe los valores a mano y seguimos.';

  // ── Acciones ───────────────────────────────────────────────────────────
  Future<void> _tomarFoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
      if (x == null) return;
      await _leerVarios([x.path]);
    } catch (_) {
      _mostrarAviso('No pude abrir la cámara aquí. Prueba con un archivo o escribe los valores a mano.');
    }
  }

  Future<void> _elegirArchivos() async {
    try {
      final archivos = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
      final rutas = archivos.map((f) => f.path).whereType<String>().toList();
      if (rutas.isEmpty) {
        if (archivos.isNotEmpty) _mostrarAviso('Esos archivos no están en tu teléfono. Prueba con otros o escribe los valores a mano.');
        return;
      }
      await _leerVarios(rutas);
    } catch (_) {
      _mostrarAviso('No pude abrir esos archivos. Prueba con otros o escribe los valores a mano.');
    }
  }

  /// Lee uno o más documentos. El backend solo acepta un archivo por
  /// solicitud, así que cada documento es su propia llamada — en serie, no en
  /// paralelo, para no perder si el servidor está despertando. Cada llamada
  /// guarda directamente en `health_context`, así que basta con quedarnos con
  /// el `biomarcadores` de la última respuesta exitosa (ya trae todo lo
  /// acumulado); las advertencias sí se juntan de todas.
  Future<void> _leerVarios(List<String> rutas) async {
    setState(() {
      _estado = _Estado.leyendo;
      _aviso = null;
    });
    final advertencias = <String>[];
    var todos = const <Biomarcador>[];
    String? fecha;
    var exitosos = 0;
    for (final ruta in rutas) {
      try {
        final r = await ref.read(examsRepositoryProvider).extraer(ruta);
        advertencias.addAll(r.advertencias);
        todos = r.biomarcadores;
        fecha ??= r.fechaExamen;
        exitosos++;
      } catch (_) {
        // Sigo con los demás documentos; si todos fallan, aviso abajo.
      }
    }
    if (!mounted) return;
    if (exitosos == 0) {
      _mostrarAviso(_fallo);
      return;
    }
    if (todos.isEmpty && advertencias.isEmpty) {
      _mostrarAviso(
        rutas.length == 1
            ? 'No encontré valores que reconozca en ese documento. Puedes escribirlos a mano.'
            : 'No encontré valores que reconozca en esos documentos. Puedes escribirlos a mano.',
        tone: MoTone.brand,
      );
      return;
    }
    final lectura = [for (final b in todos) (b.fecha == null && fecha != null) ? b.copyWith(fecha: fecha) : b];
    _irAConfirmar(lectura, advertencias: advertencias);
  }

  Future<void> _ejemplo() async {
    setState(() {
      _estado = _Estado.leyendo;
      _aviso = null;
    });
    // Misma coreografía que una lectura real, sin depender de OCR en vivo.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    _irAConfirmar(DemoData.lecturaExamen());
  }

  void _aMano() => _irAConfirmar(const <Biomarcador>[]);

  void _irAConfirmar(List<Biomarcador> lectura, {List<String> advertencias = const []}) {
    ref.read(lecturaPendienteProvider.notifier).state = lectura;
    ref.read(advertenciasLecturaProvider.notifier).state = advertencias;
    setState(() => _estado = _Estado.idle);
    context.push(Routes.examsConfirm);
  }

  void _despues() {
    ref.read(simulationProvider.notifier).start();
    context.go(Routes.simulating);
  }

  void _mostrarAviso(String texto, {MoTone tone = MoTone.watch}) => setState(() {
        _estado = _Estado.fallo;
        _aviso = texto;
        _avisoTone = tone;
      });

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final leyendo = _estado == _Estado.leyendo;
    return MoScreen(
      appBar: context.canPop() ? AppBar() : null,
      bottom: AnimatedOpacity(
        duration: Motion.base,
        opacity: leyendo ? 0 : 1,
        child: IgnorePointer(
          ignoring: leyendo,
          child: TextButton(onPressed: _despues, child: const Text('Lo hago después')),
        ),
      ),
      children: [
        const MoScreenHeader(
          title: '¿Tienes exámenes recientes?',
          subtitle:
              'Cualquier examen de sangre u otro examen médico me sirve — puedes subir varios documentos a la vez. Si no tienes, no importa: puedo seguir sin ellos y decirte después qué te conviene medir. También puedes escribir los valores a mano.',
        ),
        const SizedBox(height: Sp.x6),
        Center(
          child: AnimatedSwitcher(
            duration: Motion.slow,
            switchInCurve: Motion.out,
            child: leyendo
                ? const SizedBox.shrink(key: ValueKey('sin-mascota'))
                : const MoiraiMascot(key: ValueKey('mascota'), size: 104),
          ),
        ),
        const SizedBox(height: Sp.x5),
        AnimatedSwitcher(
          duration: Motion.slow,
          switchInCurve: Motion.out,
          switchOutCurve: Motion.soft,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
          child: leyendo ? const _Leyendo(key: ValueKey('leyendo')) : _opciones(t),
        ),
        const SizedBox(height: Sp.x6),
        const MoNotice(
          text: 'Tus exámenes se quedan en tu teléfono. Solo leo los números que necesito.',
          icon: Icons.lock_outline_rounded,
        ).animate(delay: 360.ms).fadeIn(duration: Motion.slow),
        const SizedBox(height: Sp.x4),
        Center(
          child: TextButton.icon(
            onPressed: leyendo ? null : _ejemplo,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Probar con un examen de ejemplo'),
            style: TextButton.styleFrom(foregroundColor: MoiraiColors.ink2, textStyle: t.labelMedium),
          ),
        ).animate(delay: 420.ms).fadeIn(duration: Motion.slow),
      ],
    );
  }

  Widget _opciones(TextTheme t) {
    return Column(
      key: const ValueKey('opciones'),
      children: [
        if (_aviso != null) ...[
          MoNotice(
            text: _aviso!,
            tone: _avisoTone,
            icon: _avisoTone == MoTone.brand ? Icons.search_off_rounded : Icons.auto_fix_high_rounded,
            action: TextButton(
              onPressed: _aMano,
              style: TextButton.styleFrom(
                foregroundColor: _avisoTone == MoTone.brand ? MoiraiColors.blueInk : MoiraiColors.amberInk,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('A mano'),
            ),
          ).animate().fadeIn(duration: Motion.slow).slideY(begin: -.05, end: 0, curve: Motion.out),
          const SizedBox(height: Sp.stackCard),
        ],
        _Opcion(icon: Icons.photo_camera_rounded, label: 'Tomar una foto', sub: 'De un examen de sangre u otro examen médico', onTap: _tomarFoto).stagger(0),
        const SizedBox(height: Sp.x3 + 2),
        _Opcion(icon: Icons.upload_file_rounded, label: 'Elegir archivos', sub: 'PDF o imagen — puedes elegir varios a la vez', onTap: _elegirArchivos).stagger(1),
        const SizedBox(height: Sp.x3 + 2),
        _Opcion(icon: Icons.edit_note_rounded, label: 'Escribir los valores a mano', sub: 'Los que tengas; los demás los infiero', tone: MoTone.sunken, onTap: _aMano).stagger(2),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.icon, required this.label, required this.sub, required this.onTap, this.tone = MoTone.brand});
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final MoTone tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          MoIconTile(icon, tone: tone, size: 48),
          const SizedBox(width: Sp.x4 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(sub, style: t.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: MoiraiColors.ink3),
        ],
      ),
    );
  }
}

/// Estado "Leyendo tu examen…": mascota trabajando + barras con shimmer en
/// vez de un spinner.
class _Leyendo extends StatelessWidget {
  const _Leyendo({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget barra(double w) => Container(
          height: 11,
          width: w,
          decoration: BoxDecoration(color: MoiraiColors.surface2, borderRadius: BorderRadius.circular(Rad.pill)),
        );
    return MoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const MoiraiMascot(size: 72, mood: MascotMood.working),
          const SizedBox(width: Sp.x5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Leyendo tu examen…', style: t.titleMedium),
                const SizedBox(height: 4),
                Text('Busco los 9 valores que necesito. Un momento.', style: t.bodySmall),
                const SizedBox(height: Sp.x4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    barra(150),
                    const SizedBox(height: 7),
                    barra(110),
                    const SizedBox(height: 7),
                    barra(130),
                  ],
                )
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(duration: 1400.ms, color: MoiraiColors.blueSoft, angle: .4),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: Motion.slow).scale(begin: const Offset(.98, .98), end: const Offset(1, 1), curve: Motion.out, duration: Motion.slow);
  }
}
