import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme/theme.dart';

class MoiraiApp extends ConsumerStatefulWidget {
  const MoiraiApp({super.key});

  @override
  ConsumerState<MoiraiApp> createState() => _MoiraiAppState();
}

class _MoiraiAppState extends ConsumerState<MoiraiApp> {
  @override
  void initState() {
    super.initState();
    // Solo si ya había una sesión guardada (arranque en frío con token en
    // el keychain): confirma que sigue viva y, si esta cuenta ya terminó el
    // onboarding en otro dispositivo, evita repetirlo aquí. Best-effort — no
    // bloquea el primer frame, y sin red no rompe nada.
    if (ref.read(authNotifierProvider).signedIn) {
      unawaited(() async {
        await ref.read(authRepositoryProvider).validarSesion();
        if (ref.read(authNotifierProvider).signedIn) {
          await ref.read(onboardingProvider.notifier).hydrateFromBackend();
        }
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Moirai',
      debugShowCheckedModeBanner: false,
      theme: MoiraiTheme.light(),
      routerConfig: router,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Misma escala de texto en todos lados; evita layouts rotos con fuentes gigantes.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: .9, maxScaleFactor: 1.2)),
          child: child!,
        );
      },
    );
  }
}
