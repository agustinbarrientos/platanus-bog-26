import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// A1 · Bienvenida. La mascota se presenta y pide muy poco.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MoiraiMascot(size: 132)
                            .animate()
                            .scale(begin: const Offset(.6, .6), end: const Offset(1, 1), duration: Motion.reveal, curve: Motion.bounce)
                            .fadeIn(duration: Motion.slow),
                        const SizedBox(height: 26),
                        Text('Hola, soy Moirai.', style: t.headlineLarge, textAlign: TextAlign.center)
                            .animate(delay: const Duration(milliseconds: 160))
                            .fadeIn(duration: Motion.slow, curve: Motion.out)
                            .slideY(begin: .1, end: 0, duration: Motion.slow, curve: Motion.out),
                        const SizedBox(height: Sp.x3),
                        // Quién es, en una línea: la medusa que revierte su reloj celular.
                        // La misma presentación que hace en el chat.
                        Text(
                          'La medusa que sabe devolver su reloj.',
                          style: t.labelMedium!.copyWith(color: MoiraiColors.ink3, letterSpacing: .4),
                          textAlign: TextAlign.center,
                        )
                            .animate(delay: const Duration(milliseconds: 220))
                            .fadeIn(duration: Motion.slow, curve: Motion.out),
                        const SizedBox(height: Sp.x4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2, height: 1.55),
                              children: const [
                                TextSpan(text: 'Necesito muy poco para empezar. Con pocos datos puedo simular '),
                                TextSpan(
                                  text: 'miles de versiones',
                                  style: TextStyle(color: MoiraiColors.ink, fontWeight: FontWeight.w800),
                                ),
                                TextSpan(text: ' de tu futuro y mostrarte cuáles dependen de ti.'),
                              ],
                            ),
                          ),
                        )
                            .animate(delay: const Duration(milliseconds: 280))
                            .fadeIn(duration: Motion.slow, curve: Motion.out)
                            .slideY(begin: .1, end: 0, duration: Motion.slow, curve: Motion.out),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.x5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoPrimaryButton(label: 'Empieza', onPressed: () => context.go(Routes.register)),
                    const SizedBox(height: Sp.x3),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => context.go(Routes.login),
                        child: const Text('Ya tengo cuenta'),
                      ),
                    ),
                    const SizedBox(height: Sp.x2),
                    const MoFootnote('No te voy a pedir nada que no necesite.'),
                  ],
                ),
              )
                  .animate(delay: const Duration(milliseconds: 420))
                  .fadeIn(duration: Motion.slow, curve: Motion.out)
                  .slideY(begin: .15, end: 0, duration: Motion.slow, curve: Motion.out),
            ],
          ),
        ),
      ),
    );
  }
}
