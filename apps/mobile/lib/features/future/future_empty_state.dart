import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/simulacion.dart';
import '../../data/repositories/demo_data.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// Estado vacío compartido por "Futuro" y "Simular" mientras no hay resultado.
/// Si hay una simulación corriendo, muestra una card compacta que lleva de
/// vuelta a "Simulando en vivo".
class FutureEmptyState extends ConsumerWidget {
  const FutureEmptyState({
    super.key,
    this.title = 'Todavía no he recorrido tus futuros',
    this.subtitle = 'Cuéntame un poco de ti y corro 5.000 versiones de tu futuro para ver qué depende de ti.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final sim = ref.watch(simulationProvider);
    final running = sim is SimRunning ? sim.progreso : null;

    return MoScreen(
      children: [
        const SizedBox(height: Sp.x9),
        Center(
          child: MoiraiMascot(size: 136, mood: running != null ? MascotMood.working : MascotMood.idle),
        ).animate().fadeIn(duration: Motion.slow).scale(begin: const Offset(.88, .88), end: const Offset(1, 1), curve: Motion.bounce, duration: Motion.reveal),
        const SizedBox(height: Sp.x7),
        Text(title, textAlign: TextAlign.center, style: t.headlineMedium).stagger(1),
        const SizedBox(height: Sp.x4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
          child: Text(subtitle, textAlign: TextAlign.center, style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2)),
        ).stagger(2),
        const SizedBox(height: Sp.x8),
        if (running != null) ...[
          _RunningCard(progreso: running).stagger(3),
          const SizedBox(height: Sp.x4),
          Center(
            child: TextButton(
              onPressed: () => context.go(Routes.simulating),
              child: const Text('Ver cómo va'),
            ),
          ).stagger(4),
        ] else ...[
          MoPrimaryButton(
            label: 'Simular mis futuros',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => context.go(Routes.examsUpload),
          ).stagger(3),
          const SizedBox(height: Sp.x3),
          Center(
            child: TextButton(
              onPressed: () {
                ref.read(simulationProvider.notifier).start(input: DemoData.perfil());
                context.go(Routes.simulating);
              },
              child: const Text('Probar con un caso de ejemplo'),
            ),
          ).stagger(4),
          Center(
            child: TextButton.icon(
              onPressed: () => context.push(Routes.chat),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('Pregúntale a Moirai'),
            ),
          ).stagger(5),
        ],
        const SizedBox(height: Sp.x6),
        const MoFootnote('No te voy a pedir nada que no necesite.'),
      ],
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.progreso});
  final SimulacionProgreso progreso;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      tone: MoTone.brand,
      onTap: () => context.go(Routes.simulating),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          const MoiraiMascot(size: 44, mood: MascotMood.working),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sigo simulando…', style: t.titleMedium!.copyWith(color: MoiraiColors.blueInk)),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.entero(progreso.vidas)} de ${Fmt.entero(progreso.totalVidas)} futuros',
                  style: t.bodySmall!.copyWith(color: MoiraiColors.blueInk),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Rad.xs),
                  child: LinearProgressIndicator(value: progreso.fraccion.clamp(0, 1), minHeight: 6, backgroundColor: MoiraiColors.surface),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: MoiraiColors.blueInk),
        ],
      ),
    );
  }
}
