import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/tokens.dart';
import '../../widgets/mo.dart';

/// Piezas que se repiten entre los pasos del onboarding.

/// Título del paso + subtítulo, en voz de la mascota.
class PasoTitulo extends StatelessWidget {
  const PasoTitulo({super.key, required this.titulo, this.subtitulo});
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: t.headlineMedium),
        if (subtitulo != null) ...[
          const SizedBox(height: Sp.x3),
          Text(subtitulo!, style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2)),
        ],
      ],
    ).animate().fadeIn(duration: Motion.slow, curve: Motion.out).slideY(begin: .05, end: 0, duration: Motion.slow, curve: Motion.out);
  }
}

/// Etiqueta de un campo o grupo. `opcional` agrega un badge discreto.
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.text, {super.key, this.opcional = false, this.hint});
  final String text;
  final bool opcional;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(text, style: t.titleMedium)),
              if (opcional) ...[const SizedBox(width: Sp.x3), const MoBadge('opcional')],
            ],
          ),
          if (hint != null) ...[const SizedBox(height: 4), Text(hint!, style: t.bodySmall)],
        ],
      ),
    );
  }
}

/// Pista de campo en ámbar (nunca rojo): "Necesito una estatura entre…".
class PistaCampo extends StatelessWidget {
  const PistaCampo(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.x3, left: Sp.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: MoiraiColors.amberInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: MoiraiColors.amberInk)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: Motion.base);
  }
}

/// Campo tipo selector: se ve como un input y abre una hoja con las opciones.
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icon,
    this.titulo,
    this.errorText,
  });

  final String label;
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final String? titulo;
  final String? errorText;

  Future<void> _abrir(BuildContext context) async {
    final t = Theme.of(context).textTheme;
    final r = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .72),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x7, Sp.x2, Sp.x7, Sp.x4),
              child: Align(alignment: Alignment.centerLeft, child: Text(titulo ?? label, style: t.titleLarge)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
                children: [
                  for (final e in options.entries)
                    ListTile(
                      minTileHeight: 52,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md)),
                      selected: e.key == value,
                      selectedTileColor: MoiraiColors.blueSoft,
                      title: Text(
                        e.value,
                        style: t.labelLarge!.copyWith(color: e.key == value ? MoiraiColors.blueInk : MoiraiColors.ink),
                      ),
                      trailing: e.key == value ? const Icon(Icons.check_rounded, color: MoiraiColors.blueInk) : null,
                      onTap: () => Navigator.of(ctx).pop(e.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (r != null) onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(Rad.md + 2),
      onTap: () => _abrir(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: const Icon(Icons.expand_more_rounded),
        ),
        isEmpty: value == null,
        child: Text(value == null ? '' : (options[value] ?? ''), style: t.bodyLarge),
      ),
    );
  }
}

/// Una opción de [OpcionLista].
typedef Opcion<T> = ({T value, String label, IconData icon, String? sub});

/// Lista vertical de opciones excluyentes con icono (tiles de 56+ px).
class OpcionLista<T> extends StatelessWidget {
  const OpcionLista({super.key, required this.opciones, required this.value, required this.onChanged});
  final List<Opcion<T>> opciones;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < opciones.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _OpcionTile(
            opcion: opciones[i],
            selected: opciones[i].value == value,
            onTap: () => onChanged(opciones[i].value),
          ).stagger(i),
        ],
      ],
    );
  }
}

class _OpcionTile<T> extends StatelessWidget {
  const _OpcionTile({required this.opcion, required this.selected, required this.onTap});
  final Opcion<T> opcion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.out,
      decoration: BoxDecoration(
        color: selected ? MoiraiColors.blueSoft : MoiraiColors.surface,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: selected ? MoiraiColors.blue : MoiraiColors.line, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rad.lg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? MoiraiColors.surface : MoiraiColors.surface2,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(opcion.icon, size: 20, color: selected ? MoiraiColors.blueInk : MoiraiColors.ink2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opcion.label, style: t.titleMedium!.copyWith(color: selected ? MoiraiColors.blueInk : MoiraiColors.ink)),
                      if (opcion.sub != null) ...[
                        const SizedBox(height: 2),
                        Text(opcion.sub!, style: t.bodySmall),
                      ],
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: Motion.fast,
                  opacity: selected ? 1 : 0,
                  child: const Icon(Icons.check_circle_rounded, color: MoiraiColors.blueInk, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chips de selección múltiple a partir de un catálogo `valor → etiqueta`.
class MultiChips extends StatelessWidget {
  const MultiChips({super.key, required this.options, required this.values, required this.onChanged, this.icons = const {}});
  final Map<String, String> options;
  final Set<String> values;
  final ValueChanged<Set<String>> onChanged;
  final Map<String, IconData> icons;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          MoChoice(
            label: e.value,
            icon: icons[e.key],
            selected: values.contains(e.key),
            onTap: () {
              final s = {...values};
              if (!s.remove(e.key)) s.add(e.key);
              onChanged(s);
            },
          ),
      ],
    );
  }
}

/// Sí / No en una sola fila.
class SiNo extends StatelessWidget {
  const SiNo({super.key, required this.value, required this.onChanged});
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MoChoiceGroup<bool>(options: const {true: 'Sí', false: 'No'}, value: value, onChanged: onChanged, wrap: false);
  }
}
