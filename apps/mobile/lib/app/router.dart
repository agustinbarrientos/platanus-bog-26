import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/backing/backing_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/exams/exams_confirm_screen.dart';
import '../features/exams/exams_upload_screen.dart';
import '../features/future/future_screen.dart';
import '../features/future/what_to_measure_screen.dart';
import '../features/levers/lever_detail_screen.dart';
import '../features/levers/levers_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/report/report_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/simulation/simulating_screen.dart';
import 'providers.dart';

/// Rutas de la app. Mantener sincronizado con el flujo de pantallas de
/// CLAUDE.md: A ingreso → B simulación → C futuro → D simular → E respaldo
/// (E se abre desde el encabezado de C; el chat "Pregúntame" es pestaña).
abstract final class Routes {
  static const welcome = '/bienvenida';
  static const login = '/login';
  static const register = '/registro';
  static const onboarding = '/onboarding';
  static const examsUpload = '/examenes';
  static const examsConfirm = '/examenes/confirmar';
  static const simulating = '/simulando';
  static const future = '/futuro';
  static const whatToMeasure = '/futuro/que-medir';
  static const levers = '/palancas';
  static String leverDetail(int i) => '/palancas/$i';
  static const backing = '/respaldo';
  static const profile = '/perfil';

  /// "Tu reporte" (el PDF para el médico, y su vista en pantalla). Push desde
  /// "Tu futuro" y desde Perfil; vive fuera del shell como Respaldo.
  static const report = '/reporte';

  /// Pestaña "Pregúntame" del shell (chat sin enfoque, con el bottom nav).
  static const preguntame = '/preguntame';

  /// Chat a pantalla completa (push): es el que recibe `enfoque`/`q`.
  static const chat = '/chat';

  /// Chat abierto "sobre algo": `enfoque` sesga la recuperación del backend
  /// (`escenario:<i>`, `porque`, `incertidumbre`, `biomarcador:<nombre>`,
  /// `medir`, `poblacion`) y `pregunta` se envía sola al entrar.
  static String chatCon({String? enfoque, String? pregunta}) => Uri(
    path: chat,
    queryParameters: {
      if (enfoque != null && enfoque.isNotEmpty) 'enfoque': enfoque,
      if (pregunta != null && pregunta.isNotEmpty) 'q': pregunta,
    },
  ).toString();
}

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authNotifierProvider, (_, _) => refresh.ping());
  ref.listen(onboardingDoneProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.future,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final signedIn = ref.read(authNotifierProvider).signedIn;
      final done = ref.read(onboardingDoneProvider);
      final loc = state.matchedLocation;
      final enAuth = loc == Routes.welcome || loc == Routes.login || loc == Routes.register;

      if (!signedIn) return enAuth ? null : Routes.welcome;
      if (!done) {
        final permitido = loc.startsWith(Routes.onboarding) || loc.startsWith(Routes.examsUpload) || loc == Routes.simulating;
        return permitido ? null : Routes.onboarding;
      }
      if (enAuth || loc == Routes.onboarding) return Routes.future;
      return null;
    },
    routes: [
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: Routes.examsUpload,
        builder: (_, _) => const ExamsUploadScreen(),
        routes: [GoRoute(path: 'confirmar', builder: (_, _) => const ExamsConfirmScreen())],
      ),
      GoRoute(path: Routes.simulating, builder: (_, _) => const SimulatingScreen()),
      // Respaldo vive fuera del shell: se abre desde la esquina de "Tu futuro".
      GoRoute(path: Routes.backing, builder: (_, _) => const BackingScreen()),
      GoRoute(path: Routes.report, builder: (_, _) => const ReportScreen()),
      GoRoute(
        path: Routes.chat,
        builder: (_, s) => ChatScreen(enfoque: s.uri.queryParameters['enfoque'], preguntaInicial: s.uri.queryParameters['q']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.future,
              builder: (_, _) => const FutureScreen(),
              routes: [GoRoute(path: 'que-medir', builder: (_, _) => const WhatToMeasureScreen())],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.levers,
              builder: (_, _) => const LeversScreen(),
              routes: [
                GoRoute(
                  path: ':index',
                  builder: (_, s) => LeverDetailScreen(index: int.tryParse(s.pathParameters['index'] ?? '') ?? 0),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.preguntame, builder: (_, _) => const ChatScreen(enPestana: true))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});
