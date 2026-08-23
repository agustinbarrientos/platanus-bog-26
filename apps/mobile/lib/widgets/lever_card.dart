import 'package:flutter/material.dart';

import '../app/theme/tokens.dart';
import '../core/format.dart';
import '../data/models/onboarding.dart';
import '../data/models/simulacion.dart';
import 'big_number.dart';
import 'mo.dart';

/// Qué objetivos del onboarding (`Catalogos.objetivos`) toca cada palanca del
/// motor. No cambia el orden (que es años ganados / esfuerzo, del motor): solo
/// marca la palanca para que la persona vea que lo que pidió cuenta.
const objetivosPorPalanca = <String, Set<String>>{
  'ejercicio_aerobico': {'energia', 'rendimiento', 'peso', 'longevidad'},
  'dieta_mediterranea': {'peso', 'prevencion', 'longevidad'},
  'cesacion_tabaco': {'prevencion', 'longevidad', 'fertilidad'},
  'sueno_8h': {'sueno', 'energia', 'salud_mental'},
  'reducir_estres': {'salud_mental', 'sueno', 'fertilidad'},
  'reducir_alcohol': {'sueno', 'peso', 'prevencion'},
};

/// Objetivos del usuario que toca un escenario (en el orden del catálogo).
List<String> objetivosTocados(Iterable<String> intervenciones, Set<String> objetivos) {
  if (objetivos.isEmpty) return const [];
  final tocados = <String>{for (final id in intervenciones) ...(objetivosPorPalanca[id] ?? const <String>{})};
  return [for (final o in Catalogos.objetivos.keys) if (objetivos.contains(o) && tocados.contains(o)) o];
}

/// Card de una palanca/escenario: etiqueta + rango + % de futuros que mejoran
/// a la izquierda, delta grande a la derecha. "Ningún número sin su palanca,
/// ningún delta sin su intervalo."
class LeverCard extends StatelessWidget {
  const LeverCard({super.key, required this.escenario, this.onTap, this.destacada = false, this.rank, this.objetivos = const {}});
  final Escenario escenario;
  final VoidCallback? onTap;
  final bool destacada;
  final int? rank;

  /// Objetivos del usuario: si la palanca toca alguno, se marca.
  final Set<String> objetivos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = escenario;
    final tocados = objetivosTocados(e.intervenciones, objetivos);
    return MoCard(
      onTap: onTap,
      tone: destacada ? MoTone.good : MoTone.plain,
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              MoIconTile(iconoIntervencion(e.intervenciones.first), tone: destacada ? MoTone.good : MoTone.brand, size: 46),
              if (e.intervenciones.length > 1)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: MoiraiColors.surface, shape: BoxShape.circle, border: Border.all(color: MoiraiColors.line)),
                    child: Text('+${e.intervenciones.length - 1}', style: t.labelSmall!.copyWith(letterSpacing: 0, fontSize: 10, color: MoiraiColors.ink2)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.etiqueta, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${Fmt.rangoDelta(e.rango[0], e.rango[1])} · ayuda en ${Fmt.pct(e.pctMejoran)}', style: t.bodySmall!.copyWith(color: MoiraiColors.ink2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MoBadge(e.esfuerzoLabel, tone: e.esfuerzo <= 2 ? MoTone.good : e.esfuerzo <= 4 ? MoTone.sunken : MoTone.watch),
                    if (tocados.isNotEmpty)
                      MoBadge(
                        'toca ${tocados.take(2).map((o) => (Catalogos.objetivos[o] ?? o).toLowerCase()).join(' y ')}',
                        tone: MoTone.brand,
                        icon: Icons.auto_awesome_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BigNumber(value: e.aniosGanados, signed: true, decimals: 1, style: t.displaySmall!.copyWith(fontSize: 34), color: destacada ? MoiraiColors.greenInk : MoiraiColors.blueInk),
              Text('años ganados', style: t.labelMedium!.copyWith(color: MoiraiColors.ink2)),
            ],
          ),
        ],
      ),
    );
  }
}
