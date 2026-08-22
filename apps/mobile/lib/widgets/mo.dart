import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app/theme/tokens.dart';

/// Piezas compartidas de UI ("Mo" = Moirai). Todo lo que se repite en más de
/// una pantalla vive aquí para que las vistas se vean iguales.

enum MoTone { plain, brand, good, watch, sunken }

/// Card blanca de 24 px con hairline y sombra azulada. `tone` tiñe el fondo
/// (una tintada por pantalla, máximo).
class MoCard extends StatelessWidget {
  const MoCard({super.key, required this.child, this.tone = MoTone.plain, this.padding = const EdgeInsets.all(Sp.gutter), this.onTap, this.margin});

  final Widget child;
  final MoTone tone;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (tone) {
      MoTone.plain => (MoiraiColors.surface, MoiraiColors.line),
      MoTone.brand => (MoiraiColors.blueSoft, MoiraiColors.blueSoft),
      MoTone.good => (MoiraiColors.greenSoft, MoiraiColors.greenSoft),
      MoTone.watch => (MoiraiColors.amberSoft, MoiraiColors.amberSoft),
      MoTone.sunken => (MoiraiColors.surface2, MoiraiColors.surface2),
    };
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Rad.card),
        border: Border.all(color: border),
        boxShadow: tone == MoTone.plain
            ? [
                BoxShadow(color: MoiraiColors.ink.withValues(alpha: .04), blurRadius: 2, offset: const Offset(0, 1)),
                BoxShadow(color: MoiraiColors.action.withValues(alpha: .06), blurRadius: 8, offset: const Offset(0, 2)),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    final wrapped = onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Rad.card),
              child: card,
            ),
          );
    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}

/// Kicker en mayúsculas (11 px, tracking ancho): "AÑOS SIN ENFERMEDAD CRÓNICA".
class MoOverline extends StatelessWidget {
  const MoOverline(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall!.copyWith(color: color ?? MoiraiColors.ink3),
  );
}

/// Título de sección (22 px Fredoka) con subtítulo opcional.
class MoSectionTitle extends StatelessWidget {
  const MoSectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: t.bodyMedium),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Encabezado de pantalla: título grande + subtítulo en voz de la mascota.
class MoScreenHeader extends StatelessWidget {
  const MoScreenHeader({super.key, required this.title, this.subtitle, this.leading});
  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[leading!, const SizedBox(height: Sp.x5)],
        Text(title, style: t.headlineLarge),
        if (subtitle != null) ...[
          const SizedBox(height: Sp.x3),
          Text(subtitle!, style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2)),
        ],
      ],
    ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow);
  }
}

/// Chip pill de selección (único o múltiple). Seleccionado = azul suave con
/// tinta azul; hover/press oscurecen, nunca alfa.
class MoChoice extends StatelessWidget {
  const MoChoice({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.good = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Variante verde (para "bien / sí").
  final bool good;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? (good ? MoiraiColors.greenSoft : MoiraiColors.blueSoft) : MoiraiColors.surface;
    final fg = selected ? (good ? MoiraiColors.greenInk : MoiraiColors.blueInk) : MoiraiColors.ink;
    final border = selected ? (good ? MoiraiColors.green : MoiraiColors.blue) : MoiraiColors.line;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.out,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rad.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
                Text(label, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: fg, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de opciones excluyentes (segmentadas) en una sola línea o envueltas.
class MoChoiceGroup<T> extends StatelessWidget {
  const MoChoiceGroup({super.key, required this.options, required this.value, required this.onChanged, this.wrap = true});
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final e in options.entries) MoChoice(label: e.value, selected: e.key == value, onTap: () => onChanged(e.key)),
    ];
    return wrap
        ? Wrap(spacing: 8, runSpacing: 8, children: chips)
        : Row(children: [for (final c in chips) Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: c))]);
  }
}

/// Badge chico de estado (alta/media/baja, esfuerzo, etc.).
class MoBadge extends StatelessWidget {
  const MoBadge(this.text, {super.key, this.tone = MoTone.sunken, this.icon});
  final String text;
  final MoTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      MoTone.brand => (MoiraiColors.blueSoft, MoiraiColors.blueInk),
      MoTone.good => (MoiraiColors.greenSoft, MoiraiColors.greenInk),
      MoTone.watch => (MoiraiColors.amberSoft, MoiraiColors.amberInk),
      _ => (MoiraiColors.surface2, MoiraiColors.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Rad.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(text, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: fg, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Aviso en línea, tintado, para noticias que no deben llegar como toast.
class MoNotice extends StatelessWidget {
  const MoNotice({super.key, required this.text, this.tone = MoTone.brand, this.icon = Icons.info_outline_rounded, this.action});
  final String text;
  final MoTone tone;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final fg = switch (tone) {
      MoTone.good => MoiraiColors.greenInk,
      MoTone.watch => MoiraiColors.amberInk,
      MoTone.brand => MoiraiColors.blueInk,
      _ => MoiraiColors.ink2,
    };
    return MoCard(
      tone: tone,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg, height: 1.45))),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// Scaffold de pantalla con gutter de 20, scroll y CTA fija abajo opcional.
class MoScreen extends StatelessWidget {
  const MoScreen({super.key, required this.children, this.appBar, this.bottom, this.padding, this.scrollController, this.background, this.safeTop = true});
  final List<Widget> children;
  final PreferredSizeWidget? appBar;

  /// Botón(es) anclados abajo con degradado de protección.
  final Widget? bottom;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final Widget? background;
  final bool safeTop;

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        if (background != null) Positioned.fill(child: background!),
        SafeArea(
          top: safeTop,
          bottom: false,
          child: ListView(
            controller: scrollController,
            padding: padding ?? EdgeInsets.fromLTRB(Sp.gutter, appBar == null ? Sp.x7 : Sp.x4, Sp.gutter, bottom == null ? Sp.x9 : 140),
            children: children,
          ),
        ),
        if (bottom != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(Sp.gutter, 28, Sp.gutter, MediaQuery.paddingOf(context).bottom + Sp.x5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [MoiraiColors.bg.withValues(alpha: 0), MoiraiColors.bg.withValues(alpha: .94), MoiraiColors.bg],
                    stops: const [0, .35, 1],
                  ),
                ),
                child: bottom,
              ),
            ),
          ),
      ],
    );
    return Scaffold(appBar: appBar, body: body, extendBody: true);
  }
}

/// Botón primario con sombra azul, full-width, 54 px.
class MoPrimaryButton extends StatelessWidget {
  const MoPrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false, this.good = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? MoiraiColors.green : MoiraiColors.action;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rad.pill),
        boxShadow: onPressed == null ? null : [BoxShadow(color: color.withValues(alpha: .30), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(backgroundColor: color, disabledBackgroundColor: loading ? color.withValues(alpha: .7) : MoiraiColors.surface2, disabledForegroundColor: loading ? Colors.white : MoiraiColors.ink3),
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Texto de pie ("No te voy a pedir nada que no necesite.").
class MoFootnote extends StatelessWidget {
  const MoFootnote(this.text, {super.key, this.center = true});
  final String text;
  final bool center;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: Theme.of(context).textTheme.bodySmall,
  );
}

/// Tile de icono tintado (42 px) para listas.
class MoIconTile extends StatelessWidget {
  const MoIconTile(this.icon, {super.key, this.tone = MoTone.brand, this.size = 42});
  final IconData icon;
  final MoTone tone;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      MoTone.good => (MoiraiColors.greenSoft, MoiraiColors.greenInk),
      MoTone.watch => (MoiraiColors.amberSoft, MoiraiColors.amberInk),
      MoTone.brand => (MoiraiColors.blueSoft, MoiraiColors.blueInk),
      _ => (MoiraiColors.surface2, MoiraiColors.ink2),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .33)),
      child: Icon(icon, color: fg, size: size * .5),
    );
  }
}

/// Entrada escalonada para listas: `children[i].animate(delay: i*60ms)`.
extension MoStagger on Widget {
  Widget stagger(int index, {Duration base = const Duration(milliseconds: 60)}) =>
      animate(delay: base * index).fadeIn(duration: Motion.slow, curve: Motion.out).slideY(begin: .06, end: 0, duration: Motion.slow, curve: Motion.out);
}

/// Iconos Material para los ids de intervención del catálogo.
IconData iconoIntervencion(String id) => switch (id) {
  'sueno_8h' => Icons.bedtime_rounded,
  'ejercicio_moderado' => Icons.directions_walk_rounded,
  'dejar_alcohol' => Icons.no_drinks_rounded,
  'dieta_mejor' => Icons.restaurant_rounded,
  'reducir_estres' => Icons.self_improvement_rounded,
  _ => Icons.spa_rounded,
};
