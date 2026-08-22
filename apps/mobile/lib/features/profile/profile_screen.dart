import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/env.dart';
import '../../core/format.dart';
import '../../data/api/api_client.dart';
import '../../data/models/biomarcador.dart';
import '../../data/models/me.dart';
import '../../data/models/onboarding.dart';
import '../../data/models/simulacion.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';
import 'profile_editors.dart';
import 'profile_widgets.dart';

/// Pestaña "Perfil": quién eres, qué te pregunté y qué simulé contigo.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _syncing = false;
  String? _syncResumen;
  bool _habitosCambiados = false;
  bool _borrando = false;
  String? _aviso;

  static final _fecha = DateFormat('d MMM yyyy', 'es_CO');
  static final _mesAnio = DateFormat('MMM yyyy', 'es_CO');

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final ob = ref.watch(onboardingProvider);
    final bms = ref.watch(biomarcadoresProvider);
    final historial = ref.watch(historialProvider);
    final email = ref.watch(authNotifierProvider).email;

    var i = 0;
    Widget s(Widget w) => w.stagger(i++, base: const Duration(milliseconds: 60));

    return MoScreen(
      children: [
        _Header(me: me, ob: ob, email: email, onFoto: _cambiarFoto, onRetry: () => ref.invalidate(meProvider)),
        const SizedBox(height: Sp.stackSection),

        s(_DatosBasicosCard(me: me, onRetry: () => ref.invalidate(meProvider))),
        const SizedBox(height: Sp.stackCard),

        s(_HabitosCard(
          ob: ob,
          cambiado: _habitosCambiados,
          onUpdate: (fn) async {
            await ref.read(onboardingProvider.notifier).update(fn);
            if (mounted) setState(() => _habitosCambiados = true);
          },
          onSimular: () {
            ref.read(simulationProvider.notifier).start();
            context.go(Routes.simulating);
          },
        )),
        const SizedBox(height: Sp.stackCard),

        s(_ObjetivosCard(ob: ob, onEditar: () => editGoalsAndFamily(context))),
        const SizedBox(height: Sp.stackCard),

        s(_WearableCard(
          ob: ob,
          proveedorLabel: _proveedorLabel(ob.wearableProveedor ?? ref.read(wearablesRepositoryProvider).proveedor),
          syncing: _syncing,
          resumen: _syncResumen,
          onSync: _sincronizar,
        )),
        const SizedBox(height: Sp.stackCard),

        s(_ExamenesCard(bms: bms, mesAnio: _mesAnio, onActualizar: () => context.push(Routes.examsUpload))),
        const SizedBox(height: Sp.stackCard),

        s(_GeneticaCard(ob: ob, onSubir: _subirGenetica)),
        const SizedBox(height: Sp.stackCard),

        s(_SimulacionesCard(historial: historial, fecha: _fecha)),
        const SizedBox(height: Sp.stackSection),

        if (_aviso != null) ...[
          s(MoNotice(text: _aviso!, tone: MoTone.watch)),
          const SizedBox(height: Sp.stackCard),
        ],
        s(OutlinedButton.icon(
          onPressed: _cerrarSesion,
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: const Text('Cerrar sesión'),
        )),
        const SizedBox(height: Sp.x3),
        s(TextButton(
          onPressed: _borrando ? null : _confirmarBorrado,
          style: TextButton.styleFrom(foregroundColor: MoiraiColors.ink2),
          child: Text(_borrando ? 'Borrando…' : 'Borrar mis datos'),
        )),
        const SizedBox(height: Sp.x6),
        s(MoFootnote('Moirai 0.1.0 · ${Uri.tryParse(Env.apiBaseUrl)?.host ?? Env.apiBaseUrl}')),
      ],
    );
  }

  static String _proveedorLabel(String proveedor) => proveedor == 'healthkit' ? 'Salud de Apple' : 'Health Connect';

  // ── Acciones ───────────────────────────────────────────────────────────

  Future<void> _cambiarFoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
      if (x == null) return;
      await ref.read(onboardingProvider.notifier).update((o) => o.copyWith(fotoPath: x.path));
    } catch (_) {
      setState(() => _aviso = 'No pude abrir tus fotos. Revisa el permiso de galería.');
    }
  }

  Future<void> _subirGenetica() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
      final path = f?.path;
      if (path == null) return;
      await ref.read(onboardingProvider.notifier).update((o) => o.copyWith(geneticaPath: path));
    } catch (_) {
      setState(() => _aviso = 'No pude leer ese archivo. Intenta con otro PDF.');
    }
  }

  Future<void> _sincronizar() async {
    setState(() {
      _syncing = true;
      _aviso = null;
    });
    final repo = ref.read(wearablesRepositoryProvider);
    final label = _proveedorLabel(repo.proveedor);
    try {
      final ok = await repo.conectar();
      if (!ok) {
        setState(() => _aviso = 'No pude conectar con $label. Revisa que esté instalado y que me des permiso de lectura.');
        return;
      }
      final dias = await repo.leer();
      final habitos = await repo.sincronizar(dias);
      final sue = dias.map((d) => d.suenoH).whereType<double>().toList();
      final pasos = dias.map((d) => d.pasos).whereType<int>().toList();
      await ref.read(onboardingProvider.notifier).update(
            (o) => o.copyWith(
              wearableConectado: true,
              wearableProveedor: repo.proveedor,
              suenoH: (habitos['sueno_h'] as num?)?.toDouble(),
              ejercicio: habitos['ejercicio'] as String?,
            ),
          );
      if (!mounted) return;
      if (sue.isEmpty && pasos.isEmpty) {
        _syncResumen = 'Conecté con $label, pero no encontré sueño ni pasos en los últimos 14 días.';
      } else {
        final partes = <String>[
          if (sue.isNotEmpty) 'duermes ${Fmt.decimal(sue.reduce((a, b) => a + b) / sue.length)} h en promedio',
          if (pasos.isNotEmpty) '${Fmt.entero(pasos.reduce((a, b) => a + b) / pasos.length)} pasos al día',
        ];
        _syncResumen = 'Últimos 14 días: ${partes.join(' · ')}. Ya lo apliqué a tus hábitos.';
        _habitosCambiados = true;
      }
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _aviso = 'La sincronización no terminó. Intenta de nuevo en un momento.');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _cerrarSesion() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude cerrar la sesión. Intenta de nuevo.');
    }
  }

  Future<void> _confirmarBorrado() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borro todo?'),
        content: const Text('Borro tu perfil y tus simulaciones. Esto no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Mejor no')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MoiraiColors.amberInk),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _borrando = true;
      _aviso = null;
    });
    final uid = ref.read(currentUserIdProvider);
    final profile = ref.read(profileRepositoryProvider);
    try {
      await profile.deleteMe();
      if (uid != null) await profile.clearLocal(uid);
      await ref.read(authRepositoryProvider).signOut();
    } on ApiException catch (e) {
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude borrar tus datos. ¿Tienes internet?');
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }
}

// ── Header ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.me, required this.ob, required this.email, required this.onFoto, required this.onRetry});
  final AsyncValue<Me> me;
  final OnboardingData ob;
  final String? email;
  final VoidCallback onFoto;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final foto = ob.fotoPath;
    final tieneFoto = foto != null && File(foto).existsSync();

    final avatar = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onFoto,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MoiraiColors.blueSoft,
            border: Border.all(color: MoiraiColors.surface, width: 3),
            image: tieneFoto ? DecorationImage(image: FileImage(File(foto)), fit: BoxFit.cover) : null,
          ),
          child: tieneFoto ? null : const Center(child: MoiraiMascot(size: 64)),
        ),
      ),
    );

    final datos = me.when(
      skipLoadingOnRefresh: true,
      data: (m) {
        final nombre = (m.profile.fullName ?? '').trim();
        final edad = m.profile.edad;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombre.isEmpty ? 'Tú' : nombre, style: t.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            if ((m.email ?? email) != null) ...[
              const SizedBox(height: 2),
              Text(m.email ?? email!, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (edad != null) ...[
              const SizedBox(height: 2),
              Text('$edad años', style: t.titleSmall!.copyWith(color: MoiraiColors.blueInk)),
            ],
          ],
        );
      },
      loading: () => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(width: 160, height: 24),
          SizedBox(height: 8),
          SkeletonLine(width: 200, height: 14),
          SizedBox(height: 8),
          SkeletonLine(width: 70, height: 14),
        ],
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tú', style: t.headlineMedium),
          if (email != null) ...[const SizedBox(height: 2), Text(email!, style: t.bodyMedium)],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: Sp.x5),
            Expanded(child: datos),
          ],
        ),
        if (me.isLoading && !me.hasValue) ...[
          const SizedBox(height: Sp.x5),
          const _ColdStartNotice(),
        ],
        if (me.hasError && !me.isLoading) ...[
          const SizedBox(height: Sp.x5),
          MoNotice(
            text: me.error is ApiException ? (me.error! as ApiException).message : 'No pude traer tu perfil. ¿Tienes internet?',
            tone: MoTone.watch,
            action: TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ),
        ],
      ],
    ).stagger(0);
  }
}

/// Aparece solo si `/me` lleva más de 4 s cargando (Render se duerme).
class _ColdStartNotice extends StatefulWidget {
  const _ColdStartNotice();

  @override
  State<_ColdStartNotice> createState() => _ColdStartNoticeState();
}

class _ColdStartNoticeState extends State<_ColdStartNotice> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.slow,
      curve: Motion.out,
      alignment: Alignment.topCenter,
      child: _show
          ? const MoNotice(text: 'El servidor está despertando, dame unos segundos…', icon: Icons.hourglass_top_rounded)
          : const SizedBox(width: double.infinity),
    );
  }
}

// ── Datos básicos ────────────────────────────────────────────────────────

class _DatosBasicosCard extends StatelessWidget {
  const _DatosBasicosCard({required this.me, required this.onRetry});
  final AsyncValue<Me> me;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ProfileCard(
      title: 'Datos básicos',
      subtitle: 'Toca un dato para cambiarlo.',
      child: me.when(
        skipLoadingOnRefresh: true,
        data: (m) => _rows(context, m.profile),
        loading: () => Column(
          children: [
            for (var k = 0; k < 6; k++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Row(children: [SkeletonLine(width: 110), Spacer(), SkeletonLine(width: 80)]),
              ),
          ],
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aún no pude leer tu perfil del servidor.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Sp.x4),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _rows(BuildContext context, Profile p) {
    final fechaLarga = DateFormat('d MMM yyyy', 'es_CO');
    const sinDato = 'Sin dato';
    String v(String? s) => (s == null || s.isEmpty) ? sinDato : s;

    final rows = <(BasicField, String)>[
      (BasicField.nombre, v(p.fullName)),
      (BasicField.nacimiento, p.dateOfBirth == null ? sinDato : fechaLarga.format(p.dateOfBirth!)),
      (BasicField.sexo, v(p.sexAtBirth?.label)),
      (BasicField.estatura, p.heightCm == null ? sinDato : '${Fmt.corto(p.heightCm!)} cm'),
      (BasicField.peso, p.weightKg == null ? sinDato : '${Fmt.corto(p.weightKg!)} kg'),
      (BasicField.sangre, v(p.bloodType)),
    ];
    return Column(
      children: [
        for (var k = 0; k < rows.length; k++) ...[
          if (k > 0) const Divider(),
          InfoRow(
            label: rows[k].$1.label,
            value: rows[k].$2,
            muted: rows[k].$2 == sinDato,
            onTap: () => editBasicField(context, rows[k].$1, p),
          ),
        ],
      ],
    );
  }
}

// ── Hábitos ──────────────────────────────────────────────────────────────

class _HabitosCard extends StatelessWidget {
  const _HabitosCard({required this.ob, required this.cambiado, required this.onUpdate, required this.onSimular});
  final OnboardingData ob;
  final bool cambiado;
  final Future<void> Function(OnboardingData Function(OnboardingData)) onUpdate;
  final VoidCallback onSimular;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const sinDato = 'Sin dato';
    final sueno = ob.suenoH ?? 7;
    return ProfileCard(
      title: 'Hábitos',
      subtitle: 'Lo que modula tu deriva año a año.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HabitRow(
            icon: Icons.bedtime_rounded,
            label: 'Sueño',
            value: ob.suenoH == null ? sinDato : '${Fmt.corto(ob.suenoH!)} h',
            editor: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Slider(
                  value: sueno.clamp(4, 10).toDouble(),
                  min: 4,
                  max: 10,
                  divisions: 12,
                  label: '${Fmt.corto(sueno)} h',
                  onChanged: (v) => onUpdate((o) => o.copyWith(suenoH: (v * 2).round() / 2)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('4 h', style: t.labelSmall), Text('${Fmt.corto(sueno)} h por noche', style: t.labelMedium), Text('10 h', style: t.labelSmall)],
                ),
              ],
            ),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.nightlight_round,
            label: 'Calidad del sueño',
            value: Catalogos.nivelBMA[ob.suenoCalidad] ?? sinDato,
            editor: MoChoiceGroup<String>(options: Catalogos.nivelBMA, value: ob.suenoCalidad, onChanged: (v) => onUpdate((o) => o.copyWith(suenoCalidad: v))),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.directions_walk_rounded,
            label: 'Ejercicio',
            value: Catalogos.ejercicio[ob.ejercicio] ?? sinDato,
            editor: MoChoiceGroup<String>(options: Catalogos.ejercicio, value: ob.ejercicio, onChanged: (v) => onUpdate((o) => o.copyWith(ejercicio: v))),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.local_bar_rounded,
            label: 'Alcohol',
            value: Catalogos.alcoholFrecuencia[ob.alcoholFrecuencia] ?? _alcoholNivelLabel(ob.alcohol) ?? sinDato,
            editor: MoChoiceGroup<String>(
              options: Catalogos.alcoholFrecuencia,
              value: ob.alcoholFrecuencia,
              onChanged: (v) => onUpdate((o) => o.copyWith(alcoholFrecuencia: v, alcohol: Catalogos.alcoholNivel(v))),
            ),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.restaurant_rounded,
            label: 'Alimentación',
            value: Catalogos.nivelBMA[ob.alimentacion] ?? sinDato,
            editor: MoChoiceGroup<String>(options: Catalogos.nivelBMA, value: ob.alimentacion, onChanged: (v) => onUpdate((o) => o.copyWith(alimentacion: v))),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.smoke_free_rounded,
            label: 'Tabaco',
            value: ob.tabaco == null ? sinDato : (ob.tabaco! ? 'Sí' : 'No'),
            editor: MoChoiceGroup<bool>(options: const {false: 'No fumo', true: 'Sí fumo'}, value: ob.tabaco, onChanged: (v) => onUpdate((o) => o.copyWith(tabaco: v))),
          ),
          const Divider(),
          HabitRow(
            icon: Icons.self_improvement_rounded,
            label: 'Estrés',
            value: Catalogos.nivelBMA[ob.estres] ?? sinDato,
            editor: MoChoiceGroup<String>(options: Catalogos.nivelBMA, value: ob.estres, onChanged: (v) => onUpdate((o) => o.copyWith(estres: v))),
          ),
          const SizedBox(height: Sp.x5),
          Text('Si cambias algo aquí, vuelve a simular para verlo reflejado.', style: t.bodySmall),
          const SizedBox(height: Sp.x4),
          if (cambiado)
            MoPrimaryButton(label: 'Volver a simular', icon: Icons.replay_rounded, onPressed: onSimular)
          else
            OutlinedButton.icon(onPressed: onSimular, icon: const Icon(Icons.replay_rounded, size: 20), label: const Text('Volver a simular')),
        ],
      ),
    );
  }

  static String? _alcoholNivelLabel(String? nivel) => switch (nivel) {
    'nunca' => 'Nunca',
    'ocasional' => 'Ocasional',
    'moderado' => 'Moderado',
    'alto' => 'Frecuente',
    _ => null,
  };
}

// ── Objetivos y familia ──────────────────────────────────────────────────

class _ObjetivosCard extends StatelessWidget {
  const _ObjetivosCard({required this.ob, required this.onEditar});
  final OnboardingData ob;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final familia = ob.historialFamiliar;
    return ProfileCard(
      title: 'Objetivos y familia',
      action: TextButton(onPressed: onEditar, child: const Text('Editar')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoOverline('Qué buscas'),
          const SizedBox(height: Sp.x3),
          if (ob.objetivos.isEmpty)
            Text('Todavía no me dijiste qué buscas.', style: t.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final o in ob.objetivos) MoBadge(Catalogos.objetivos[o] ?? o, tone: MoTone.brand)],
            ),
          const SizedBox(height: Sp.x5),
          MoOverline('En tu familia'),
          const SizedBox(height: Sp.x3),
          if (familia.isEmpty)
            Text('Sin historial familiar registrado.', style: t.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in familia)
                  MoBadge(
                    f.condicion == 'ninguna' || f.parentesco == null
                        ? (Catalogos.condicionesFamiliares[f.condicion] ?? f.condicion)
                        : '${Catalogos.condicionesFamiliares[f.condicion] ?? f.condicion} · ${(Catalogos.parentescos[f.parentesco] ?? f.parentesco!).toLowerCase()}',
                    tone: f.condicion == 'ninguna' ? MoTone.good : MoTone.sunken,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Reloj o pulsera ──────────────────────────────────────────────────────

class _WearableCard extends StatelessWidget {
  const _WearableCard({required this.ob, required this.proveedorLabel, required this.syncing, required this.resumen, required this.onSync});
  final OnboardingData ob;
  final String proveedorLabel;
  final bool syncing;
  final String? resumen;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final conectado = ob.wearableConectado;
    return ProfileCard(
      title: 'Reloj o pulsera',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MoIconTile(Icons.watch_rounded, tone: conectado ? MoTone.good : MoTone.sunken),
              const SizedBox(width: Sp.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conectado ? 'Conectado · $proveedorLabel' : 'Sin conectar', style: t.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      conectado
                          ? 'Leo tu sueño y tus pasos de los últimos 14 días y los llevo a tus hábitos.'
                          : 'Si tienes reloj o pulsera, leo tu sueño y tus pasos desde $proveedorLabel. Sin cuentas de terceros.',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              if (conectado) ...[const SizedBox(width: Sp.x3), const MoBadge('Activo', tone: MoTone.good, icon: Icons.check_rounded)],
            ],
          ),
          if (resumen != null) ...[
            const SizedBox(height: Sp.x4),
            MoNotice(text: resumen!, tone: MoTone.good, icon: Icons.sync_rounded),
          ],
          const SizedBox(height: Sp.x5),
          OutlinedButton.icon(
            onPressed: syncing ? null : onSync,
            icon: syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                : Icon(conectado ? Icons.sync_rounded : Icons.link_rounded, size: 20),
            label: Text(syncing ? 'Leyendo…' : (conectado ? 'Sincronizar ahora' : 'Conectar')),
          ),
        ],
      ),
    );
  }
}

// ── Exámenes ─────────────────────────────────────────────────────────────

class _ExamenesCard extends StatelessWidget {
  const _ExamenesCard({required this.bms, required this.mesAnio, required this.onActualizar});
  final List<Biomarcador> bms;
  final DateFormat mesAnio;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = BiomarcadorDef.all.length;
    final fechas = bms.map((b) => b.fecha).whereType<String>().toList()..sort();
    final ultima = fechas.isEmpty ? null : _fechaExamen(fechas.last);
    return ProfileCard(
      title: 'Exámenes',
      subtitle: bms.isEmpty
          ? 'Aún no tengo tus valores; simulo con medianas poblacionales y una banda más ancha.'
          : '${bms.length} de $total valores${ultima == null ? '' : ' · último examen ${mesAnio.format(ultima)}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bms.isNotEmpty) ...[
            for (var k = 0; k < bms.length; k++) ...[
              if (k > 0) const Divider(),
              InfoRow(
                label: BiomarcadorDef.byId(bms[k].nombre)?.nombre ?? bms[k].nombre,
                value: '${Fmt.corto(bms[k].valor)} ${bms[k].unidad}',
                trailing: bms[k].inferido ? const MoBadge('Inferido', tone: MoTone.watch) : null,
              ),
            ],
            const SizedBox(height: Sp.x4),
            Text(
              bms.length >= total ? 'Tengo los 9. La banda es la más angosta que puedo darte.' : 'Los ${total - bms.length} que faltan los imputo con medianas NHANES.',
              style: t.bodySmall,
            ),
            const SizedBox(height: Sp.x4),
          ],
          OutlinedButton.icon(
            onPressed: onActualizar,
            icon: const Icon(Icons.upload_file_rounded, size: 20),
            label: Text(bms.isEmpty ? 'Subir exámenes' : 'Actualizar exámenes'),
          ),
        ],
      ),
    );
  }

  static DateTime? _fechaExamen(String s) {
    final parts = s.split('-');
    final y = int.tryParse(parts.elementAtOrNull(0) ?? '');
    final m = int.tryParse(parts.elementAtOrNull(1) ?? '1') ?? 1;
    return y == null ? null : DateTime(y, m);
  }
}

// ── Prueba genética ──────────────────────────────────────────────────────

class _GeneticaCard extends StatelessWidget {
  const _GeneticaCard({required this.ob, required this.onSubir});
  final OnboardingData ob;
  final VoidCallback onSubir;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final path = ob.geneticaPath;
    return ProfileCard(
      title: 'Prueba genética',
      subtitle: 'La analizo contigo más adelante.',
      child: path == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Si tienes una prueba genética en PDF, guárdala aquí. Por ahora no entra en la simulación.', style: t.bodyMedium),
                const SizedBox(height: Sp.x4),
                OutlinedButton.icon(onPressed: onSubir, icon: const Icon(Icons.picture_as_pdf_rounded, size: 20), label: const Text('Subir PDF')),
              ],
            )
          : Row(
              children: [
                const MoIconTile(Icons.picture_as_pdf_rounded, tone: MoTone.sunken),
                const SizedBox(width: Sp.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(path.split(Platform.pathSeparator).last, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      const MoBadge('Pendiente de análisis', tone: MoTone.watch, icon: Icons.schedule_rounded),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.x3),
                TextButton(onPressed: onSubir, child: const Text('Cambiar')),
              ],
            ),
    );
  }
}

// ── Mis simulaciones ─────────────────────────────────────────────────────

class _SimulacionesCard extends StatelessWidget {
  const _SimulacionesCard({required this.historial, required this.fecha});
  final List<SimulacionResultado> historial;
  final DateFormat fecha;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProfileCard(
      title: 'Mis simulaciones',
      subtitle: historial.isEmpty ? null : '${historial.length} ${historial.length == 1 ? 'corrida' : 'corridas'} guardadas en este dispositivo.',
      child: historial.isEmpty
          ? Text('Aún no he simulado tu futuro. Cuando lo haga, aquí queda el historial.', style: t.bodyMedium)
          : Column(
              children: [
                for (var k = 0; k < historial.length; k++) ...[
                  if (k > 0) const Divider(),
                  _SimRow(r: historial[k], fecha: fecha),
                ],
              ],
            ),
    );
  }
}

class _SimRow extends StatelessWidget {
  const _SimRow({required this.r, required this.fecha});
  final SimulacionResultado r;
  final DateFormat fecha;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mejor = r.mejorDecision;
    final etiqueta = mejor.etiqueta.isNotEmpty
        ? mejor.etiqueta
        : mejor.intervenciones.map((id) => r.intervencion(id)?.etiqueta ?? id).join(' + ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const MoIconTile(Icons.auto_awesome_rounded, tone: MoTone.sunken, size: 40),
          const SizedBox(width: Sp.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fecha.format(r.creadoEn), style: t.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Edad biológica ${Fmt.decimal(r.edadBiologicaHoy)} · ${etiqueta.isEmpty ? 'sin palanca' : etiqueta}',
                  style: t.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (mejor.intervenciones.isNotEmpty) ...[
            const SizedBox(width: Sp.x3),
            Text(
              '${Fmt.delta(mejor.aniosGanados)} años',
              style: t.titleSmall!.copyWith(color: MoiraiColors.greenInk, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ],
      ),
    );
  }
}
