import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/mock/mock_engine.dart';
import '../../data/models/simulacion.dart';
import '../../widgets/big_number.dart';
import '../../widgets/fan_chart.dart';
import '../../widgets/lever_card.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';
import 'future_empty_state.dart';

/// Tab "Futuro" (flujo C): la pantalla principal. Titular = edad biológica
/// hoy y proyectada a 10 años con su banda P10–P90; al lado, lo que la mueve.
class FutureScreen extends ConsumerWidget {
  const FutureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(ultimoResultadoProvider);
    if (r == null) return const FutureEmptyState();
    return _FutureBody(r: r, key: ValueKey(r.id));
  }
}

class _FutureBody extends StatelessWidget {
  const _FutureBody({super.key, required this.r});
  final SimulacionResultado r;

  /// Umbral bajo el cual no vale la pena pedirle nada al usuario.
  static const _umbralAccion = 0.5;

  @override
  Widget build(BuildContext context) {
    final estasBien = r.mejorDecision.aniosGanados < _umbralAccion;
    return MoScreen(
      children: [
        _Header(r: r),
        const SizedBox(height: Sp.x6),
        _HeroCard(r: r).stagger(1),
        const SizedBox(height: Sp.stackCard),
        _ProjectionCard(r: r).stagger(2),
        const SizedBox(height: Sp.stackSection),
        if (estasBien) ...[
          _EstasBien(r: r).stagger(3),
          const SizedBox(height: Sp.stackSection),
        ] else ...[
          _LeversSection(r: r).stagger(3),
          const SizedBox(height: Sp.stackSection),
          _TwinCard(r: r).stagger(4),
          const SizedBox(height: Sp.stackSection),
        ],
        _WhySection(r: r).stagger(5),
        const SizedBox(height: Sp.stackSection),
        _PopulationCard(r: r).stagger(6),
        const SizedBox(height: Sp.stackCard),
        _UncertaintyNotice(r: r).stagger(7),
        const SizedBox(height: Sp.stackSection),
        MoFootnote(r.descargo),
      ],
    );
  }
}

// ── Encabezado ───────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text('Tu futuro', style: t.headlineLarge)),
            MoBadge(
              '${r.escenarios.length} escenarios · ${Fmt.entero(5000)} futuros',
              tone: MoTone.brand,
              icon: Icons.auto_awesome_rounded,
            ),
          ],
        ),
        const SizedBox(height: Sp.x3),
        Text('Esto es lo que vi cuando recorrí tus futuros.', style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2)),
      ],
    ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow);
  }
}

// ── Hero: edad biológica hoy ─────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      tone: MoTone.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoOverline('Edad biológica hoy', color: MoiraiColors.blueInk),
          const SizedBox(height: Sp.x3),
          BigNumber(
            value: r.edadBiologicaHoy,
            decimals: 1,
            unit: 'años',
            style: t.displayLarge,
            unitStyle: t.titleLarge,
            color: MoiraiColors.blueInk,
          ),
          const SizedBox(height: Sp.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('tu edad es ', style: t.headlineSmall!.copyWith(color: MoiraiColors.ink2)),
              Text('${r.edadCronologica}', style: t.displaySmall),
            ],
          ),
          const SizedBox(height: Sp.x4),
          _DeltaBadge(delta: r.delta),
          const SizedBox(height: Sp.x4),
          Text(
            'PhenoAge (Levine 2018) a partir de tus biomarcadores. Es una medida de hoy, no una predicción.',
            style: t.bodySmall!.copyWith(color: MoiraiColors.blueInk.withValues(alpha: .8)),
          ),
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});
  final double delta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final neutro = delta.abs() < 0.05;
    final abajo = delta <= 0;
    final (bg, fg) = abajo ? (MoiraiColors.greenSoft, MoiraiColors.greenInk) : (MoiraiColors.amberSoft, MoiraiColors.amberInk);
    final unidad = (delta.abs() - 1).abs() < 0.05 ? 'año' : 'años';
    final texto = neutro ? 'justo en tu edad' : '${Fmt.delta(delta)} $unidad ${abajo ? 'por debajo' : 'por encima'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Rad.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(abajo ? Icons.south_rounded : Icons.north_rounded, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(texto, style: t.titleMedium!.copyWith(color: fg)),
        ],
      ),
    ).animate().fadeIn(delay: Motion.count, duration: Motion.slow).scale(begin: const Offset(.9, .9), end: const Offset(1, 1), delay: Motion.count, curve: Motion.bounce, duration: Motion.reveal);
  }
}

// ── Proyección a 10 años (abanico) ───────────────────────────────────────
class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = r.baseline;
    final horizonte = c.anios.isNotEmpty ? c.anios.last : 10;
    final hoy = r.edadBiologicaHoy;
    return MoCard(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.draw,
        curve: Motion.soft,
        builder: (_, p, _) {
          double lerp(double fin) => hoy + (fin - hoy) * p;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: MoOverline('Edad biológica en $horizonte años')),
                  const MoBadge('banda P10–P90', icon: Icons.stacked_line_chart_rounded),
                ],
              ),
              const SizedBox(height: Sp.x3),
              FanChart(
                edad0: r.edadCronologica,
                curva: c,
                trayectorias: r.muestraTrayectorias,
                progress: p,
                height: 230,
                etiquetaBase: '+$horizonte años → ${Fmt.decimal(c.final_)}',
              ),
              const SizedBox(height: Sp.x5),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'En $horizonte años: ', style: t.headlineSmall!.copyWith(color: MoiraiColors.ink2)),
                    TextSpan(text: Fmt.decimal(lerp(c.mediana.last)), style: t.headlineLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    TextSpan(text: ' · ', style: t.headlineSmall!.copyWith(color: MoiraiColors.ink3)),
                    TextSpan(
                      text: Fmt.rango(lerp(c.p10.last), lerp(c.p90.last)),
                      style: t.headlineSmall!.copyWith(color: MoiraiColors.blueInk, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Sp.x3),
              Row(
                children: [
                  Container(width: 30, height: 4, decoration: BoxDecoration(color: MoiraiColors.blue.withValues(alpha: .45), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Ese rango no es un detalle: es lo que todavía no sé de ti.', style: t.bodySmall)),
                ],
              ),
              const SizedBox(height: Sp.x4),
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: MoiraiColors.ink3),
                  const SizedBox(width: 6),
                  Text('Estimación, no diagnóstico.', style: t.labelMedium!.copyWith(color: MoiraiColors.ink3)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Lo que puedes mover (top 2) ──────────────────────────────────────────
class _LeversSection extends StatelessWidget {
  const _LeversSection({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final top = r.escenarios.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MoSectionTitle('Lo que puedes mover', subtitle: 'Ordenadas por años ganados por unidad de esfuerzo. Toca una para ver los futuros pareados.'),
        const SizedBox(height: Sp.x5),
        for (var i = 0; i < top.length; i++) ...[
          LeverCard(
            escenario: top[i],
            destacada: i == 0,
            rank: i + 1,
            onTap: () => context.go(Routes.leverDetail(i)),
          ).stagger(i, base: const Duration(milliseconds: 120)),
          if (i < top.length - 1) const SizedBox(height: Sp.x4),
        ],
        const SizedBox(height: Sp.x3),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.go(Routes.levers),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Ver todas las palancas'),
          ),
        ),
      ],
    );
  }
}

// ── Tu gemelo ────────────────────────────────────────────────────────────
class _TwinCard extends StatelessWidget {
  const _TwinCard({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoiraiMascot(size: 58, mood: MascotMood.happy),
          const SizedBox(width: Sp.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MoOverline('Tu gemelo'),
                const SizedBox(height: 6),
                Text(r.veredicto, style: t.titleMedium),
                if (r.porque.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.porque, style: t.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Por qué (SHAP) ───────────────────────────────────────────────────────
class _WhySection extends StatelessWidget {
  const _WhySection({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final drivers = r.shap;
    final maxAbs = drivers.fold<double>(0, (m, d) => d.contribucion.abs() > m ? d.contribucion.abs() : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MoSectionTitle('Por qué', subtitle: 'Qué pesa en tu edad biológica de hoy, de mayor a menor.'),
        const SizedBox(height: Sp.x5),
        MoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (drivers.isEmpty)
                Text('Todavía no tengo suficiente para explicarte el porqué. Con tus exámenes completos sí puedo.', style: t.bodyMedium)
              else
                for (var i = 0; i < drivers.length; i++) ...[
                  _ShapRow(driver: drivers[i], fraccion: maxAbs == 0 ? 0 : drivers[i].contribucion.abs() / maxAbs, index: i),
                  if (i < drivers.length - 1) const SizedBox(height: Sp.x5),
                ],
              const SizedBox(height: Sp.x5),
              Row(
                children: [
                  _Dot(MoiraiColors.green),
                  const SizedBox(width: 5),
                  Text('te rejuvenece', style: t.labelMedium),
                  const SizedBox(width: Sp.x4),
                  _Dot(MoiraiColors.amber),
                  const SizedBox(width: 5),
                  Text('te envejece', style: t.labelMedium),
                ],
              ),
              const SizedBox(height: Sp.x3),
              Text('Estos son los factores que más mueven tu edad biológica hoy.', style: t.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _ShapRow extends StatelessWidget {
  const _ShapRow({required this.driver, required this.fraccion, required this.index});
  final ShapDriver driver;
  final double fraccion;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mejora = driver.direccion == 'mejora';
    final color = mejora ? MoiraiColors.green : MoiraiColors.amber;
    final ink = mejora ? MoiraiColors.greenInk : MoiraiColors.amberInk;
    final nombre = _capital(MockEngine.nombreVariable(driver.variable));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(nombre, style: t.titleSmall)),
            const SizedBox(width: Sp.x3),
            Text('${Fmt.delta(driver.contribucion)} años', style: t.titleMedium!.copyWith(color: ink, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(Rad.xs),
          child: SizedBox(
            height: 10,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: MoiraiColors.surface2)),
                FractionallySizedBox(
                  widthFactor: fraccion.clamp(0.04, 1),
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Rad.xs))),
                )
                    .animate(delay: Duration(milliseconds: 200 + 90 * index))
                    .scaleX(begin: 0, end: 1, alignment: Alignment.centerLeft, duration: Motion.reveal, curve: Motion.out),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Frente a personas como tú (NHANES) ───────────────────────────────────
class _PopulationCard extends StatelessWidget {
  const _PopulationCard({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = r.percentilPoblacional.clamp(0, 100);
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoOverline('Frente a personas como tú'),
          const SizedBox(height: Sp.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Percentil ', style: t.headlineSmall!.copyWith(color: MoiraiColors.ink2)),
              BigNumber(value: p.toDouble(), style: t.headlineLarge, color: MoiraiColors.blueInk),
              const SizedBox(width: 8),
              Text('de tu grupo de edad y sexo', style: t.bodySmall),
            ],
          ),
          const SizedBox(height: Sp.x5),
          _PercentileMeter(percentil: p),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('más joven', style: t.labelSmall!.copyWith(letterSpacing: 0)),
              const Spacer(),
              Text('mayor edad biológica', style: t.labelSmall!.copyWith(letterSpacing: 0)),
            ],
          ),
          const SizedBox(height: Sp.x5),
          Text(r.mensajePoblacional, style: t.bodyMedium!.copyWith(color: MoiraiColors.ink)),
          const SizedBox(height: Sp.x3),
          Row(
            children: [
              const Icon(Icons.public_rounded, size: 14, color: MoiraiColors.ink3),
              const SizedBox(width: 6),
              Text('Fuente: NHANES', style: t.labelMedium!.copyWith(color: MoiraiColors.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PercentileMeter extends StatelessWidget {
  const _PercentileMeter({required this.percentil});
  final int percentil;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percentil / 100),
      duration: Motion.draw,
      curve: Motion.out,
      builder: (_, f, _) => SizedBox(
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rad.pill),
                gradient: const LinearGradient(colors: [MoiraiColors.greenSoft, MoiraiColors.blueSoft, MoiraiColors.amberSoft]),
              ),
            ),
            Align(
              alignment: Alignment(-1 + 2 * f, 0),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: MoiraiColors.action,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: MoiraiColors.action.withValues(alpha: .35), blurRadius: 8, offset: const Offset(0, 3))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Incertidumbre + qué medir ────────────────────────────────────────────
class _UncertaintyNotice extends StatelessWidget {
  const _UncertaintyNotice({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoNotice(text: r.incertidumbre, tone: MoTone.brand, icon: Icons.blur_on_rounded),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.push(Routes.whatToMeasure),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('¿Qué te conviene medir?'),
          ),
        ),
      ],
    );
  }
}

// ── Variante "Estás bien" ────────────────────────────────────────────────
class _EstasBien extends StatelessWidget {
  const _EstasBien({required this.r});
  final SimulacionResultado r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: MoiraiMascot(size: 116, mood: MascotMood.happy)),
        const SizedBox(height: Sp.x5),
        Text('No encontré nada\nque requiera acción', textAlign: TextAlign.center, style: t.headlineMedium),
        const SizedBox(height: Sp.x4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
          child: Text(
            'En serio. Revisé tus ${Fmt.entero(5000)} futuros y ninguno cambia mucho con lo que podrías hacer distinto hoy.',
            textAlign: TextAlign.center,
            style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2),
          ),
        ),
        const SizedBox(height: Sp.x6),
        MoCard(
          tone: MoTone.good,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lo único que te sugiero', style: t.titleSmall!.copyWith(color: MoiraiColors.greenInk)),
              const SizedBox(height: 6),
              Text('Seguir como vas. Lo que ya haces es la razón por la que este resultado se ve así.', style: t.bodyLarge),
              if (r.escenarios.isNotEmpty && r.mejorDecision.rango.length >= 2) ...[
                const SizedBox(height: Sp.x3),
                Text(
                  'La palanca que más suma, ${r.mejorDecision.etiqueta.toLowerCase()}, apenas mueve ${Fmt.delta(r.mejorDecision.aniosGanados)} años (${Fmt.rangoDelta(r.mejorDecision.rango[0], r.mejorDecision.rango[1])}).',
                  style: t.bodySmall!.copyWith(color: MoiraiColors.greenInk),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Sp.stackCard),
        MoCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: MoiraiColors.ink3, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('Vuelve en seis meses, o cuando tengas exámenes nuevos.', style: t.bodyMedium)),
            ],
          ),
        ),
        const SizedBox(height: Sp.x5),
        const MoFootnote('No te voy a inventar un problema para que vuelvas.'),
        if (r.escenarios.isNotEmpty) ...[
          const SizedBox(height: Sp.x3),
          Center(
            child: TextButton(
              onPressed: () => context.go(Routes.levers),
              child: const Text('Ver las palancas de todos modos'),
            ),
          ),
        ],
      ],
    );
  }
}
