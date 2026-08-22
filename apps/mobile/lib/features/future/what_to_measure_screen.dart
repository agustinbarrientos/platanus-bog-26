import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/biomarcador.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// "¿Qué te conviene medir?": qué biomarcador faltante (imputado) angostaría
/// más la banda P10–P90 si lo midieras. El ranking es una heurística local
/// (pesos fijos normalizados sobre lo que falta); el motor todavía no calcula
/// valor de información.
class WhatToMeasureScreen extends ConsumerWidget {
  const WhatToMeasureScreen({super.key});

  /// Cuánto suele angostar el rango cada biomarcador cuando deja de estar
  /// imputado (aproximación propia, no del motor).
  static const _pesos = <String, double>{
    'hs_CRP': .30,
    'glucosa': .22,
    'rdw': .14,
    'albumina': .10,
    'creatinina': .08,
    'leucocitos': .06,
    'linfocitos_pct': .04,
    'vcm': .03,
    'fosfatasa_alcalina': .03,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final r = ref.watch(ultimoResultadoProvider);
    final input = ref.watch(simulacionInputProvider);

    final usados = r?.biomarcadoresUsados ?? const [];
    final faltantes = usados.isNotEmpty
        ? usados.where((b) => b.inferido).map((b) => b.nombre).toList()
        : List<String>.of(input.datosFaltantes);

    final total = faltantes.fold<double>(0, (s, id) => s + (_pesos[id] ?? .02));
    final filas = [
      for (final id in faltantes) (id: id, fraccion: total == 0 ? 0.0 : (_pesos[id] ?? .02) / total),
    ]..sort((a, b) => b.fraccion.compareTo(a.fraccion));

    return MoScreen(
      appBar: AppBar(
        title: const Text('Qué medir'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.future);
            }
          },
        ),
      ),
      bottom: MoPrimaryButton(
        label: 'Actualizar mis exámenes',
        icon: Icons.upload_file_rounded,
        onPressed: () => context.go(Routes.examsUpload),
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MoiraiMascot(size: 58, mood: filas.isEmpty ? MascotMood.happy : MascotMood.idle),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Qué te conviene medir?', style: t.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Medir esto no cambia tu salud. Cambia lo que yo sé de ti, y por eso angosta el rango.',
                    style: t.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow),
        const SizedBox(height: Sp.x7),
        if (filas.isEmpty)
          const _TodoMedido().stagger(1)
        else ...[
          Row(
            children: [
              MoOverline('${filas.length} de 9 todavía ${filas.length == 1 ? 'inferido' : 'inferidos'}'),
              const Spacer(),
              const MoOverline('cuánto angosta el rango'),
            ],
          ).stagger(1),
          const SizedBox(height: Sp.x4),
          for (var i = 0; i < filas.length; i++) ...[
            _VoiRow(id: filas[i].id, fraccion: filas[i].fraccion, primera: i == 0, index: i).stagger(i + 2),
            if (i < filas.length - 1) const SizedBox(height: Sp.x3),
          ],
          const SizedBox(height: Sp.x5),
          MoFootnote(
            'El porcentaje es qué parte del rango que me falta angostar depende de ese dato. Es una aproximación mía; el motor no calcula todavía valor de información.',
            center: false,
          ).stagger(filas.length + 2),
        ],
        const SizedBox(height: Sp.stackSection),
        if (r != null)
          MoNotice(text: r.incertidumbre, tone: MoTone.brand, icon: Icons.blur_on_rounded).stagger(filas.length + 3)
        else if (input.notasIncertidumbre != null)
          MoNotice(text: input.notasIncertidumbre!, tone: MoTone.brand, icon: Icons.blur_on_rounded).stagger(filas.length + 3),
      ],
    );
  }
}

class _VoiRow extends StatelessWidget {
  const _VoiRow({required this.id, required this.fraccion, required this.primera, required this.index});
  final String id;
  final double fraccion;
  final bool primera;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final def = BiomarcadorDef.byId(id);
    final nombre = def?.nombre ?? id;
    final ayuda = def?.ayuda ?? 'Pídelo en tu próximo examen de sangre.';
    return MoCard(
      tone: primera ? MoTone.brand : MoTone.plain,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(nombre, style: t.titleMedium)),
              const SizedBox(width: Sp.x3),
              Text(
                '−${Fmt.pct(fraccion * 100)}',
                style: t.headlineSmall!.copyWith(color: MoiraiColors.blueInk, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rad.xs),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: primera ? MoiraiColors.surface : MoiraiColors.surface2)),
                  FractionallySizedBox(
                    widthFactor: fraccion.clamp(0.04, 1),
                    alignment: Alignment.centerLeft,
                    child: const DecoratedBox(decoration: BoxDecoration(color: MoiraiColors.blue)),
                  )
                      .animate(delay: Duration(milliseconds: 240 + 80 * index))
                      .scaleX(begin: 0, end: 1, alignment: Alignment.centerLeft, duration: Motion.reveal, curve: Motion.out),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sp.x3),
          Text(ayuda, style: t.bodySmall),
          const SizedBox(height: Sp.x3),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (primera) const MoBadge('La que más me falta ahora mismo', tone: MoTone.brand, icon: Icons.star_rounded),
              if (def?.nucleo ?? false) const MoBadge('núcleo PhenoAge'),
              if (def != null) MoBadge(def.unidad),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodoMedido extends StatelessWidget {
  const _TodoMedido();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      tone: MoTone.good,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: MoiraiColors.greenInk),
              const SizedBox(width: 10),
              Expanded(child: Text('Ya tengo tus 9 valores.', style: t.titleLarge!.copyWith(color: MoiraiColors.greenInk))),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Text(
            'La banda que te muestro es la más angosta que puedo darte con lo que existe hoy. Vuelve cuando tengas exámenes nuevos.',
            style: t.bodyLarge,
          ),
        ],
      ),
    );
  }
}
