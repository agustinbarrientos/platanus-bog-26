import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/tokens.dart';
import '../../widgets/mo.dart';

/// Card de sección del perfil: título (+ acción opcional a la derecha) y contenido.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.title, required this.child, this.subtitle, this.action, this.padding});
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      padding: padding ?? const EdgeInsets.fromLTRB(Sp.gutter, Sp.x5, Sp.gutter, Sp.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: t.bodyMedium)],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: Sp.x4),
          child,
        ],
      ),
    );
  }
}

/// Fila "etiqueta · valor" estilo ListTile; con `onTap` muestra chevron.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.onTap, this.leading, this.trailing, this.muted = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  /// Valor apagado (p. ej. "Sin dato").
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Sp.x4)],
          Expanded(child: Text(label, style: t.bodyMedium)),
          const SizedBox(width: Sp.x4),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.titleSmall!.copyWith(color: muted ? MoiraiColors.ink3 : MoiraiColors.ink, fontWeight: muted ? FontWeight.w600 : FontWeight.w700),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Sp.x3), trailing!] else if (onTap != null) ...[
            const SizedBox(width: Sp.x2),
            const Icon(Icons.chevron_right_rounded, size: 20, color: MoiraiColors.ink3),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Rad.sm), child: row),
    );
  }
}

/// Fila de hábito que se expande en línea para editar con chips.
class HabitRow extends StatefulWidget {
  const HabitRow({super.key, required this.label, required this.value, required this.editor, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  /// Editor inline (MoChoiceGroup, slider…).
  final Widget editor;

  @override
  State<HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends State<HabitRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(Rad.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: _open ? MoiraiColors.blueInk : MoiraiColors.ink3),
                    const SizedBox(width: Sp.x4),
                  ],
                  Expanded(child: Text(widget.label, style: t.bodyMedium)),
                  const SizedBox(width: Sp.x4),
                  Flexible(
                    child: Text(
                      widget.value,
                      textAlign: TextAlign.end,
                      style: t.titleSmall!.copyWith(color: _open ? MoiraiColors.blueInk : MoiraiColors.ink),
                    ),
                  ),
                  const SizedBox(width: Sp.x2),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: Motion.base,
                    curve: Motion.out,
                    child: const Icon(Icons.expand_more_rounded, size: 20, color: MoiraiColors.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Sp.x4, top: 2),
                  child: widget.editor,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Línea gris "cargando" con brillo suave (sin spinner).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width = double.infinity, this.height = 14, this.radius = Rad.xs});
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: MoiraiColors.surface2, borderRadius: BorderRadius.circular(radius)),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1400.ms, color: MoiraiColors.surface.withValues(alpha: .9));
  }
}

/// Círculo skeleton (avatar cargando).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => SkeletonLine(width: size, height: size, radius: size / 2);
}
