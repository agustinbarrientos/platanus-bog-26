import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/onboarding.dart';
import '../../widgets/big_number.dart';
import '../../widgets/mo.dart';
import 'onboarding_widgets.dart';

/// Pasos d–i: objetivos, familia y hábitos moduladores. Todo vive en
/// `onboardingProvider` y se persiste en cada cambio.

const _iconosObjetivos = <String, IconData>{
  'energia': Icons.bolt_rounded,
  'prevencion': Icons.shield_outlined,
  'longevidad': Icons.hourglass_bottom_rounded,
  'fertilidad': Icons.spa_outlined,
  'rendimiento': Icons.directions_run_rounded,
  'sueno': Icons.bedtime_outlined,
  'peso': Icons.monitor_weight_outlined,
  'salud_mental': Icons.self_improvement_rounded,
};

// ── d. Objetivos ─────────────────────────────────────────────────────────
class PasoObjetivos extends ConsumerWidget {
  const PasoObjetivos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MultiChips(
          options: Catalogos.objetivos,
          icons: _iconosObjetivos,
          values: ob.objetivos,
          onChanged: (s) => n.update((d) => d.copyWith(objetivos: s)),
        ).stagger(0),
        const SizedBox(height: Sp.x6),
        AnimatedSwitcher(
          duration: Motion.base,
          child: ob.objetivos.isEmpty
              ? const SizedBox.shrink()
              : MoNotice(
                  key: ValueKey(ob.objetivos.length),
                  tone: MoTone.brand,
                  icon: Icons.auto_awesome_rounded,
                  text: ob.objetivos.length == 1
                      ? 'Anotado. Cuando te muestre palancas, te marco las que tocan eso.'
                      : 'Anotados ${Fmt.entero(ob.objetivos.length)} objetivos. Te marco las palancas que tocan lo que más te importa.',
                ),
        ),
      ],
    );
  }
}

// ── d2. Cómo te explico ──────────────────────────────────────────────────
/// "¿Qué tanto sabes de salud?": fija el registro del chat
/// (`perfil_conocimiento`). Moirai siempre habla sencillo; esto solo decide
/// cuánto vocabulario puede dar por sabido.
class PasoPerfil extends ConsumerWidget {
  const PasoPerfil({super.key});

  static const _iconos = <String, IconData>{
    'general': Icons.chat_bubble_outline_rounded,
    'curioso': Icons.lightbulb_outline_rounded,
    'profesional': Icons.medical_services_outlined,
  };

  static const _respuesta = <String, String>{
    'general': 'Perfecto. Te lo cuento como a un amigo, sin palabras raras. Si un día quieres el detalle técnico, pídemelo y te lo doy.',
    'curioso': 'Me gusta. Te explico sencillo, pero nombro las cosas por su nombre y te cuento el porqué. Si quieres ir más hondo, pídemelo.',
    'profesional': 'Entendido. Uso el vocabulario del área y voy al grano. La parte técnica completa te la doy cuando me la pidas.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    final v = ob.perfilConocimiento;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OpcionLista<String>(
          opciones: [
            for (final e in Catalogos.perfilConocimiento.entries)
              (value: e.key, label: e.value, icon: _iconos[e.key] ?? Icons.chat_bubble_outline_rounded, sub: Catalogos.perfilConocimientoDetalle[e.key]),
          ],
          value: v,
          onChanged: (p) => n.update((d) => d.copyWith(perfilConocimiento: p)),
        ),
        const SizedBox(height: Sp.x6),
        AnimatedSwitcher(
          duration: Motion.base,
          child: v == null
              ? const SizedBox.shrink()
              : MoNotice(key: ValueKey(v), tone: MoTone.brand, icon: Icons.auto_awesome_rounded, text: _respuesta[v] ?? _respuesta['general']!),
        ),
        const SizedBox(height: Sp.x5),
        const MoFootnote('Lo puedes cambiar cuando quieras desde tu perfil.', center: false),
      ],
    );
  }
}

// ── e. Historial familiar ────────────────────────────────────────────────
class PasoFamilia extends ConsumerWidget {
  const PasoFamilia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    final seleccion = ob.historialFamiliar.map((e) => e.condicion).toSet();

    void toggle(Set<String> nuevo) {
      // 'ninguna' es excluyente con el resto.
      final agregado = nuevo.difference(seleccion);
      List<FamiliarCondicion> lista;
      if (agregado.contains('ninguna')) {
        lista = const [FamiliarCondicion(condicion: 'ninguna')];
      } else {
        lista = [
          for (final e in ob.historialFamiliar)
            if (nuevo.contains(e.condicion) && e.condicion != 'ninguna') e,
          for (final c in agregado)
            if (c != 'ninguna') FamiliarCondicion(condicion: c),
        ];
      }
      n.update((d) => d.copyWith(historialFamiliar: lista));
    }

    void parentesco(String condicion, String? p) {
      n.update((d) => d.copyWith(historialFamiliar: [
            for (final e in d.historialFamiliar)
              e.condicion == condicion ? FamiliarCondicion(condicion: condicion, parentesco: e.parentesco == p ? null : p) : e,
          ]));
    }

    final conDetalle = ob.historialFamiliar.where((e) => e.condicion != 'ninguna').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MultiChips(options: Catalogos.condicionesFamiliares, values: seleccion, onChanged: toggle).stagger(0),
        AnimatedSize(
          duration: Motion.slow,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: conDetalle.isEmpty
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Sp.stackSection),
                    const Etiqueta('¿Quién?', opcional: true, hint: 'Si lo sabes, me ayuda a afinar. Si no, sigue.'),
                    for (var i = 0; i < conDetalle.length; i++) ...[
                      if (i > 0) const SizedBox(height: Sp.x4),
                      MoCard(
                        key: ValueKey(conDetalle[i].condicion),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Catalogos.condicionesFamiliares[conDetalle[i].condicion] ?? conDetalle[i].condicion, style: t.titleSmall),
                            const SizedBox(height: Sp.x3),
                            MoChoiceGroup<String>(
                              options: Catalogos.parentescos,
                              value: conDetalle[i].parentesco,
                              onChanged: (p) => parentesco(conDetalle[i].condicion, p),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ── f. Sueño ─────────────────────────────────────────────────────────────
class PasoSueno extends ConsumerStatefulWidget {
  const PasoSueno({super.key});

  @override
  ConsumerState<PasoSueno> createState() => _PasoSuenoState();
}

class _PasoSuenoState extends ConsumerState<PasoSueno> {
  double? _local;

  @override
  void initState() {
    super.initState();
    // Si todavía no hay valor, arranco en 7 h (y lo dejo guardado).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(onboardingProvider).suenoH == null) {
        ref.read(onboardingProvider.notifier).update((d) => d.copyWith(suenoH: 7));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    final h = _local ?? ob.suenoH ?? 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoCard(
          child: Column(
            children: [
              const MoOverline('Horas por noche'),
              const SizedBox(height: Sp.x3),
              BigNumber(value: h, corto: true, unit: 'horas', style: t.displayLarge, color: MoiraiColors.action),
              const SizedBox(height: Sp.x3),
              Slider(
                min: 4,
                max: 10,
                divisions: 12,
                value: h.clamp(4, 10),
                label: '${Fmt.corto(h)} h',
                onChanged: (v) => setState(() => _local = v),
                onChangeEnd: (v) {
                  n.update((d) => d.copyWith(suenoH: v));
                  setState(() => _local = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('4 h', style: t.bodySmall), Text('10 h', style: t.bodySmall)],
                ),
              ),
            ],
          ),
        ).stagger(0),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('¿Y cómo te levantas?'),
        MoChoiceGroup<String>(
          options: const {'baja': 'Cansado', 'media': 'Regular', 'alta': 'Descansado'},
          value: ob.suenoCalidad,
          onChanged: (v) => n.update((d) => d.copyWith(suenoCalidad: v)),
          wrap: false,
        ).stagger(1),
      ],
    );
  }
}

// ── g. Ejercicio ─────────────────────────────────────────────────────────
class PasoEjercicio extends ConsumerWidget {
  const PasoEjercicio({super.key});

  static const _iconos = <String, IconData>{
    'nulo': Icons.weekend_outlined,
    'bajo': Icons.directions_walk_rounded,
    'moderado': Icons.directions_run_rounded,
    'alto': Icons.fitness_center_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    return OpcionLista<String>(
      opciones: [
        for (final e in Catalogos.ejercicio.entries)
          (value: e.key, label: e.value, icon: _iconos[e.key] ?? Icons.directions_walk_rounded, sub: null),
      ],
      value: ob.ejercicio,
      onChanged: (v) => n.update((d) => d.copyWith(ejercicio: v)),
    );
  }
}

// ── h1. Alcohol y tabaco ─────────────────────────────────────────────────
class PasoAlcohol extends ConsumerWidget {
  const PasoAlcohol({super.key});

  static const _iconos = <String, IconData>{
    'nunca': Icons.no_drinks_outlined,
    'mensual': Icons.local_bar_outlined,
    '2_3_por_semana': Icons.wine_bar_outlined,
    'casi_diario': Icons.sports_bar_outlined,
    'diario': Icons.liquor_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Etiqueta('¿Cada cuánto tomas alcohol?'),
        OpcionLista<String>(
          opciones: [
            for (final e in Catalogos.alcoholFrecuencia.entries)
              (value: e.key, label: e.value, icon: _iconos[e.key] ?? Icons.local_bar_outlined, sub: null),
          ],
          value: ob.alcoholFrecuencia,
          onChanged: (v) => n.update((d) => d.copyWith(alcoholFrecuencia: v, alcohol: Catalogos.alcoholNivel(v))),
        ),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('¿Fumas?'),
        SiNo(value: ob.tabaco, onChanged: (v) => n.update((d) => d.copyWith(tabaco: v))).stagger(5),
      ],
    );
  }
}

// ── h2. Alimentación y estrés ────────────────────────────────────────────
class PasoAlimentacion extends ConsumerWidget {
  const PasoAlimentacion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Etiqueta('¿Qué tan bien comes?'),
        MoChoiceGroup<String>(
          options: const {'baja': 'Podría mejorar', 'media': 'Más o menos', 'alta': 'Bastante bien'},
          value: ob.alimentacion,
          onChanged: (v) => n.update((d) => d.copyWith(alimentacion: v)),
        ).stagger(0),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('¿Algo de esto te suena?', opcional: true),
        MultiChips(
          options: Catalogos.alimentacionPatron,
          values: ob.alimentacionPatron,
          onChanged: (s) => n.update((d) => d.copyWith(alimentacionPatron: s)),
        ).stagger(1),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('¿Cómo anda el estrés?'),
        MoChoiceGroup<String>(
          options: const {'baja': 'Bajo', 'media': 'Medio', 'alta': 'Alto'},
          value: ob.estres,
          onChanged: (v) => n.update((d) => d.copyWith(estres: v)),
          wrap: false,
        ).stagger(2),
      ],
    );
  }
}

// ── i. Suplementos ───────────────────────────────────────────────────────
class PasoSuplementos extends ConsumerStatefulWidget {
  const PasoSuplementos({super.key});

  @override
  ConsumerState<PasoSuplementos> createState() => _PasoSuplementosState();
}

class _PasoSuplementosState extends ConsumerState<PasoSuplementos> {
  late final TextEditingController _otros;

  @override
  void initState() {
    super.initState();
    final actuales = ref.read(onboardingProvider).suplementos;
    _otros = TextEditingController(
      text: actuales.where((s) => !Catalogos.suplementosComunes.containsKey(s.nombre)).map((s) => s.nombre).join(', '),
    );
  }

  @override
  void dispose() {
    _otros.dispose();
    super.dispose();
  }

  void _guardar(Set<String> sel, String otros) {
    final lista = [
      for (final k in Catalogos.suplementosComunes.keys)
        if (sel.contains(k)) Suplemento(nombre: k, frecuencia: 'diaria'),
      for (final o in otros.split(','))
        if (o.trim().isNotEmpty) Suplemento(nombre: o.trim(), frecuencia: 'diaria'),
    ];
    ref.read(onboardingProvider.notifier).update((d) => d.copyWith(suplementos: lista));
  }

  @override
  Widget build(BuildContext context) {
    final ob = ref.watch(onboardingProvider);
    final sel = ob.suplementos.map((s) => s.nombre).where(Catalogos.suplementosComunes.containsKey).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MultiChips(
          options: Catalogos.suplementosComunes,
          values: sel,
          onChanged: (s) => _guardar(s, _otros.text),
        ).stagger(0),
        const SizedBox(height: Sp.stackSection),
        TextField(
          controller: _otros,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (t) => _guardar(sel, t),
          decoration: const InputDecoration(
            labelText: 'Otro',
            hintText: 'Colágeno, zinc… separados por coma',
            prefixIcon: Icon(Icons.medication_outlined),
          ),
        ).stagger(1),
      ],
    );
  }
}
