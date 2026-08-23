import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/api/api_client.dart';
import '../../data/models/reporte.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// "Tu reporte": lo que le llevarías a tu médico. Muestra en pantalla el
/// reporte de salud orientativo que arma el backend desde el motor real
/// (`POST /me/health-context/reporte`) —foto de hoy, ejes, recomendaciones
/// con evidencia, ranking de combinaciones, con quién consultar, qué medir—
/// y descarga/comparte el PDF (`/reporte.pdf`, completo o resumen de 1 página).
/// Ningún número se calcula aquí; la app solo lo pinta (ver API_CONTRACT.md).
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _descargando = false;
  bool _descargandoResumen = false;
  String? _aviso;

  static final _fecha = DateFormat('d MMM yyyy', 'es_CO');

  Future<void> _descargar({required bool resumen}) async {
    if (_descargando || _descargandoResumen) return;
    setState(() {
      _aviso = null;
      if (resumen) {
        _descargandoResumen = true;
      } else {
        _descargando = true;
      }
    });
    try {
      final repo = ref.read(reportRepositoryProvider);
      final f = await repo.descargarPdf(resumen: resumen);
      await repo.compartir(f, resumen: resumen);
    } on ApiException catch (e) {
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude generar el PDF. Revisa la conexión e intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _descargando = false;
          _descargandoResumen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rep = ref.watch(reporteProvider);
    final hayResultado = ref.watch(ultimoResultadoProvider) != null;

    return MoScreen(
      appBar: AppBar(
        title: const Text('Tu reporte'),
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
      bottom: rep.hasValue
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoPrimaryButton(
                  label: 'Descargar PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  loading: _descargando,
                  onPressed: _descargandoResumen ? null : () => _descargar(resumen: false),
                ),
                const SizedBox(height: Sp.x3),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _descargando ? null : () => _descargar(resumen: true),
                    icon: _descargandoResumen
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.summarize_outlined, size: 20),
                    label: const Text('Resumen de 1 página'),
                  ),
                ),
              ],
            )
          : null,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MoiraiMascot(size: 58, mood: MascotMood.idle),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lo que le llevarías a tu médico', style: t.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Armo un documento con lo que vi: tu foto de hoy, los ejes de tu sistema, lo que puedes mover y con quién conviene hablar. Orienta; no diagnostica.',
                    style: t.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ).animate().fadeIn(duration: Motion.slow).slideY(begin: .05, end: 0, curve: Motion.out, duration: Motion.slow),
        const SizedBox(height: Sp.x6),
        if (_aviso != null) ...[
          MoNotice(text: _aviso!, tone: MoTone.watch),
          const SizedBox(height: Sp.stackCard),
        ],
        rep.when(
          loading: () => const _Cargando(),
          error: (e, _) => _Error(
            mensaje: e is ApiException ? e.message : 'No pude armar el reporte. Intenta de nuevo en un momento.',
            sinSimulacion: !hayResultado,
            onRetry: () => ref.invalidate(reporteProvider),
          ),
          data: (r) => _Cuerpo(r: r, fecha: _fecha),
        ),
      ],
    );
  }
}

// ── Estados ──────────────────────────────────────────────────────────────
class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Row(
        children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: Sp.x4),
          Expanded(child: Text('Estoy armando tu reporte con el motor real: vuelvo a correr tus futuros con la misma semilla para que coincida con lo que viste.', style: t.bodyMedium)),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.sinSimulacion, required this.onRetry});
  final String mensaje;
  final bool sinSimulacion;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoNotice(text: mensaje, tone: MoTone.watch, action: TextButton(onPressed: onRetry, child: const Text('Reintentar'))),
        if (sinSimulacion) ...[
          const SizedBox(height: Sp.stackCard),
          MoCard(child: Text('El reporte usa tu perfil guardado en el servidor (edad, sexo, exámenes y hábitos). Si aún no has simulado, primero completa tus datos y simula.', style: t.bodyMedium)),
        ],
      ],
    );
  }
}

// ── Cuerpo ───────────────────────────────────────────────────────────────
class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.r, required this.fecha});
  final Reporte r;
  final DateFormat fecha;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    var i = 0;
    Widget s(Widget w) => w.stagger(i++, base: const Duration(milliseconds: 70));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        s(MoNotice(text: r.disclaimer, tone: MoTone.brand, icon: Icons.verified_user_outlined)),
        const SizedBox(height: Sp.stackCard),
        s(MoCard(
          tone: MoTone.brand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoOverline('${r.nombre ?? 'Tu reporte'} · ${fecha.format(r.generadoEn.toLocal())}', color: MoiraiColors.blueInk),
              const SizedBox(height: Sp.x3),
              Text(r.resumen, style: t.titleMedium!.copyWith(color: MoiraiColors.blueInk)),
              const SizedBox(height: Sp.x3),
              Text('ID ${r.id} · ${Fmt.entero(r.trayectorias)} futuros por escenario · semilla ${r.semilla}', style: t.bodySmall!.copyWith(color: MoiraiColors.blueInk.withValues(alpha: .8))),
            ],
          ),
        )),
        const SizedBox(height: Sp.stackSection),

        s(const MoSectionTitle('1 · Tu foto de hoy')),
        const SizedBox(height: Sp.x4),
        s(_FotoHoyCard(f: r.fotoHoy)),
        const SizedBox(height: Sp.stackSection),

        s(const MoSectionTitle('2 · Los ejes de tu sistema', subtitle: 'Un nivel por regla: atención si algo medido está fuera de su rango, a vigilar si está en el borde. Lo inferido no cuenta.')),
        const SizedBox(height: Sp.x4),
        for (final e in r.ejes) ...[s(_EjeCard(e: e)), const SizedBox(height: Sp.x3)],
        const SizedBox(height: Sp.stackSection - Sp.x3),

        s(MoSectionTitle('3 · Tus futuros a ${r.futuros.horizonte} años', subtitle: 'La misma vida con y sin cada palanca (futuros pareados). Estimación, no certeza.')),
        const SizedBox(height: Sp.x4),
        s(_FuturosCard(f: r.futuros)),
        const SizedBox(height: Sp.stackSection),

        s(const MoSectionTitle('4 · Qué puedes hacer', subtitle: 'Las palancas que más mueven tu futuro por unidad de esfuerzo, calculadas para ti, con su respaldo en la literatura.')),
        const SizedBox(height: Sp.x4),
        if (r.recomendaciones.isEmpty)
          s(MoCard(
            tone: MoTone.good,
            child: Text('Con tus hábitos de hoy no encuentro una palanca con brecha abierta: seguir como vas es la recomendación.', style: t.bodyLarge),
          ))
        else
          for (var k = 0; k < r.recomendaciones.length; k++) ...[
            s(_RecomendacionCard(rec: r.recomendaciones[k], rank: k + 1)),
            const SizedBox(height: Sp.x4),
          ],
        if (r.futuros.ranking.length > 1) ...[
          s(_RankingCard(items: r.futuros.ranking)),
          const SizedBox(height: Sp.x3),
        ],
        const SizedBox(height: Sp.stackSection - Sp.x3),

        s(const MoSectionTitle('5 · Con quién consultar')),
        const SizedBox(height: Sp.x4),
        s(MoNotice(text: r.consulta.disclaimer, tone: MoTone.brand, icon: Icons.medical_information_outlined)),
        const SizedBox(height: Sp.x3),
        for (final sug in r.consulta.sugerencias) ...[s(_SugerenciaCard(s: sug)), const SizedBox(height: Sp.x3)],
        s(Text(r.consulta.llevaEsto, style: t.bodySmall)),
        const SizedBox(height: Sp.stackSection),

        s(const MoSectionTitle('6 · Qué datos ayudarían a afinar')),
        const SizedBox(height: Sp.x4),
        s(_AfinarCard(a: r.afinar)),
        const SizedBox(height: Sp.stackSection),

        s(MoFootnote('${r.privacidad}\n${r.fuentes.join(' · ')}')),
      ],
    );
  }
}

// ── 1 · Foto de hoy ──────────────────────────────────────────────────────
class _FotoHoyCard extends StatelessWidget {
  const _FotoHoyCard({required this.f});
  final FotoHoy f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final marcados = f.biomarcadores.where((b) => b.marcado).toList();
    final medidos = f.biomarcadores.where((b) => !b.inferido).toList();
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Stat(label: 'Edad biológica', value: Fmt.decimal(f.edadBiologica), unit: 'años')),
              Expanded(child: _Stat(label: 'Tu edad', value: '${f.edadCronologica}', unit: 'años')),
              Expanded(child: _Stat(label: 'Percentil', value: Fmt.entero(f.percentil), unit: 'de tu edad y sexo')),
            ],
          ),
          if (f.tieneBandaHoy) ...[
            const SizedBox(height: Sp.x4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.blur_on_rounded, size: 16, color: MoiraiColors.blueInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Hoy, ${Fmt.rango(f.rangoHoyP10, f.rangoHoyP90)} por lo que no está medido (P10–P90).',
                    style: t.bodySmall!.copyWith(color: MoiraiColors.blueInk),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Sp.x4),
          Text(f.lectura, style: t.bodyMedium),
          const SizedBox(height: Sp.x5),
          Wrap(
            spacing: Sp.x3,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MoOverline('${f.nMedidos} medidos · ${f.nInferidos} inferidos'),
              if (marcados.isNotEmpty) MoBadge('${marcados.length} a revisar', tone: MoTone.watch) else if (medidos.isNotEmpty) const MoBadge('todo en rango', tone: MoTone.good),
            ],
          ),
          const SizedBox(height: Sp.x3),
          for (final b in f.biomarcadores) ...[
            _BiomarcadorRow(b: b),
            if (b != f.biomarcadores.last) const Divider(height: 14, color: MoiraiColors.line),
          ],
          const SizedBox(height: Sp.x4),
          Text(f.notaPoblacional, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoOverline(label),
        const SizedBox(height: 4),
        Text(value, style: t.headlineLarge!.copyWith(color: MoiraiColors.blueInk, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(unit, style: t.labelMedium),
      ],
    );
  }
}

class _BiomarcadorRow extends StatelessWidget {
  const _BiomarcadorRow({required this.b});
  final BiomarcadorReporte b;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (etiqueta, tono) = switch (b.estado) {
      'en_rango' => ('en rango', MoTone.good),
      'borde' => ('en el borde${b.lado != null ? ' (${b.lado})' : ''}', MoTone.watch),
      'fuera' => ('fuera del rango${b.lado != null ? ' (${b.lado})' : ''}', MoTone.watch),
      'inferido' => ('inferido', MoTone.sunken),
      _ => ('sin rango', MoTone.sunken),
    };
    final valor = b.valor < 10 ? Fmt.decimal(b.valor) : Fmt.corto(b.valor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(b.etiqueta, style: t.titleSmall!.copyWith(color: b.inferido ? MoiraiColors.ink2 : MoiraiColors.ink))),
            const SizedBox(width: Sp.x3),
            Text('$valor ${b.unidad}', style: t.titleSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: b.inferido ? MoiraiColors.ink2 : MoiraiColors.ink)),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MoBadge(etiqueta, tone: tono),
            if (b.rangoReferencia != null) Text('ref. ${b.rangoReferencia}', style: t.labelMedium),
            Text('· ${b.fuente}', style: t.labelMedium),
            if (!b.inferido && b.contribucionAnios.abs() >= 0.05)
              Text('· ${Fmt.delta(b.contribucionAnios)} años hoy', style: t.labelMedium!.copyWith(color: b.contribucionAnios > 0 ? MoiraiColors.amberInk : MoiraiColors.greenInk)),
          ],
        ),
        if (b.nota != null) ...[const SizedBox(height: 4), Text(b.nota!, style: t.bodySmall)],
      ],
    );
  }
}

// ── 2 · Ejes ─────────────────────────────────────────────────────────────
class _EjeCard extends StatelessWidget {
  const _EjeCard({required this.e});
  final EjeReporte e;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tono = switch (e.nivel) { 'optimo' => MoTone.good, 'a_vigilar' || 'atencion' => MoTone.watch, _ => MoTone.sunken };
    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.nombre, style: t.titleMedium)),
              MoBadge(e.nivelTexto, tone: tono),
            ],
          ),
          const SizedBox(height: 6),
          Text(e.explicacion, style: t.bodySmall!.copyWith(color: MoiraiColors.ink2)),
          const SizedBox(height: 6),
          Text(e.biomarcadores.join(' · '), style: t.labelMedium),
        ],
      ),
    );
  }
}

// ── 3 · Futuros ──────────────────────────────────────────────────────────
class _FuturosCard extends StatelessWidget {
  const _FuturosCard({required this.f});
  final FuturosReporte f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final escs = <(EscenarioClave, MoTone)>[
      (f.sigueIgual, MoTone.brand),
      if (f.siMejoras != null) (f.siMejoras!, MoTone.good),
      if (f.siTeDescuidas != null) (f.siTeDescuidas!, MoTone.sunken),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (e, tono) in escs) ...[
          MoCard(
            tone: tono,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoOverline(e.titulo.toUpperCase(), color: tono == MoTone.good ? MoiraiColors.greenInk : tono == MoTone.brand ? MoiraiColors.blueInk : MoiraiColors.ink2),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(Fmt.decimal(e.mediana), style: t.headlineLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: 8),
                    Expanded(child: Text(Fmt.rango(e.p10, e.p90), style: t.titleSmall!.copyWith(color: MoiraiColors.ink2))),
                    if (e.aniosGanados != null && e.aniosGanados! > 0)
                      Text('${Fmt.delta(e.aniosGanados!)} años', style: t.titleMedium!.copyWith(color: MoiraiColors.greenInk)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(e.texto, style: t.bodySmall!.copyWith(color: MoiraiColors.ink2)),
              ],
            ),
          ),
          const SizedBox(height: Sp.x3),
        ],
        Text(f.notaIncertidumbre, style: t.bodySmall),
      ],
    );
  }
}

// ── 4 · Recomendaciones ──────────────────────────────────────────────────
class _RecomendacionCard extends StatelessWidget {
  const _RecomendacionCard({required this.rec, required this.rank});
  final Recomendacion rec;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      tone: rank == 1 ? MoTone.good : MoTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('$rank. ${rec.nombre}', style: t.titleLarge)),
              const SizedBox(width: Sp.x3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${Fmt.delta(rec.aniosGanados)} años', style: t.headlineSmall!.copyWith(color: MoiraiColors.greenInk, fontFeatures: const [FontFeature.tabularFigures()])),
                  if (rec.rangoGanados.length >= 2) Text(Fmt.rangoDelta(rec.rangoGanados[0], rec.rangoGanados[1]), style: t.labelMedium),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(rec.queHacer, style: t.bodyLarge),
          const SizedBox(height: Sp.x3),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MoBadge('mejora en ${Fmt.pct(rec.pctMejoran)}', tone: MoTone.brand, icon: Icons.auto_awesome_rounded),
              MoBadge('esfuerzo ${rec.esfuerzo}/10'),
              if (rec.brecha < 1) MoBadge('ya a medio camino', tone: MoTone.good),
            ],
          ),
          const SizedBox(height: Sp.x4),
          Text(rec.porQue, style: t.bodySmall!.copyWith(color: MoiraiColors.ink2)),
          if (rec.evidencia.isNotEmpty) ...[
            const SizedBox(height: Sp.x4),
            const MoOverline('Respaldo en la literatura'),
            const SizedBox(height: 6),
            for (final ev in rec.evidencia) ...[
              Text(ev.hallazgo, style: t.bodySmall),
              const SizedBox(height: 2),
              Text(ev.fuente, style: t.labelMedium!.copyWith(color: MoiraiColors.ink3, letterSpacing: 0)),
              const SizedBox(height: 6),
            ],
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(Routes.chatCon(pregunta: '¿Cómo empiezo con ${rec.nombre.toLowerCase()}?')),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('Pregúntame cómo empezar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.items});
  final List<RankingItem> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = items.take(6).toList();
    final maxG = top.fold<double>(0, (m, x) => x.aniosGanados > m ? x.aniosGanados : m);
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoOverline('Si combinas palancas (ranking por años ganados)'),
          const SizedBox(height: Sp.x3),
          for (final x in top) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(x.nombre, style: t.bodyMedium)),
                const SizedBox(width: Sp.x3),
                Text('${Fmt.delta(x.aniosGanados)} · ${Fmt.rangoDelta(x.p10, x.p90)}', style: t.labelMedium!.copyWith(color: MoiraiColors.greenInk, letterSpacing: 0)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(Rad.xs),
              child: SizedBox(
                height: 6,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: MoiraiColors.surface2)),
                    FractionallySizedBox(
                      widthFactor: maxG == 0 ? 0 : (x.aniosGanados / maxG).clamp(0.03, 1),
                      alignment: Alignment.centerLeft,
                      child: const DecoratedBox(decoration: BoxDecoration(color: MoiraiColors.green)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text('${Fmt.pct(x.pctMejoran)} de los futuros mejora · esfuerzo ${x.esfuerzo}/10', style: t.labelSmall!.copyWith(letterSpacing: 0)),
            if (x != top.last) const SizedBox(height: Sp.x4),
          ],
          const SizedBox(height: Sp.x4),
          Text('Hasta 3 palancas a la vez, con descuento por solapamiento. Cada fila es la misma vida con y sin esas palancas. El detalle pareado está en "Simular".', style: t.bodySmall),
        ],
      ),
    );
  }
}

// ── 5 · Con quién consultar ──────────────────────────────────────────────
class _SugerenciaCard extends StatelessWidget {
  const _SugerenciaCard({required this.s});
  final SugerenciaConsulta s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tono = switch (s.nivel) { 'optimo' => MoTone.good, 'a_vigilar' || 'atencion' => MoTone.watch, _ => MoTone.sunken };
    final nivelTexto = switch (s.nivel) { 'optimo' => 'en rango', 'a_vigilar' => 'a vigilar', 'atencion' => 'atención', _ => s.nivel };
    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.nombre, style: t.titleMedium)),
              MoBadge(nivelTexto, tone: tono),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.profesional, style: t.titleSmall!.copyWith(color: MoiraiColors.blueInk)),
          const SizedBox(height: 6),
          Text(s.texto, style: t.bodyMedium),
        ],
      ),
    );
  }
}

// ── 6 · Afinar ───────────────────────────────────────────────────────────
class _AfinarCard extends StatelessWidget {
  const _AfinarCard({required this.a});
  final AfinarReporte a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.nota, style: t.bodyMedium),
          if (a.faltantes.isNotEmpty) ...[
            const SizedBox(height: Sp.x4),
            for (final f in a.faltantes) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text(f.etiqueta, style: t.titleSmall)),
                  if (f.reduccionAnios != null)
                    Text('−${Fmt.decimal(f.reduccionAnios!)} años de banda', style: t.labelMedium!.copyWith(color: MoiraiColors.blueInk, letterSpacing: 0))
                  else if (f.fraccion != null)
                    Text(Fmt.pct(f.fraccion! * 100), style: t.labelMedium!.copyWith(color: MoiraiColors.blueInk, letterSpacing: 0)),
                ],
              ),
              if (f != a.faltantes.last) const Divider(height: 12, color: MoiraiColors.line),
            ],
          ],
          const SizedBox(height: Sp.x3),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(Routes.whatToMeasure),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Ver qué medir'),
            ),
          ),
        ],
      ),
    );
  }
}
