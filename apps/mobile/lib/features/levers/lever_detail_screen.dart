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
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// Detalle de una palanca (flujo D): los mismos futuros, misma semilla, una
/// sola cosa cambiada. Incluye el "¿y si no lo sostengo?" (adherencia) y el
/// CTA "Guardar como mi plan".
class LeverDetailScreen extends ConsumerStatefulWidget {
  const LeverDetailScreen({super.key, required this.index});
  final int index;

  @override
  ConsumerState<LeverDetailScreen> createState() => _LeverDetailScreenState();
}

class _LeverDetailScreenState extends ConsumerState<LeverDetailScreen> {
  /// Factor local por adherencia. El motor aún no simula adherencia (contrato
  /// §3: "Fase 2"); esto es una aproximación para que la pantalla respire.
  static const _factores = <String, double>{'3_meses': .25, '8_meses': .5, '2_anios': .8, 'siempre': 1};
  static const _etiquetas = <String, String>{'3_meses': '3 meses', '8_meses': '8 meses', '2_anios': '2 años', 'siempre': 'Siempre'};
  static const _notas = <String, String>{
    '3_meses': 'Poco, pero no es cero. Nunca es cero.',
    '8_meses': 'Aunque aflojes después, algo de esto se te queda.',
    '2_anios': 'Aquí el cuerpo ya cambió lo que tenía que cambiar.',
    'siempre': 'El escenario ideal. Casi nadie vive aquí, y está bien.',
  };

  String _adherencia = 'siempre';
  bool _esPlan = false;
  int _celebraciones = 0;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final r = ref.read(ultimoResultadoProvider);
    final e = _escenario(r);
    if (r == null || e == null) return;
    final plan = ref.read(simulationRepositoryProvider).plan(r.id);
    if (plan != null && _mismoPlan(plan, e)) {
      _esPlan = true;
      final adh = '${plan['adherencia'] ?? ''}';
      if (_factores.containsKey(adh)) _adherencia = adh;
    }
  }

  Escenario? _escenario(SimulacionResultado? r) {
    if (r == null) return null;
    if (widget.index < 0 || widget.index >= r.escenarios.length) return null;
    return r.escenarios[widget.index];
  }

  static bool _mismoPlan(Map<String, dynamic> plan, Escenario e) {
    final ids = ((plan['intervenciones'] as List?) ?? const []).map((x) => '$x').toSet();
    return ids.length == e.intervenciones.length && ids.containsAll(e.intervenciones);
  }

  Future<void> _guardar(SimulacionResultado r, Escenario e) async {
    setState(() => _guardando = true);
    try {
      await ref.read(simulationRepositoryProvider).guardarPlan(r.id, e.intervenciones, _adherencia);
      if (!mounted) return;
      setState(() {
        _esPlan = true;
        _celebraciones++;
        _guardando = false;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Listo. Lo guardé como tu plan.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('No pude guardarlo ahora. Inténtalo otra vez en un momento.')));
    }
  }

  void _volver() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.levers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = ref.watch(ultimoResultadoProvider);
    final e = _escenario(r);
    if (r == null || e == null) return _NoEncontrado(onBack: _volver);

    final factor = _factores[_adherencia] ?? 1;
    // Ningún delta sin su intervalo: si el rango no viene, uso el punto.
    final (rangoLo, rangoHi) = e.rango.length >= 2 ? (e.rango[0], e.rango[1]) : (e.aniosGanados, e.aniosGanados);
    final restante = (100 - e.pctMejoran).clamp(0, 100);
    final horizonte = r.baseline.anios.isNotEmpty ? r.baseline.anios.last : 10;

    return MoScreen(
      appBar: AppBar(
        title: Text(e.etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: BackButton(onPressed: _volver),
        actions: [
          if (_esPlan)
            const Padding(
              padding: EdgeInsets.only(right: Sp.x4),
              child: MoBadge('Tu plan', tone: MoTone.good, icon: Icons.bookmark_rounded),
            ),
        ],
      ),
      bottom: MoPrimaryButton(
        label: _esPlan ? 'Actualizar mi plan' : 'Guardar como mi plan',
        icon: _esPlan ? Icons.bookmark_rounded : Icons.bookmark_add_rounded,
        good: _esPlan,
        loading: _guardando,
        onPressed: () => _guardar(r, e),
      ),
      children: [
        // Copy de apertura.
        Text.rich(
          TextSpan(
            style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2),
            children: [
              const TextSpan(text: 'Corrí '),
              TextSpan(text: 'los mismos', style: TextStyle(color: MoiraiColors.ink, fontWeight: FontWeight.w800)),
              TextSpan(text: ' ${Fmt.entero(5000)} futuros otra vez, cambiando solo esto. Cada línea verde es la pareja exacta de una gris.'),
            ],
          ),
        ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow),
        const SizedBox(height: Sp.x5),

        // Abanico pareado.
        MoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.draw,
                curve: Motion.soft,
                builder: (_, p, _) => FanChart(
                  edad0: r.edadCronologica,
                  curva: r.baseline,
                  comparacion: e.curva,
                  trayectorias: r.muestraTrayectorias,
                  progress: p,
                  height: 220,
                  etiquetaBase: 'Si sigues igual',
                  etiquetaComparacion: 'Si lo haces',
                ),
              ),
              const SizedBox(height: Sp.x4),
              const Divider(),
              const SizedBox(height: Sp.x4),
              Row(
                children: [
                  _Legend(color: MoiraiColors.ghost, label: 'Si sigues igual · ${Fmt.decimal(r.baseline.final_)}'),
                  const SizedBox(width: Sp.x5),
                  _Legend(color: MoiraiColors.green, label: 'Si lo haces · ${Fmt.decimal(e.curva.final_)}'),
                ],
              ),
              const SizedBox(height: 6),
              Text('Edad biológica en $horizonte años, mediana de los ${Fmt.entero(5000)} futuros.', style: t.bodySmall),
            ],
          ),
        ).stagger(1),
        const SizedBox(height: Sp.stackCard),

        // Dos cifras grandes.
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: MoCard(
                tone: MoTone.good,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigNumber(value: e.aniosGanados, signed: true, decimals: 1, style: t.displaySmall, color: MoiraiColors.greenInk),
                    const SizedBox(height: 4),
                    const MoOverline('Años ganados', color: MoiraiColors.greenInk),
                    const SizedBox(height: 6),
                    Text(Fmt.rangoDelta(rangoLo, rangoHi), style: t.titleLarge!.copyWith(color: MoiraiColors.greenInk)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Sp.x3 + 1),
            Expanded(
              child: MoCard(
                tone: MoTone.brand,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigNumber(value: e.pctMejoran.toDouble(), unit: '%', style: t.displaySmall, color: MoiraiColors.blueInk),
                    const SizedBox(height: 4),
                    const MoOverline('De tus futuros', color: MoiraiColors.blueInk),
                    const SizedBox(height: 6),
                    Text('mejoran con esto', style: t.titleLarge!.copyWith(color: MoiraiColors.blueInk)),
                  ],
                ),
              ),
            ),
          ],
        ).stagger(2),
        const SizedBox(height: Sp.stackCard),

        // El resto.
        MoCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              KeyedSubtree(
                key: ValueKey(_celebraciones),
                child: MoiraiMascot(size: 48, mood: _celebraciones > 0 ? MascotMood.happy : MascotMood.idle)
                    .animate()
                    .scale(begin: const Offset(.8, .8), end: const Offset(1, 1), curve: Motion.bounce, duration: Motion.reveal),
              ),
              const SizedBox(width: Sp.x4),
              Expanded(
                child: Text(
                  'En el ${Fmt.pct(restante)} restante no te hace daño: simplemente algo más pasa primero.',
                  style: t.bodyMedium,
                ),
              ),
            ],
          ),
        ).stagger(3),
        const SizedBox(height: Sp.stackSection),

        // Qué cambia.
        MoSectionTitle(
          e.intervenciones.length == 1 ? 'Qué cambia' : 'Qué cambia (${e.intervenciones.length} cosas)',
          subtitle: 'Lo que le pedí a tus futuros que hicieran distinto.',
        ).stagger(4),
        const SizedBox(height: Sp.x5),
        for (var i = 0; i < e.intervenciones.length; i++) ...[
          _InterventionCard(intervencion: _catalogo(r, e.intervenciones[i])).stagger(5 + i),
          if (i < e.intervenciones.length - 1) const SizedBox(height: Sp.x3 + 1),
        ],
        const SizedBox(height: Sp.stackSection),

        // Pregúntale a Moirai sobre esta palanca (el chat llega enfocado en ella).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(Routes.chatCon(enfoque: 'escenario:${widget.index}')),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Pregúntame sobre esta palanca'),
          ),
        ).stagger(6),
        const SizedBox(height: Sp.stackCard),

        // Adherencia.
        const MoSectionTitle(
          '¿Y si no lo sostengo?',
          subtitle: 'Nadie lo sostiene todo. Prefiero simular lo que de verdad va a pasar.',
        ).stagger(6),
        const SizedBox(height: Sp.x5),
        MoChoiceGroup<String>(
          options: _etiquetas,
          value: _adherencia,
          onChanged: (v) => setState(() => _adherencia = v),
        ).stagger(7),
        const SizedBox(height: Sp.x5),
        MoCard(
          tone: MoTone.good,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BigNumber(
                value: e.aniosGanados * factor,
                signed: true,
                decimals: 1,
                unit: 'años ganados',
                style: t.displayMedium,
                unitStyle: t.titleLarge,
                color: MoiraiColors.greenInk,
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: Motion.base,
                switchInCurve: Motion.out,
                switchOutCurve: Motion.out,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(a), child: child),
                ),
                child: Column(
                  key: ValueKey(_adherencia),
                  children: [
                    Text(
                      Fmt.rangoDelta(rangoLo * factor, rangoHi * factor),
                      style: t.titleLarge!.copyWith(color: MoiraiColors.greenInk),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'si lo sostienes ${_etiquetas[_adherencia]!.toLowerCase()}',
                      style: t.labelMedium!.copyWith(color: MoiraiColors.greenInk),
                    ),
                    const SizedBox(height: Sp.x3),
                    Text(_notas[_adherencia] ?? '', textAlign: TextAlign.center, style: t.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: Sp.x4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.science_outlined, size: 15, color: MoiraiColors.ink3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Aproximación local: el motor aún no simula adherencia; la guardo para cuando lo haga.',
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).stagger(8),
        const SizedBox(height: Sp.stackSection),
        MoFootnote(r.descargo),
      ],
    );
  }

  /// Busca la intervención en el catálogo del resultado; si no viene, en el
  /// catálogo local del motor mock; si tampoco, una genérica con el id.
  static Intervencion _catalogo(SimulacionResultado r, String id) {
    final viaResultado = r.intervencion(id);
    if (viaResultado != null) return viaResultado;
    final viaMock = MockEngine.catalogo.where((c) => c.id == id).firstOrNull;
    if (viaMock != null) return viaMock;
    return Intervencion(id: id, etiqueta: id.replaceAll('_', ' '), esfuerzo: 2, icono: 'spa', descripcion: '');
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _InterventionCard extends StatelessWidget {
  const _InterventionCard({required this.intervencion});
  final Intervencion intervencion;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final i = intervencion;
    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoIconTile(iconoIntervencion(i.id), tone: MoTone.good, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.etiqueta, style: t.titleMedium),
                if (i.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(i.descripcion, style: t.bodyMedium),
                ],
                const SizedBox(height: 8),
                MoBadge(i.esfuerzoLabel, tone: i.esfuerzo <= 2 ? MoTone.good : i.esfuerzo == 3 ? MoTone.sunken : MoTone.watch),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoEncontrado extends StatelessWidget {
  const _NoEncontrado({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoScreen(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      children: [
        const SizedBox(height: Sp.x8),
        const Center(child: MoiraiMascot(size: 110, mood: MascotMood.gentle)),
        const SizedBox(height: Sp.x6),
        Text('No encontré ese escenario', textAlign: TextAlign.center, style: t.headlineMedium),
        const SizedBox(height: Sp.x3),
        Text(
          'Puede que la simulación haya cambiado desde que abriste este enlace. Vuelve a la lista y elige una palanca.',
          textAlign: TextAlign.center,
          style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2),
        ),
        const SizedBox(height: Sp.x7),
        OutlinedButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), label: const Text('Volver a las palancas')),
      ],
    );
  }
}
