import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/biomarcador.dart';
import '../../widgets/mo.dart';

/// Estado editable de un biomarcador en la pantalla de confirmación.
class _Entrada {
  _Entrada({required this.def, Biomarcador? leido})
      : leido = leido,
        activo = leido != null,
        controller = TextEditingController(text: leido == null ? '' : _fmt(leido.valor)),
        focus = FocusNode();

  final BiomarcadorDef def;

  /// Lo que vino de `/examenes/extraer` (null si no se leyó).
  final Biomarcador? leido;
  final TextEditingController controller;
  final FocusNode focus;

  /// Si el usuario decidió escribirlo (o vino leído). Inactivo = "lo infiero".
  bool activo;

  bool get deLectura => leido != null;

  double? get valor => parse(controller.text);

  /// El usuario cambió lo que leí: ya no aplica la confianza de la lectura.
  bool get corregido => leido != null && valor != null && (valor! - leido!.valor).abs() > 1e-9;

  String? get confianza => deLectura && !corregido ? leido!.confianza : null;

  /// Fuera del rango plausible: aviso, nunca bloqueo.
  String? get aviso {
    final v = valor;
    if (v == null) return null;
    if (v > def.max) return 'Eso se ve un poco alto, ¿lo revisas?';
    if (v < def.min) return 'Eso se ve un poco bajo, ¿lo revisas?';
    return null;
  }

  void dispose() {
    controller.dispose();
    focus.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? Fmt.entero(v) : v.toString().replaceAll('.', ',');

  /// Acepta "4,4" y "4.4"; si hay coma, el punto es separador de miles.
  static double? parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s;
    return double.tryParse(s);
  }
}

/// A · Confirmar lectura. Los 9 biomarcadores PhenoAge, editables; lo que
/// falta se infiere (medianas) y ensancha la banda, no la hace "más falsa".
class ExamsConfirmScreen extends ConsumerStatefulWidget {
  const ExamsConfirmScreen({super.key});

  @override
  ConsumerState<ExamsConfirmScreen> createState() => _ExamsConfirmScreenState();
}

class _ExamsConfirmScreenState extends ConsumerState<ExamsConfirmScreen> {
  late final List<_Entrada> _entradas;
  late final bool _manual;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final lectura = ref.read(lecturaPendienteProvider) ?? const <Biomarcador>[];
    _manual = lectura.isEmpty;
    _entradas = [
      for (final def in BiomarcadorDef.all) _Entrada(def: def, leido: lectura.where((b) => b.nombre == def.id).firstOrNull),
    ];
    for (final e in _entradas) {
      e.controller.addListener(_refrescar);
    }
  }

  @override
  void dispose() {
    for (final e in _entradas) {
      e.dispose();
    }
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  int get _conValor => _entradas.where((e) => e.valor != null).length;

  void _activar(_Entrada e) {
    setState(() => e.activo = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) e.focus.requestFocus();
    });
  }

  Future<void> _simular() async {
    FocusScope.of(context).unfocus();
    setState(() => _guardando = true);
    final now = DateTime.now();
    final fechaActual = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lista = <Biomarcador>[
      for (final e in _entradas)
        if (e.valor != null)
          Biomarcador(
            nombre: e.def.id,
            valor: e.valor!,
            unidad: e.leido?.unidad ?? e.def.unidad,
            fecha: e.leido?.fecha ?? fechaActual,
            fuente: e.deLectura ? 'documento' : 'manual',
            confianza: e.confianza,
          ),
    ];
    await ref.read(biomarcadoresProvider.notifier).set(lista);
    if (!mounted) return;
    ref.read(lecturaPendienteProvider.notifier).state = null;
    ref.read(simulationProvider.notifier).start();
    context.go(Routes.simulating);
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = _conValor;
    final borrosos = _entradas.where((e) => e.confianza == 'baja').map((e) => e.def.nombre).toList();

    return MoScreen(
      appBar: AppBar(),
      bottom: MoPrimaryButton(
        label: 'Simular mis futuros',
        icon: Icons.auto_awesome_rounded,
        loading: _guardando,
        onPressed: _simular,
      ),
      children: [
        Text(_manual ? 'Escribe tus valores' : 'Esto es lo que leí', style: t.headlineLarge),
        const SizedBox(height: Sp.x3),
        Text.rich(
          TextSpan(
            style: t.bodyLarge!.copyWith(color: MoiraiColors.ink2),
            children: _manual
                ? const [TextSpan(text: 'Escribe los que tengas a la mano. Los que falten los infiero y después te digo cuál conviene medir.')]
                : [
                    const TextSpan(text: 'Corrige lo que esté mal. Con los datos de confianza baja mi estimación se vuelve '),
                    TextSpan(text: 'más amplia', style: TextStyle(fontWeight: FontWeight.w800, color: MoiraiColors.ink)),
                    const TextSpan(text: ', no más falsa.'),
                  ],
          ),
        ),
        const SizedBox(height: Sp.x6),
        // Contador vivo.
        AnimatedSwitcher(
          duration: Motion.base,
          child: MoBadge(
            key: ValueKey(n),
            _textoConteo(n),
            tone: n >= 6 ? MoTone.good : MoTone.sunken,
            icon: n >= 6 ? Icons.compress_rounded : Icons.expand_rounded,
          ),
        ),
        const SizedBox(height: Sp.stackCard),
        for (var i = 0; i < _entradas.length; i++) ...[
          _Fila(entrada: _entradas[i], onActivar: () => _activar(_entradas[i])).stagger(i, base: 40.ms),
          if (i < _entradas.length - 1) const SizedBox(height: Sp.x3 + 2),
        ],
        if (borrosos.isNotEmpty) ...[
          const SizedBox(height: Sp.stackCard),
          MoNotice(
            tone: MoTone.watch,
            icon: Icons.blur_on_rounded,
            text: borrosos.length == 1
                ? 'Leí borroso el valor de ${borrosos.first}. Si lo corriges, mi estimación se angosta bastante.'
                : 'Leí borrosos los valores de ${_lista(borrosos)}. Si los corriges, mi estimación se angosta bastante.',
          ).animate().fadeIn(duration: Motion.slow),
        ],
        const SizedBox(height: Sp.x5),
        const MoFootnote('Estimación, no diagnóstico. Nada de esto reemplaza a tu médico.'),
      ],
    );
  }

  static String _textoConteo(int n) => switch (n) {
        9 => 'Con 9 de 9 valores, la banda será lo más angosta posible',
        >= 6 => 'Con $n de 9 valores, la banda será más angosta',
        0 => 'Sin valores, la banda será más ancha: los infiero',
        _ => 'Con $n de 9 valores, la banda será más ancha',
      };

  static String _lista(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} y ${xs.last}';
}

/// Una fila por biomarcador: nombre, unidad, campo numérico, confianza.
class _Fila extends StatelessWidget {
  const _Fila({required this.entrada, required this.onActivar});
  final _Entrada entrada;
  final VoidCallback onActivar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = entrada;
    final def = e.def;

    if (!e.activo) {
      return MoCard(
        tone: MoTone.sunken,
        onTap: onActivar,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.nombre, style: t.titleSmall!.copyWith(color: MoiraiColors.ink2)),
                  const SizedBox(height: 3),
                  Text('No lo tengo — lo infiero', style: t.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            const SizedBox(width: Sp.x3),
            Text('Escribirlo', style: t.labelMedium!.copyWith(color: MoiraiColors.blueInk)),
            const SizedBox(width: 6),
            const MoIconTile(Icons.edit_rounded, tone: MoTone.plain, size: 36),
          ],
        ),
      );
    }

    final aviso = e.aviso;
    final conf = e.confianza;
    final (badgeText, badgeTone) = switch (conf) {
      'alta' => ('Confianza alta', MoTone.good),
      'media' => ('Confianza media', MoTone.sunken),
      'baja' => ('Confianza baja', MoTone.watch),
      _ => e.corregido ? ('Corregido', MoTone.brand) : (e.deLectura ? ('Leído', MoTone.sunken) : ('A mano', MoTone.brand)),
    };

    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.nombre, style: t.titleSmall!.copyWith(color: MoiraiColors.ink2)),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: Motion.fast,
                      child: MoBadge(badgeText, key: ValueKey(badgeText), tone: badgeTone),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.x3),
              SizedBox(
                width: 132,
                child: TextField(
                  controller: e.controller,
                  focusNode: e.focus,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  style: t.titleLarge!.copyWith(fontSize: 22, fontFeatures: const [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    hintText: '—',
                    suffixText: def.unidad,
                    suffixStyle: t.labelMedium!.copyWith(color: MoiraiColors.ink3),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rad.sm),
                      borderSide: BorderSide(color: aviso != null ? MoiraiColors.amber : MoiraiColors.line, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rad.sm),
                      borderSide: BorderSide(color: aviso != null ? MoiraiColors.amber : MoiraiColors.blue, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.out,
            alignment: Alignment.topLeft,
            child: aviso == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, size: 16, color: MoiraiColors.amberInk),
                        const SizedBox(width: 6),
                        Expanded(child: Text(aviso, style: t.bodySmall!.copyWith(color: MoiraiColors.amberInk))),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(def.ayuda, style: t.bodySmall),
        ],
      ),
    );
  }
}
