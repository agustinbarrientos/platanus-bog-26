import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/simulacion.dart';
import '../../data/repositories/simulation_repository.dart';
import '../../widgets/big_number.dart';
import '../../widgets/fan_chart.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

enum _Fase { idle, running, done, failed }

_Fase _faseDe(SimState s) => switch (s) {
      SimIdle() => _Fase.idle,
      SimRunning() => _Fase.running,
      SimDone() => _Fase.done,
      SimFailed() => _Fase.failed,
    };

/// B · Simulando en vivo. Reemplaza al spinner: las trayectorias se dibujan
/// una por una y el contador de vidas sube de verdad. Al terminar, la mediana
/// y la banda se revelan sobre las vidas y pasamos a "Tu futuro".
class SimulatingScreen extends ConsumerStatefulWidget {
  const SimulatingScreen({super.key});

  @override
  ConsumerState<SimulatingScreen> createState() => _SimulatingScreenState();
}

class _SimulatingScreenState extends ConsumerState<SimulatingScreen> with TickerProviderStateMixin {
  /// Cuántas líneas se ven (animado para que aparezcan de a una aunque el
  /// stream emita en bloques).
  late final AnimationController _lineas = AnimationController.unbounded(vsync: this);

  /// Dibujo de la curva final de izquierda a derecha (0→1).
  late final AnimationController _revelado = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  /// Progreso actual: solo el contador y el abanico lo escuchan, la pantalla
  /// entera no se reconstruye por evento del stream.
  final _progreso = ValueNotifier<SimulacionProgreso>(const SimulacionProgreso(fraccion: 0, vidas: 0, totalVidas: SimulationRepository.nTrayectorias));
  SimulacionResultado? _resultado;
  bool _terminando = false;
  bool _hojaAbierta = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(simulationProvider);
      if (s is SimIdle) {
        ref.read(simulationProvider.notifier).start();
      } else {
        _aplicar(s);
      }
    });
  }

  @override
  void dispose() {
    _lineas.dispose();
    _revelado.dispose();
    _progreso.dispose();
    super.dispose();
  }

  // ── Reacción al estado ─────────────────────────────────────────────────
  void _aplicar(SimState s) {
    switch (s) {
      case SimRunning(:final progreso):
        // Nueva corrida (p. ej. "Intentar de nuevo"): arrancar de cero.
        if (progreso.vidas == 0 && (_terminando || _lineas.value > 0)) _reiniciar();
        _progreso.value = progreso;
        _animarLineas(progreso.trayectoriasParciales.length, porLinea: 45);
      case SimDone(:final resultado):
        if (_terminando) return;
        _terminando = true;
        _resultado = resultado;
        final prev = _progreso.value;
        final total = prev.totalVidas > 1 ? prev.totalVidas : SimulationRepository.nTrayectorias;
        final tray = resultado.muestraTrayectorias.isNotEmpty ? resultado.muestraTrayectorias : prev.trayectoriasParciales;
        _progreso.value = SimulacionProgreso(fraccion: 1, vidas: total, totalVidas: total, trayectoriasParciales: tray);
        _animarLineas(tray.length, porLinea: 12);
        _revelado.forward(from: 0);
        Future<void>.delayed(const Duration(milliseconds: 1400), _irAlFuturo);
      case SimFailed():
        _revelado.value = 0;
      case SimIdle():
        break;
    }
  }

  void _reiniciar() {
    _terminando = false;
    _resultado = null;
    _lineas.stop();
    _lineas.value = 0;
    _revelado.value = 0;
  }

  void _animarLineas(int objetivo, {required int porLinea}) {
    final faltan = objetivo - _lineas.value;
    if (faltan <= 0) return;
    _lineas.animateTo(
      objetivo.toDouble(),
      duration: Duration(milliseconds: math.max(220, (faltan * porLinea).round())),
      curve: Curves.linear,
    );
  }

  void _irAlFuturo() {
    if (!mounted) return;
    if (_hojaAbierta) {
      Navigator.of(context, rootNavigator: true).pop();
      _hojaAbierta = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(Routes.future);
    });
  }

  void _reintentar() {
    _reiniciar();
    ref.read(simulationProvider.notifier).start();
  }

  void _volver() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.examsUpload);
    }
  }

  Future<void> _salir() async {
    _hojaAbierta = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _HojaFondo(
        progreso: _progreso,
        onEsperar: () => Navigator.of(ctx).pop(),
        onInicio: () {
          Navigator.of(ctx).pop();
          context.go(Routes.future);
        },
      ),
    );
    _hojaAbierta = false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fase = ref.watch(simulationProvider.select(_faseDe));
    final mensajeFallo = ref.watch(simulationProvider.select((s) => s is SimFailed ? s.message : null));
    final edad0 = ref.watch(simulacionInputProvider.select((i) => i.edad));
    ref.listen<SimState>(simulationProvider, (_, next) => _aplicar(next));

    final mood = switch (fase) {
      _Fase.done => MascotMood.happy,
      _Fase.failed => MascotMood.gentle,
      _ => MascotMood.working,
    };
    final (titulo, sub) = switch (fase) {
      _Fase.done => ('Listo. Encontré lo que sí depende de ti.', 'Te muestro lo que más mueve tu futuro.'),
      _Fase.failed => ('No alcancé a terminar', mensajeFallo ?? 'La simulación no terminó. Intenta de nuevo.'),
      _ => ('Estoy recorriendo tus futuros', 'Cada línea es una versión posible de tu vida. Ninguna es una predicción por sí sola.'),
    };

    return MoScreen(
      bottom: AnimatedSwitcher(
        duration: Motion.slow,
        switchInCurve: Motion.out,
        child: switch (fase) {
          _Fase.failed => Column(
              key: const ValueKey('fallo'),
              mainAxisSize: MainAxisSize.min,
              children: [
                MoPrimaryButton(label: 'Intentar de nuevo', icon: Icons.refresh_rounded, onPressed: _reintentar),
                const SizedBox(height: Sp.x3),
                TextButton(onPressed: _volver, child: const Text('Volver')),
              ],
            ),
          _Fase.done => const SizedBox(key: ValueKey('listo'), height: 54),
          _ => OutlinedButton.icon(
              key: const ValueKey('salir'),
              onPressed: _salir,
              icon: const Icon(Icons.notifications_none_rounded, size: 20),
              label: const Text('Avísame y déjame salir'),
            ),
        },
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MoiraiMascot(size: 64, mood: mood),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.reveal,
                switchInCurve: Motion.out,
                switchOutCurve: Motion.soft,
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                child: Column(
                  key: ValueKey(fase),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(titulo, style: t.headlineMedium),
                    const SizedBox(height: Sp.x3),
                    Text(sub, style: t.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow),
        const SizedBox(height: Sp.x6),
        MoCard(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          child: RepaintBoundary(
            child: ValueListenableBuilder<SimulacionProgreso>(
              valueListenable: _progreso,
              builder: (_, p, _) => AnimatedBuilder(
                animation: Listenable.merge([_lineas, _revelado]),
                builder: (_, _) {
                  final listo = _resultado != null;
                  return FanChart(
                    edad0: edad0,
                    curva: listo ? _resultado!.baseline : null,
                    trayectorias: p.trayectoriasParciales,
                    trayectoriasVisibles: math.min(_lineas.value.floor(), p.trayectoriasParciales.length),
                    progress: listo ? Motion.out.transform(_revelado.value) : 1,
                    height: 260,
                    identidad: true,
                    etiquetaBase: listo ? 'tu mediana' : null,
                  );
                },
              ),
            ),
          ),
        ).animate(delay: 120.ms).fadeIn(duration: Motion.reveal).scale(begin: const Offset(.97, .97), end: const Offset(1, 1), curve: Motion.out, duration: Motion.reveal),
        const SizedBox(height: Sp.x7),
        _Contador(progreso: _progreso).animate(delay: 240.ms).fadeIn(duration: Motion.reveal),
        const SizedBox(height: Sp.x4),
        Center(
          child: AnimatedOpacity(
            duration: Motion.slow,
            opacity: fase == _Fase.running || fase == _Fase.idle ? 1 : 0,
            child: const MoFootnote('Estimación, no diagnóstico.'),
          ),
        ),
      ],
    );
  }
}

/// Número grande con count-up + barra fina. Escucha solo el progreso.
class _Contador extends StatelessWidget {
  const _Contador({required this.progreso});
  final ValueNotifier<SimulacionProgreso> progreso;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<SimulacionProgreso>(
      valueListenable: progreso,
      builder: (_, p, _) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              BigNumber(
                value: p.vidas.toDouble(),
                style: t.displaySmall!.copyWith(fontSize: 46, fontWeight: FontWeight.w600),
                color: MoiraiColors.greenInk,
                duration: Motion.reveal,
              ),
              const SizedBox(width: 8),
              Text('de ${Fmt.entero(p.totalVidas)}', style: t.titleMedium!.copyWith(color: MoiraiColors.ink2)),
            ],
          ),
          const SizedBox(height: Sp.x4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p.fraccion.clamp(0, 1)),
            duration: Motion.reveal,
            curve: Motion.out,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 7,
              borderRadius: BorderRadius.circular(Rad.pill),
              color: MoiraiColors.green,
              backgroundColor: MoiraiColors.surface2,
            ),
          ),
          const SizedBox(height: Sp.x3),
          const MoOverline('vidas simuladas'),
        ],
      ),
    );
  }
}

/// Hoja "Sigo trabajando en esto" (SimulandoFondo).
class _HojaFondo extends StatelessWidget {
  const _HojaFondo({required this.progreso, required this.onEsperar, required this.onInicio});
  final ValueNotifier<SimulacionProgreso> progreso;
  final VoidCallback onEsperar;
  final VoidCallback onInicio;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Sp.x7, Sp.x3, Sp.x7, Sp.x5 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MoiraiMascot(size: 110, mood: MascotMood.working),
            const SizedBox(height: Sp.x5),
            Text('Sigo trabajando en esto', style: t.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: Sp.x4),
            Text(
              'Me toma un momento hacerlo bien. Te aviso apenas termine, puedes cerrar la app tranquila.',
              style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Sp.x5),
            ValueListenableBuilder<SimulacionProgreso>(
              valueListenable: progreso,
              builder: (_, p, _) => MoBadge('Van ${Fmt.entero(p.vidas)} de ${Fmt.entero(p.totalVidas)}', tone: MoTone.brand, icon: Icons.schedule_rounded),
            ),
            const SizedBox(height: Sp.x7),
            MoPrimaryButton(label: 'Prefiero esperar aquí', onPressed: onEsperar),
            const SizedBox(height: Sp.x3),
            TextButton(onPressed: onInicio, child: const Text('Ir al inicio')),
          ],
        ),
      ),
    ).animate().fadeIn(duration: Motion.slow);
  }
}
