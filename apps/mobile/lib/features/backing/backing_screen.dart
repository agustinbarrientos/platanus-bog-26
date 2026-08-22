import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/tokens.dart';
import '../../core/env.dart';
import '../../data/mock/mock_engine.dart';
import '../../data/models/biomarcador.dart';
import '../../data/models/simulacion.dart';
import '../../widgets/fan_chart.dart';
import '../../widgets/mo.dart';

/// Pestaña "Respaldo": de dónde sale cada número. No hay un número de
/// calibración inventado; hay tres capas explicadas, los coeficientes que
/// uso, lo que NO hago y las respuestas a las preguntas incómodas.
class BackingScreen extends StatelessWidget {
  const BackingScreen({super.key});

  static final Uri _nhanes = Uri.parse('https://www.cdc.gov/nchs/nhanes/');
  static final Uri _levine = Uri.parse('https://doi.org/10.18632/aging.101414');

  @override
  Widget build(BuildContext context) {
    var i = 0;
    Widget s(Widget w) => w.stagger(i++, base: const Duration(milliseconds: 70));

    return MoScreen(
      children: [
        const MoScreenHeader(
          title: 'De dónde sale esto',
          subtitle: 'No te pido confianza ciega. Esto es lo que hay detrás de cada número.',
        ),
        const SizedBox(height: Sp.stackSection),

        // ── Tres capas ────────────────────────────────────────────────────
        s(const MoSectionTitle('Tres capas, apiladas', subtitle: 'Una mide, otra proyecta, la tercera dice qué tan seguro estoy.')),
        const SizedBox(height: Sp.x5),
        s(const _LayerCard(
          numero: 1,
          icon: Icons.straighten_rounded,
          titulo: 'Medidor — PhenoAge',
          texto: 'Mide tu edad biológica hoy con 9 biomarcadores y pesos publicados (Levine et al., 2018). No predice: mide el presente.',
          tone: MoTone.brand,
        )),
        s(const _Connector()),
        s(const _LayerCard(
          numero: 2,
          icon: Icons.timeline_rounded,
          titulo: 'Motor de evolución',
          texto: 'Cada biomarcador cambia un poco cada año; cada hábito modifica esa deriva. Coeficientes aproximados, derivados de literatura epidemiológica — citables, nunca inventados.',
          tone: MoTone.good,
        )),
        s(const _Connector()),
        s(_LayerCard(
          numero: 3,
          icon: Icons.blur_on_rounded,
          titulo: 'Monte Carlo',
          texto: 'Corro la capa 2 5.000 veces con ruido biológico. El abanico P10–P90 es lo que no sé de ti, dicho en voz alta.',
          tone: MoTone.watch,
          extra: Padding(
            padding: const EdgeInsets.only(top: Sp.x4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Rad.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(color: MoiraiColors.surface2.withValues(alpha: .6), borderRadius: BorderRadius.circular(Rad.sm)),
                child: FanChart(
                  edad0: 34,
                  curva: _Ilustrativo.curva,
                  trayectorias: _Ilustrativo.trayectorias,
                  mostrarEjes: false,
                  identidad: false,
                  height: 80,
                ),
              ),
            ),
          ),
        )),
        const SizedBox(height: Sp.stackSection),

        // ── Qué datos uso ────────────────────────────────────────────────
        s(const MoSectionTitle('Qué datos uso')),
        const SizedBox(height: Sp.x5),
        s(const _DatosCard()),
        const SizedBox(height: Sp.stackSection),

        // ── Palancas ─────────────────────────────────────────────────────
        s(const MoSectionTitle('Las palancas y su efecto anual', subtitle: 'Cuánto mueve cada hábito la deriva de cada biomarcador, por año.')),
        const SizedBox(height: Sp.x5),
        s(const _PalancasCard()),
        const SizedBox(height: Sp.stackSection),

        // ── Lo que NO hace ───────────────────────────────────────────────
        s(const MoSectionTitle('Lo que esto NO hace')),
        const SizedBox(height: Sp.x5),
        s(const _NoHaceCard()),
        const SizedBox(height: Sp.stackSection),

        // ── FAQ ──────────────────────────────────────────────────────────
        s(const MoSectionTitle('Si me preguntas…')),
        const SizedBox(height: Sp.x5),
        s(const _FaqCard()),
        const SizedBox(height: Sp.stackSection),

        // ── Fuentes ──────────────────────────────────────────────────────
        s(const MoSectionTitle('Fuentes')),
        const SizedBox(height: Sp.x5),
        s(MoCard(
          padding: const EdgeInsets.symmetric(vertical: Sp.x2),
          child: Column(
            children: [
              _FuenteTile(
                titulo: 'NHANES (CDC)',
                subtitulo: 'Medianas poblacionales por edad y sexo para imputar lo que falta.',
                onTap: () => _abrir(context, _nhanes),
              ),
              const Divider(indent: Sp.gutter, endIndent: Sp.gutter),
              _FuenteTile(
                titulo: 'Levine et al. 2018 — An epigenetic biomarker of aging for lifespan and healthspan',
                subtitulo: 'Aging, 10(4). Los pesos de PhenoAge (capa 1).',
                onTap: () => _abrir(context, _levine),
              ),
            ],
          ),
        )),
        const SizedBox(height: Sp.stackSection),

        // ── Pie ──────────────────────────────────────────────────────────
        s(const MoFootnote('Estimación de riesgo poblacional, no diagnóstico. Consulta a un profesional para decisiones clínicas.')),
        if (Env.useMockEngine) ...[
          const SizedBox(height: Sp.x3),
          s(Text(
            'Motor v0.1 · mock en el dispositivo',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: .4),
          )),
        ],
      ],
    );
  }

  static Future<void> _abrir(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude abrir el enlace. Cópialo: $uri')),
      );
    }
  }
}

// ── Capas ────────────────────────────────────────────────────────────────

class _LayerCard extends StatelessWidget {
  const _LayerCard({required this.numero, required this.icon, required this.titulo, required this.texto, required this.tone, this.extra});
  final int numero;
  final IconData icon;
  final String titulo;
  final String texto;
  final MoTone tone;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoIconTile(icon, tone: tone),
              const SizedBox(width: Sp.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoOverline('Capa $numero'),
                    const SizedBox(height: 2),
                    Text(titulo, style: t.titleMedium),
                    const SizedBox(height: 6),
                    Text(texto, style: t.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          ?extra,
        ],
      ),
    );
  }
}

/// Conector vertical entre capas: una línea corta alineada con el icono.
class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Sp.gutter + 21 - 1),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          children: [
            Container(width: 2, height: 10, color: MoiraiColors.line),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: MoiraiColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// Curva sintética solo para ilustrar el abanico (no es ninguna persona).
abstract final class _Ilustrativo {
  static final Curva curva = Curva(
    anios: List.generate(11, (i) => i),
    mediana: List.generate(11, (i) => 34 + i * 1.08),
    p10: List.generate(11, (i) => 34 + i * 1.08 - 0.4 - i * 0.42),
    p90: List.generate(11, (i) => 34 + i * 1.08 + 0.4 + i * 0.55),
  );

  static final List<List<double>> trayectorias = () {
    final rng = math.Random(11);
    return List.generate(14, (_) {
      var v = 34.0;
      final pendiente = 0.7 + rng.nextDouble() * 0.8;
      return List.generate(11, (i) {
        if (i > 0) v += pendiente + (rng.nextDouble() - 0.5) * 1.1;
        return v;
      });
    });
  }();
}

// ── Qué datos uso ────────────────────────────────────────────────────────

class _DatosCard extends StatelessWidget {
  const _DatosCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Los 9 biomarcadores de PhenoAge', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Los seis resaltados son el núcleo: con esos ya puedo simular.', style: t.bodyMedium),
          const SizedBox(height: Sp.x4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in BiomarcadorDef.all)
                MoBadge(
                  d.nombre,
                  tone: d.nucleo ? MoTone.brand : MoTone.sunken,
                  icon: d.nucleo ? Icons.check_rounded : null,
                ),
            ],
          ),
          const SizedBox(height: Sp.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: MoiraiColors.ink3),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Text(
                  'Los que faltan los imputo con medianas NHANES por edad y sexo y ensancho la banda.',
                  style: t.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Palancas ─────────────────────────────────────────────────────────────

class _PalancasCard extends StatelessWidget {
  const _PalancasCard();

  /// Coeficientes con hasta tres decimales (−0,002 no puede mostrarse como
  /// "0"); signo explícito y menos tipográfico, igual que `Fmt.delta`.
  static final _tres = NumberFormat('#,##0.###', 'es_CO');
  static String _coef(double v) {
    if (v.abs() < 0.0005) return '0';
    final s = _tres.format(v.abs());
    return v > 0 ? '+$s' : '−$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x3, Sp.gutter, Sp.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final interv in MockEngine.catalogo)
            _SinBordes(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 54, bottom: Sp.x3),
                leading: MoIconTile(iconoIntervencion(interv.id), size: 40),
                title: Text(interv.etiqueta, style: t.titleMedium),
                subtitle: Text(
                  '${MockEngine.efectoIntervencion[interv.id]?.length ?? 0} biomarcadores · ${interv.esfuerzoLabel}',
                  style: t.bodySmall,
                ),
                iconColor: MoiraiColors.ink2,
                collapsedIconColor: MoiraiColors.ink3,
                children: [
                  for (final e in (MockEngine.efectoIntervencion[interv.id] ?? const {}).entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(child: Text(BiomarcadorDef.byId(e.key)?.nombre ?? e.key, style: t.bodyMedium)),
                          const SizedBox(width: Sp.x3),
                          Text(
                            '${_coef(e.value)} ${BiomarcadorDef.byId(e.key)?.unidad ?? ''}/año',
                            style: t.labelMedium!.copyWith(
                              color: e.value < 0 ? MoiraiColors.greenInk : MoiraiColors.amberInk,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Sp.x3),
          Text('Aproximados, de literatura. Los ajustamos con NHANES cuando el tiempo alcanza.', style: t.bodySmall),
        ],
      ),
    );
  }
}

/// Quita los bordes que ExpansionTile pinta al abrir/cerrar.
class _SinBordes extends StatelessWidget {
  const _SinBordes({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      dividerColor: Colors.transparent,
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    ),
    child: child,
  );
}

// ── Lo que NO hace ───────────────────────────────────────────────────────

class _NoHaceCard extends StatelessWidget {
  const _NoHaceCard();

  static const _items = [
    'No diagnostica.',
    'No predice una enfermedad: estratifica y proyecta trayectorias probables.',
    'No inventa pesos y los presenta como verdad.',
    'No simula más de 3 cambios a la vez.',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.x4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.do_not_disturb_on_outlined, size: 20, color: MoiraiColors.amberInk),
                ),
                const SizedBox(width: Sp.x4),
                Expanded(child: Text(_items[i], style: t.bodyLarge)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── FAQ ──────────────────────────────────────────────────────────────────

class _FaqCard extends StatelessWidget {
  const _FaqCard();

  // Spec §13, en primera persona.
  static const _qa = <(String, String)>[
    (
      '¿Los pesos son inventados?',
      'Capa 1 es PhenoAge publicado (Levine 2018). Capa 2 son efectos de literatura epidemiológica, aproximados y citables. Nada lo presento como verdad exacta.',
    ),
    (
      '¿Esto predice enfermedad?',
      'No. Estratifico y proyecto trayectorias probables de edad biológica, con incertidumbre explícita — el abanico muestra lo que no sé.',
    ),
    (
      '¿Por qué confiar en la proyección?',
      'No te pido confianza ciega: te muestro la banda P10–P90. La incertidumbre es parte de lo que te entrego, no algo que escondo.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      padding: const EdgeInsets.symmetric(horizontal: Sp.gutter, vertical: Sp.x2),
      child: Column(
        children: [
          for (var i = 0; i < _qa.length; i++) ...[
            if (i > 0) const Divider(),
            _SinBordes(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: Sp.x5, right: Sp.x7),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                iconColor: MoiraiColors.ink2,
                collapsedIconColor: MoiraiColors.ink3,
                title: Text(_qa[i].$1, style: t.titleMedium),
                children: [Text(_qa[i].$2, style: t.bodyMedium)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Fuentes ──────────────────────────────────────────────────────────────

class _FuenteTile extends StatelessWidget {
  const _FuenteTile({required this.titulo, required this.subtitulo, required this.onTap});
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.gutter, vertical: 4),
      leading: const MoIconTile(Icons.menu_book_rounded, tone: MoTone.sunken, size: 40),
      title: Text(titulo, style: t.titleSmall),
      subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitulo, style: t.bodySmall)),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: MoiraiColors.ink3),
      onTap: onTap,
    );
  }
}
