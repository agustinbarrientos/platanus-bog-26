import 'package:flutter/material.dart';

import '../app/theme/tokens.dart';
import '../core/format.dart';

/// Número protagonista con count-up (~900 ms) desde 0 o desde el valor
/// anterior. Unidad aparte, más chica y apagada. Formato es-CO.
class BigNumber extends StatelessWidget {
  const BigNumber({
    super.key,
    required this.value,
    this.unit,
    this.decimals = 0,
    this.signed = false,
    this.corto = false,
    this.style,
    this.unitStyle,
    this.color,
    this.duration = Motion.count,
    this.align = CrossAxisAlignment.baseline,
  });

  final double value;
  final String? unit;
  final int decimals;

  /// Muestra "+"/"−" explícito (deltas).
  final bool signed;

  /// Sin decimal cuando el valor es entero exacto (7 → "7", 7.5 → "7,5").
  final bool corto;
  final TextStyle? style;
  final TextStyle? unitStyle;
  final Color? color;
  final Duration duration;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = (style ?? t.displayMedium)!.copyWith(color: color ?? (style?.color ?? MoiraiColors.ink), fontFeatures: const [FontFeature.tabularFigures()]);
    final ust = (unitStyle ?? t.titleMedium)!.copyWith(color: MoiraiColors.ink2, fontWeight: FontWeight.w600);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Motion.out,
      builder: (_, v, _) {
        final txt = signed
            ? Fmt.delta(v)
            : corto
                ? Fmt.corto(v)
                : (decimals == 0 ? Fmt.entero(v) : Fmt.decimal(v));
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: align,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(txt, style: st),
            if (unit != null) ...[
              const SizedBox(width: 6),
              Text(unit!, style: ust),
            ],
          ],
        );
      },
    );
  }
}
