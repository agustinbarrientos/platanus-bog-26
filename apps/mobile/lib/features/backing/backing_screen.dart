import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/env.dart';
import '../../core/format.dart';
import '../../data/models/biomarcador.dart';
import '../../data/models/simulacion.dart';
import '../../data/repositories/simulation_repository.dart';
import '../../widgets/fan_chart.dart';
import '../../widgets/mo.dart';

/// "Respaldo" (se abre desde el encabezado de "Tu futuro"): de dónde sale cada número. No hay un número de
/// calibración inventado; hay tres capas explicadas, los coeficientes que
/// uso, lo que NO hago y las respuestas a las preguntas incómodas.
class BackingScreen extends ConsumerWidget {
  const BackingScreen({super.key});

  static final Uri _nhanes = Uri.parse('https://www.cdc.gov/nchs/nhanes/');
  static final Uri _levine = Uri.parse('https://doi.org/10.18632/aging.101414');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var i = 0;
    Widget s(Widget w) => w.stagger(i++, base: const Duration(milliseconds: 70));
    final catalogo = ref.watch(engineCatalogProvider).asData?.value;
    final version = '${catalogo?['version'] ?? '0.3'}';

    return MoScreen(
      appBar: AppBar(
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
          texto: 'Cada biomarcador cambia un poco cada año; tus hábitos de hoy ajustan esa deriva y cada palanca cierra la brecha de uno de ellos. Coeficientes aproximados, derivados de literatura epidemiológica — citables, nunca inventados.',
          tone: MoTone.good,
        )),
        s(const _Connector()),
        s(_LayerCard(
          numero: 3,
          icon: Icons.blur_on_rounded,
          titulo: 'Monte Carlo',
          texto: 'Corro la capa 2 5.000 veces con ruido biológico, sorteando lo que no medí y la respuesta de cada futuro, pareando cada vida con y sin la palanca. El abanico P10–P90 es lo que no sé de ti, dicho en voz alta.',
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
        s(_PalancasCard(catalogo: catalogo)),
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
        const SizedBox(height: Sp.x3),
        s(Text(
          Env.useMockEngine
              ? 'Motor mock en el dispositivo'
              : 'Motor v$version en el servidor · ${Uri.tryParse(Env.apiBaseUrl)?.host ?? Env.apiBaseUrl}${catalogo == null ? ' · coeficientes: copia local' : ''}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: .4),
        )),
        const SizedBox(height: Sp.x2),
        s(Text(
          'El chat y la lectura de exámenes usan claude-haiku-4-5.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: .4),
        )),
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
              for (final d in BiomarcadorDef.phenoAgeDefs)
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
                  'Los que faltan los imputo con la mediana de referencia de tu edad y sexo y, al simular, los sorteo dentro de su dispersión poblacional: por eso la banda arranca ancha ya hoy y medirlos la angosta.',
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

/// Copia de respaldo de `apps/backend/app/health_metrics/interventions.py`
/// (DYNAMICS): deriva natural por año y ruido anual (SD) de cada biomarcador
/// PhenoAge, en las unidades del backend. Solo se usa si `GET /engine/catalogo`
/// no responde (sin red / backend viejo); con el catálogo del motor se muestra
/// exactamente lo que corre el servidor.
const _dinamicaBackend = <String, ({double deriva, double ruido})>{
  'hs_CRP': (deriva: 0.012, ruido: 0.6),
  'glucosa': (deriva: 0.20, ruido: 4.0),
  'albumina': (deriva: -0.005, ruido: 0.08),
  'creatinina': (deriva: 0.002, ruido: 0.04),
  'fosfatasa_alcalina': (deriva: 0.15, ruido: 4.0),
  'linfocitos_pct': (deriva: -0.05, ruido: 1.5),
  'vcm': (deriva: 0.035, ruido: 1.0),
  'rdw': (deriva: 0.012, ruido: 0.3),
  'leucocitos': (deriva: 0.005, ruido: 0.4),
};

/// Copia de respaldo de `interventions.py` (SCENARIOS → efectos_anuales):
/// cuánto suma cada palanca a la deriva natural, por biomarcador y por año,
/// con la brecha completa.
const _efectosBackend = <String, Map<String, double>>{
  'ejercicio_aerobico': {'hs_CRP': -0.08, 'glucosa': -0.9, 'leucocitos': -0.03},
  'dieta_mediterranea': {'hs_CRP': -0.06, 'glucosa': -0.6, 'albumina': 0.01},
  'cesacion_tabaco': {'leucocitos': -0.11, 'hs_CRP': -0.10, 'vcm': -0.15},
  'sueno_8h': {'hs_CRP': -0.05, 'glucosa': -0.2},
  'reducir_estres': {'hs_CRP': -0.04},
  'reducir_alcohol': {'vcm': -0.20, 'hs_CRP': -0.03},
};

const _nombreHabito = <String, String>{
  'actividad': 'actividad física',
  'alimentacion': 'alimentación',
  'tabaco': 'tabaco',
  'sueno': 'sueño',
  'estres': 'estrés',
  'alcohol': 'alcohol',
};

typedef _Palanca = ({String id, String etiqueta, String descripcion, int esfuerzo, String habito, Map<String, double> efectos});

/// Palancas a mostrar: del catálogo del motor si llegó, si no la copia local.
List<_Palanca> _palancasDe(Map<String, dynamic>? catalogo) {
  final lista = (catalogo?['palancas'] as List?)?.cast<Map>();
  if (lista != null && lista.isNotEmpty) {
    return [
      for (final p in lista)
        (
          id: '${p['id']}',
          etiqueta: SimulationRepository.etiquetasPalanca['${p['id']}'] ?? '${p['nombre'] ?? p['id']}',
          descripcion: '${p['descripcion'] ?? ''}',
          esfuerzo: (p['esfuerzo'] as num?)?.toInt() ?? 0,
          habito: '${p['habito'] ?? ''}',
          efectos: ((p['efectos_anuales'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toDouble())),
        ),
    ];
  }
  return [
    for (final e in SimulationRepository.escenariosBackend.entries)
      (id: e.key, etiqueta: e.value.etiqueta, descripcion: e.value.descripcion, esfuerzo: e.value.esfuerzo, habito: e.value.habito, efectos: _efectosBackend[e.key] ?? const {}),
  ];
}

Map<String, ({double deriva, double ruido})> _dinamicaDe(Map<String, dynamic>? catalogo) {
  final lista = (catalogo?['biomarcadores'] as List?)?.cast<Map>();
  if (lista != null && lista.isNotEmpty) {
    final out = <String, ({double deriva, double ruido})>{};
    for (final b in lista) {
      if (b['phenoage'] != true || b['deriva_anual'] == null) continue;
      out['${b['nombre']}'] = (deriva: (b['deriva_anual'] as num).toDouble(), ruido: (b['ruido_anual_sd'] as num?)?.toDouble() ?? 0);
    }
    if (out.isNotEmpty) return out;
  }
  return _dinamicaBackend;
}

IconData _iconoEscenario(String id) => switch (id) {
  'ejercicio_aerobico' => Icons.directions_walk_rounded,
  'dieta_mediterranea' => Icons.restaurant_rounded,
  'cesacion_tabaco' => Icons.smoke_free_rounded,
  'sueno_8h' => Icons.bedtime_rounded,
  'reducir_estres' => Icons.self_improvement_rounded,
  'reducir_alcohol' => Icons.no_drinks_rounded,
  'combinada' => Icons.auto_awesome_rounded,
  _ => Icons.spa_rounded,
};

class _PalancasCard extends StatelessWidget {
  const _PalancasCard({this.catalogo});

  /// `GET /engine/catalogo` (null = sin red o backend viejo → copia local).
  final Map<String, dynamic>? catalogo;

  /// Coeficientes con hasta tres decimales (−0,002 no puede mostrarse como
  /// "0"); signo explícito y menos tipográfico, igual que `Fmt.delta`.
  static final _tres = NumberFormat('#,##0.###', 'es_CO');
  static String _coef(double v) {
    if (v.abs() < 0.0005) return '0';
    final s = _tres.format(v.abs());
    return v > 0 ? '+$s' : '−$s';
  }

  static String _esfuerzo(int e) => switch (e) { <= 2 => 'esfuerzo bajo', <= 4 => 'esfuerzo medio', _ => 'esfuerzo alto' };

  Widget _fila(TextTheme t, String id, double v, {String? extra}) {
    final def = BiomarcadorDef.byId(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(def?.nombre ?? id, style: t.bodyMedium)),
          const SizedBox(width: Sp.x3),
          Text(
            '${_coef(v)} ${BiomarcadorDef.unidadBonita(def?.unidad ?? '')}/año${extra ?? ''}',
            style: t.labelMedium!.copyWith(
              color: v < 0 ? MoiraiColors.greenInk : MoiraiColors.amberInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dinamica = _dinamicaDe(catalogo);
    final palancas = _palancasDe(catalogo);
    final combinacion = (catalogo?['combinacion'] as Map?)?.cast<String, dynamic>();
    final descuento = (combinacion?['descuento_por_palanca_adicional'] as num?)?.toDouble() ?? 0.08;
    final heterogeneidad = (combinacion?['heterogeneidad_respuesta_sd'] as num?)?.toDouble() ?? 0.5;
    return MoCard(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x3, Sp.gutter, Sp.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Línea base: deriva natural + ruido, sin intervención.
          _SinBordes(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 54, bottom: Sp.x3),
              leading: const MoIconTile(Icons.timeline_rounded, tone: MoTone.sunken, size: 40),
              title: Text('Sin intervención (línea base)', style: t.titleMedium),
              subtitle: Text('Deriva natural por año ± ruido anual, ${dinamica.length} biomarcadores', style: t.bodySmall),
              iconColor: MoiraiColors.ink2,
              collapsedIconColor: MoiraiColors.ink3,
              children: [
                for (final e in dinamica.entries) _fila(t, e.key, e.value.deriva, extra: ' (± ${_tres.format(e.value.ruido)})'),
              ],
            ),
          ),
          for (final p in palancas)
            _SinBordes(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 54, bottom: Sp.x3),
                leading: MoIconTile(_iconoEscenario(p.id), size: 40),
                title: Text(p.etiqueta, style: t.titleMedium),
                subtitle: Text(
                  '${p.efectos.length} biomarcadores · ${_esfuerzo(p.esfuerzo)}${p.habito.isEmpty ? '' : ' · cierra ${_nombreHabito[p.habito] ?? p.habito}'}',
                  style: t.bodySmall,
                ),
                iconColor: MoiraiColors.ink2,
                collapsedIconColor: MoiraiColors.ink3,
                children: [
                  if (p.descripcion.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p.descripcion, style: t.bodySmall)),
                  for (final f in p.efectos.entries) _fila(t, f.key, f.value, extra: f.key == 'hs_CRP' ? ' (∝ tu valor)' : null),
                ],
              ),
            ),
          const SizedBox(height: Sp.x3),
          Text(
            'Aproximados, de literatura (ver `interventions.py`). Cada palanca cierra la brecha de un hábito tuyo: si ya lo tienes, no te la ofrezco; si lo tienes a medias, la mitad del efecto. Tus hábitos de hoy también mueven tu línea base (los malos la empeoran, los buenos la frenan). Al combinar palancas descuento ${Fmt.pct(descuento * 100)} por cada una adicional sobre el mismo biomarcador, y cada futuro responde distinto (±${Fmt.pct(heterogeneidad * 100)}): de ahí el rango de los años ganados.',
            style: t.bodySmall,
          ),
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
