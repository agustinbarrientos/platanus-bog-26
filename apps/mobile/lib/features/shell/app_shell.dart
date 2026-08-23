import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';

/// Shell con la navegación inferior: Futuro · Simular · Pregúntame · Perfil.
/// (Respaldo no es pestaña: se abre desde la esquina de "Tu futuro".)
/// Glass (blur) para que el contenido pase por debajo.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: MoiraiColors.line)),
            ),
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'Futuro'),
                NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'Simular'),
                NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Pregúntame'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
