import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/onboarding.dart';
import '../../widgets/big_number.dart';
import '../../widgets/mo.dart';

/// Pasos j–m: wearables, foto, prueba genética y resumen.

// ── j. Wearables ─────────────────────────────────────────────────────────
enum _EstadoW { inicial, leyendo, listo, sinAcceso }

class PasoWearables extends ConsumerStatefulWidget {
  const PasoWearables({super.key});

  @override
  ConsumerState<PasoWearables> createState() => _PasoWearablesState();
}

class _PasoWearablesState extends ConsumerState<PasoWearables> {
  _EstadoW _estado = _EstadoW.inicial;
  double? _suenoProm;
  int? _pasosProm;
  int _diasConDatos = 0;
  String? _aviso;

  /// Solo cuando falta Health Connect: ofrezco el atajo a la tienda.
  bool _puedeInstalar = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(onboardingProvider).wearableConectado) _estado = _EstadoW.listo;
  }

  Future<void> _conectar() async {
    setState(() {
      _estado = _EstadoW.leyendo;
      _aviso = null;
      _puedeInstalar = false;
    });
    final repo = ref.read(wearablesRepositoryProvider);
    try {
      final r = await repo.conectar();
      if (!r.ok) {
        if (!mounted) return;
        setState(() {
          _estado = _EstadoW.sinAcceso;
          _aviso = '${r.mensaje(repo.proveedorLabel)} Puedes seguir sin esto y conectarlo luego desde tu perfil.';
          _puedeInstalar = r.puedeInstalar;
        });
        return;
      }
      final dias = await repo.leer();
      final habitos = await repo.sincronizar(dias);

      final sue = dias.map((d) => d.suenoH).whereType<double>().toList();
      final pasos = dias.map((d) => d.pasos).whereType<int>().toList();
      final suenoProm = sue.isEmpty ? null : sue.reduce((a, b) => a + b) / sue.length;
      final pasosProm = pasos.isEmpty ? null : (pasos.reduce((a, b) => a + b) / pasos.length).round();
      final conDatos = dias.where((d) => d.suenoH != null || d.pasos != null).length;

      final sueH = (habitos['sueno_h'] as num?)?.toDouble();
      final ej = habitos['ejercicio'] as String?;
      await ref.read(onboardingProvider.notifier).update(
            (d) => d.copyWith(
              suenoH: sueH ?? d.suenoH,
              ejercicio: ej ?? d.ejercicio,
              wearableConectado: true,
              wearableProveedor: repo.proveedor,
            ),
          );
      if (!mounted) return;
      setState(() {
        _estado = _EstadoW.listo;
        _suenoProm = suenoProm;
        _pasosProm = pasosProm;
        _diasConDatos = conDatos;
        _aviso = conDatos == 0 ? 'Quedó conectado, pero todavía no veo datos de los últimos 14 días. Cuando sincronices el reloj, los leo.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoW.sinAcceso;
        _aviso = 'No alcancé a leer tus datos de salud. Puedes seguir sin esto; lo intento de nuevo desde tu perfil.';
      });
    }
  }

  String get _proveedorLabel => switch (ref.read(onboardingProvider).wearableProveedor) {
        'healthkit' => 'Salud (iOS)',
        _ => 'Health Connect',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final leyendo = _estado == _EstadoW.leyendo;
    final listo = _estado == _EstadoW.listo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const MoIconTile(Icons.watch_outlined),
                  const SizedBox(width: Sp.x4),
                  Expanded(
                    child: Text(
                      'Samsung, Garmin, Fitbit, Xiaomi, Apple Watch, Oura… si sincroniza con tu teléfono, me sirve.',
                      style: t.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.x5),
              const Row(
                children: [
                  Expanded(child: _Lectura(Icons.bedtime_outlined, 'Sueño')),
                  Expanded(child: _Lectura(Icons.directions_walk_rounded, 'Pasos')),
                  Expanded(child: _Lectura(Icons.favorite_outline_rounded, 'Ejercicio')),
                ],
              ),
            ],
          ),
        ).stagger(0),
        const SizedBox(height: Sp.x5),
        AnimatedSwitcher(
          duration: Motion.slow,
          switchInCurve: Motion.out,
          child: listo
              ? MoCard(
                  key: const ValueKey('listo'),
                  tone: MoTone.good,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const MoBadge('Conectado', tone: MoTone.good, icon: Icons.check_rounded),
                          const Spacer(),
                          Text(_proveedorLabel, style: t.bodySmall!.copyWith(color: MoiraiColors.greenInk)),
                        ],
                      ),
                      if (_suenoProm != null || _pasosProm != null) ...[
                        const SizedBox(height: Sp.x5),
                        Row(
                          children: [
                            if (_suenoProm != null)
                              Expanded(
                                child: _Dato(
                                  label: 'Sueño promedio',
                                  child: BigNumber(value: _suenoProm!, decimals: 1, unit: 'h', style: t.displaySmall, color: MoiraiColors.greenInk),
                                ),
                              ),
                            if (_pasosProm != null)
                              Expanded(
                                child: _Dato(
                                  label: 'Pasos al día',
                                  child: BigNumber(value: _pasosProm!.toDouble(), style: t.displaySmall, color: MoiraiColors.greenInk),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Sp.x3),
                        Text('Promedio de los últimos ${Fmt.entero(_diasConDatos)} días con datos.', style: t.bodySmall!.copyWith(color: MoiraiColors.greenInk)),
                      ],
                    ],
                  ),
                ).animate().scale(begin: const Offset(.97, .97), end: const Offset(1, 1), curve: Motion.out, duration: Motion.slow)
              : OutlinedButton.icon(
                  key: const ValueKey('conectar'),
                  onPressed: leyendo ? null : _conectar,
                  icon: leyendo
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Icon(Icons.link_rounded),
                  label: Text(leyendo ? 'Leyendo tus datos…' : 'Conectar'),
                ).stagger(1),
        ),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x4),
          MoNotice(
            tone: listo ? MoTone.brand : MoTone.watch,
            text: _aviso!,
            action: _puedeInstalar
                ? TextButton(
                    onPressed: () => ref.read(wearablesRepositoryProvider).instalarProveedor(),
                    child: const Text('Instalar'),
                  )
                : null,
          ).animate().fadeIn(duration: Motion.base),
        ],
        const SizedBox(height: Sp.x5),
        const MoFootnote('Solo leo. Nunca escribo nada en tus datos de salud.', center: false),
      ],
    );
  }
}

class _Lectura extends StatelessWidget {
  const _Lectura(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MoiraiColors.blueInk),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoOverline(label, color: MoiraiColors.greenInk),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

// ── k. Foto ──────────────────────────────────────────────────────────────
class PasoFoto extends ConsumerStatefulWidget {
  const PasoFoto({super.key});

  @override
  ConsumerState<PasoFoto> createState() => _PasoFotoState();
}

class _PasoFotoState extends ConsumerState<PasoFoto> {
  String? _aviso;
  bool _ocupado = false;

  Future<void> _elegir(ImageSource origen) async {
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    try {
      final x = await ImagePicker().pickImage(source: origen, maxWidth: 1400, imageQuality: 88);
      if (x != null) {
        await ref.read(onboardingProvider.notifier).update((d) => d.copyWith(fotoPath: x.path));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aviso = origen == ImageSource.camera
            ? 'No pude abrir la cámara aquí. Prueba con la galería o sigue sin foto.'
            : 'No pude abrir la galería. Puedes seguir sin foto.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ob = ref.watch(onboardingProvider);
    final path = ob.fotoPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedSwitcher(
            duration: Motion.slow,
            switchInCurve: Motion.bounce,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
            child: path == null
                ? Container(
                    key: const ValueKey('vacio'),
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: MoiraiColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: MoiraiColors.line, width: 1.5),
                    ),
                    child: const Icon(Icons.person_outline_rounded, size: 60, color: MoiraiColors.ink3),
                  )
                : Container(
                    key: ValueKey(path),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: MoiraiColors.blue, width: 2),
                      boxShadow: [BoxShadow(color: MoiraiColors.action.withValues(alpha: .18), blurRadius: 18, offset: const Offset(0, 6))],
                    ),
                    child: CircleAvatar(radius: 66, backgroundImage: FileImage(File(path))),
                  ),
          ),
        ).stagger(0),
        const SizedBox(height: Sp.x7),
        OutlinedButton.icon(
          onPressed: _ocupado ? null : () => _elegir(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Tomar una foto'),
        ).stagger(1),
        const SizedBox(height: Sp.x3),
        OutlinedButton.icon(
          onPressed: _ocupado ? null : () => _elegir(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Elegir de la galería'),
        ).stagger(2),
        if (path != null) ...[
          const SizedBox(height: Sp.x2),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => ref.read(onboardingProvider.notifier).update((d) => d.copyWith(clearFoto: true)),
              child: const Text('Quitar la foto'),
            ),
          ),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x4),
          MoNotice(tone: MoTone.watch, text: _aviso!).animate().fadeIn(duration: Motion.base),
        ],
        const SizedBox(height: Sp.x5),
        const MoFootnote('Se queda en este teléfono. No la uso para simular nada todavía.'),
      ],
    );
  }
}

// ── l. Prueba genética ───────────────────────────────────────────────────
class PasoGenetica extends ConsumerStatefulWidget {
  const PasoGenetica({super.key});

  @override
  ConsumerState<PasoGenetica> createState() => _PasoGeneticaState();
}

class _PasoGeneticaState extends ConsumerState<PasoGenetica> {
  String? _aviso;
  bool _ocupado = false;

  Future<void> _elegir() async {
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    try {
      final archivo = await FilePicker.pickFile(
        dialogTitle: 'Elige tu prueba genética (PDF)',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      final p = archivo?.path;
      if (p != null) {
        await ref.read(onboardingProvider.notifier).update((d) => d.copyWith(geneticaPath: p));
      }
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude abrir tus archivos. Puedes seguir y subirla después desde tu perfil.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ob = ref.watch(onboardingProvider);
    final path = ob.geneticaPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: Motion.slow,
          switchInCurve: Motion.out,
          child: path == null
              ? OutlinedButton.icon(
                  key: const ValueKey('elegir'),
                  onPressed: _ocupado ? null : _elegir,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Elegir el PDF'),
                )
              : MoCard(
                  key: ValueKey(path),
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    children: [
                      const MoIconTile(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: Sp.x4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(path.split(Platform.pathSeparator).last, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('Guardada en este teléfono', style: t.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        onPressed: () => ref.read(onboardingProvider.notifier).update((d) => d.copyWith(clearGenetica: true)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
        ).stagger(0),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x4),
          MoNotice(tone: MoTone.watch, text: _aviso!).animate().fadeIn(duration: Motion.base),
        ],
        const SizedBox(height: Sp.x5),
        const MoNotice(
          tone: MoTone.brand,
          icon: Icons.schedule_rounded,
          text: 'Por ahora solo la guardo. El análisis viene después y te lo explico paso a paso.',
        ).stagger(1),
      ],
    );
  }
}

// ── m. Resumen ───────────────────────────────────────────────────────────
/// Lo básico que vive en `/me` (lo pasa la pantalla, que tiene los valores
/// más recientes aunque el backend siga despertando).
typedef ResumenBasico = ({String? nombre, int? edad, String? sexo, double? estatura, double? peso, String? sangre});

class PasoResumen extends ConsumerWidget {
  const PasoResumen({super.key, required this.basico});
  final ResumenBasico basico;

  String _etiquetas(Map<String, String> cat, Iterable<String> keys) => keys.map((k) => cat[k] ?? k).join(', ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final b = basico;

    String? medidas() {
      final partes = <String>[
        if (b.estatura != null) '${Fmt.corto(b.estatura!)} cm',
        if (b.peso != null) '${Fmt.corto(b.peso!)} kg',
      ];
      return partes.isEmpty ? null : partes.join(' · ');
    }

    String? sueno() {
      if (ob.suenoH == null && ob.suenoCalidad == null) return null;
      final h = ob.suenoH == null ? null : '${Fmt.corto(ob.suenoH!)} h';
      final c = switch (ob.suenoCalidad) {
        'baja' => 'me levanto cansado',
        'media' => 'regular',
        'alta' => 'descanso bien',
        _ => null,
      };
      return [h, c].whereType<String>().join(', ');
    }

    final familia = ob.historialFamiliar
        .map((e) => e.parentesco == null
            ? (Catalogos.condicionesFamiliares[e.condicion] ?? e.condicion)
            : '${Catalogos.condicionesFamiliares[e.condicion] ?? e.condicion} (${Catalogos.parentescos[e.parentesco]?.toLowerCase() ?? e.parentesco})')
        .join(', ');

    final cards = <_ResumenCard>[
      _ResumenCard(icon: Icons.person_outline_rounded, titulo: 'Tú', filas: [
        ('Nombre', b.nombre),
        ('Edad', b.edad == null ? null : '${Fmt.entero(b.edad!)} años'),
        ('Sexo al nacer', b.sexo),
        ('Medidas', medidas()),
        ('Tipo de sangre', b.sangre),
      ]),
      _ResumenCard(icon: Icons.public_rounded, titulo: 'Origen', filas: [
        ('Nacionalidad', Catalogos.paises[ob.nacionalidad]),
        ('Vives en', Catalogos.paises[ob.paisResidencia]),
        ('Ancestría', Catalogos.ancestria[ob.ancestria]),
      ]),
      _ResumenCard(icon: Icons.auto_awesome_rounded, titulo: 'Lo que quieres ganar', filas: [
        ('Objetivos', ob.objetivos.isEmpty ? null : _etiquetas(Catalogos.objetivos, ob.objetivos)),
      ]),
      _ResumenCard(icon: Icons.family_restroom_rounded, titulo: 'Familia', filas: [
        ('Historial', familia.isEmpty ? null : familia),
      ]),
      _ResumenCard(icon: Icons.favorite_outline_rounded, titulo: 'Hábitos', filas: [
        ('Sueño', sueno()),
        ('Ejercicio', Catalogos.ejercicio[ob.ejercicio]),
        ('Alcohol', Catalogos.alcoholFrecuencia[ob.alcoholFrecuencia]),
        ('Tabaco', ob.tabaco == null ? null : (ob.tabaco! ? 'Sí' : 'No')),
        ('Alimentación', Catalogos.nivelBMA[ob.alimentacion]),
        ('Patrones', ob.alimentacionPatron.isEmpty ? null : _etiquetas(Catalogos.alimentacionPatron, ob.alimentacionPatron)),
        ('Estrés', Catalogos.nivelBMA[ob.estres]),
      ]),
      _ResumenCard(icon: Icons.inventory_2_outlined, titulo: 'Extras', filas: [
        ('Suplementos', ob.suplementos.isEmpty ? null : ob.suplementos.map((s) => Catalogos.suplementosComunes[s.nombre] ?? s.nombre).join(', ')),
        ('Reloj o pulsera', ob.wearableConectado ? 'Conectado' : 'Sin conectar'),
        ('Foto', ob.fotoPath == null ? 'Sin foto' : 'Guardada'),
        ('Prueba genética', ob.geneticaPath == null ? 'Sin archivo' : 'Guardada'),
      ]),
    ];

    final visibles = cards.where((c) => c.filas.any((f) => f.$2 != null)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibles.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.stackCard),
          visibles[i].stagger(i),
        ],
        const SizedBox(height: Sp.x6),
        const MoNotice(
          tone: MoTone.brand,
          icon: Icons.edit_outlined,
          text: 'Puedes cambiar cualquiera de estos datos cuando quieras desde tu perfil.',
        ),
      ],
    );
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({required this.icon, required this.titulo, required this.filas});
  final IconData icon;
  final String titulo;
  final List<(String, String?)> filas;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final conValor = filas.where((f) => f.$2 != null).toList();
    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MoIconTile(icon, size: 34),
              const SizedBox(width: Sp.x4),
              Text(titulo, style: t.titleMedium),
            ],
          ),
          const SizedBox(height: Sp.x4),
          for (var i = 0; i < conValor.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 112, child: Text(conValor[i].$1, style: t.bodySmall)),
                Expanded(child: Text(conValor[i].$2!, style: t.bodyMedium!.copyWith(color: MoiraiColors.ink, fontWeight: FontWeight.w600))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
