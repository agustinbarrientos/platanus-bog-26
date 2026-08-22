import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../data/models/simulacion.dart';
import '../../widgets/lever_card.dart';
import '../../widgets/mo.dart';
import '../future/future_empty_state.dart';

/// Tab "Simular" (flujo D): el barrido completo de escenarios, ya rankeado por
/// años ganados / esfuerzo. Filtro por número de cambios.
class LeversScreen extends ConsumerStatefulWidget {
  const LeversScreen({super.key});

  @override
  ConsumerState<LeversScreen> createState() => _LeversScreenState();
}

class _LeversScreenState extends ConsumerState<LeversScreen> {
  /// 0 = todas; 1–3 = número de intervenciones del combo.
  int _filtro = 0;

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(ultimoResultadoProvider);
    if (r == null) {
      return const FutureEmptyState(
        title: 'Todavía no tengo palancas que mostrarte',
        subtitle: 'Primero necesito recorrer tus futuros. Después te digo qué los mueve y en qué orden.',
      );
    }
    final todos = r.escenarios;
    final tamanos = todos.map((e) => e.intervenciones.length).toSet();
    final opciones = <int, String>{
      0: 'Todas',
      for (final n in [1, 2, 3])
        if (tamanos.contains(n)) n: n == 1 ? '1 cambio' : '$n cambios',
    };
    final filtro = opciones.containsKey(_filtro) ? _filtro : 0;
    final lista = filtro == 0 ? todos : todos.where((e) => e.intervenciones.length == filtro).toList();

    return MoScreen(
      children: [
        const MoScreenHeader(
          title: 'Lo que puedes mover',
          subtitle: 'Las ordené por cuánto mueven tu edad biológica por unidad de esfuerzo. Toca una para ver los futuros pareados.',
        ),
        const SizedBox(height: Sp.x6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final o in opciones.entries) ...[
                MoChoice(
                  label: o.value,
                  selected: o.key == filtro,
                  onTap: () => setState(() => _filtro = o.key),
                ),
                const SizedBox(width: Sp.x3),
              ],
            ],
          ),
        ).stagger(1),
        const SizedBox(height: Sp.x5),
        AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.out,
          switchOutCurve: Motion.out,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: _LeverList(key: ValueKey(filtro), todos: todos, lista: lista, filtro: filtro),
        ),
        const SizedBox(height: Sp.stackSection),
        const MoNotice(
          text: 'Los rangos son anchos a propósito. Confío mucho más en el orden de esta lista que en cualquiera de los números por separado.',
          tone: MoTone.brand,
        ).stagger(3),
        const SizedBox(height: Sp.x5),
        const MoFootnote('Estimación, no diagnóstico. Cada delta es frente a tus mismos futuros si sigues igual.'),
      ],
    );
  }
}

class _LeverList extends StatelessWidget {
  const _LeverList({super.key, required this.todos, required this.lista, required this.filtro});
  final List<Escenario> todos;
  final List<Escenario> lista;
  final int filtro;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (lista.isEmpty) {
      return MoCard(
        tone: MoTone.sunken,
        child: Text(
          filtro == 0 ? 'No encontré palancas que apliquen a tu caso.' : 'No tengo combinaciones de $filtro cambios para ti.',
          style: t.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lista.length; i++) ...[
          Builder(
            builder: (context) {
              final e = lista[i];
              final indexGlobal = todos.indexOf(e);
              return LeverCard(
                escenario: e,
                rank: indexGlobal + 1,
                destacada: indexGlobal == 0,
                onTap: () => context.go(Routes.leverDetail(indexGlobal < 0 ? i : indexGlobal)),
              );
            },
          ).stagger(i, base: const Duration(milliseconds: 70)),
          if (i < lista.length - 1) const SizedBox(height: Sp.x3 + 1),
        ],
      ],
    );
  }
}
