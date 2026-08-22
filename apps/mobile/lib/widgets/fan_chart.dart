import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme/tokens.dart';
import '../core/format.dart';
import '../data/models/simulacion.dart';

/// El abanico de futuros: trayectorias individuales (fantasma), banda P10–P90 y
/// mediana, con eje en años de edad cronológica. `progress` (0–1) dibuja la
/// curva de izquierda a derecha; `trayectoriasVisibles` controla cuántas líneas
/// individuales se muestran (para la pantalla "simulando en vivo").
///
/// Si se pasa `comparacion`, se dibuja una segunda banda/mediana en verde
/// (escenario) sobre la base en gris (contrafactual pareado).
class FanChart extends StatelessWidget {
  const FanChart({
    super.key,
    required this.edad0,
    this.curva,
    this.comparacion,
    this.trayectorias = const [],
    this.trayectoriasVisibles,
    this.progress = 1,
    this.height = 200,
    this.mostrarEjes = true,
    this.colorBase,
    this.colorComparacion,
    this.etiquetaBase,
    this.etiquetaComparacion,
    this.identidad = true,
  });

  final int edad0;
  final Curva? curva;
  final Curva? comparacion;
  final List<List<double>> trayectorias;
  final int? trayectoriasVisibles;
  final double progress;
  final double height;
  final bool mostrarEjes;
  final Color? colorBase;
  final Color? colorComparacion;
  final String? etiquetaBase;
  final String? etiquetaComparacion;

  /// Dibuja la línea punteada "edad biológica = cronológica".
  final bool identidad;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FanPainter(
          edad0: edad0,
          curva: curva,
          comparacion: comparacion,
          trayectorias: trayectorias,
          visibles: trayectoriasVisibles ?? trayectorias.length,
          progress: progress.clamp(0, 1),
          mostrarEjes: mostrarEjes,
          colorBase: colorBase ?? (comparacion != null ? MoiraiColors.ghost : MoiraiColors.action),
          colorComp: colorComparacion ?? MoiraiColors.green,
          etiquetaBase: etiquetaBase,
          etiquetaComp: etiquetaComparacion,
          identidad: identidad,
          labelStyle: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 0, color: MoiraiColors.ink3),
        ),
      ),
    );
  }
}

class _FanPainter extends CustomPainter {
  _FanPainter({
    required this.edad0,
    required this.curva,
    required this.comparacion,
    required this.trayectorias,
    required this.visibles,
    required this.progress,
    required this.mostrarEjes,
    required this.colorBase,
    required this.colorComp,
    required this.etiquetaBase,
    required this.etiquetaComp,
    required this.identidad,
    required this.labelStyle,
  });

  final int edad0;
  final Curva? curva;
  final Curva? comparacion;
  final List<List<double>> trayectorias;
  final int visibles;
  final double progress;
  final bool mostrarEjes;
  final Color colorBase, colorComp;
  final String? etiquetaBase, etiquetaComp;
  final bool identidad;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final padL = mostrarEjes ? 30.0 : 6.0, padR = 10.0, padT = 10.0, padB = mostrarEjes ? 22.0 : 6.0;
    final w = size.width - padL - padR, h = size.height - padT - padB;

    // Rango Y a partir de todo lo que se dibuja.
    final ys = <double>[];
    void addC(Curva? c) {
      if (c == null) return;
      ys.addAll(c.p10);
      ys.addAll(c.p90);
    }

    addC(curva);
    addC(comparacion);
    for (final t in trayectorias.take(visibles)) {
      ys.addAll(t);
    }
    final anios = curva?.anios.length ?? comparacion?.anios.length ?? (trayectorias.isNotEmpty ? trayectorias.first.length : 11);
    if (ys.isEmpty) {
      ys.addAll([edad0 - 5.0, edad0 + anios + 5.0]);
    }
    if (identidad) {
      ys.add(edad0.toDouble());
      ys.add(edad0 + anios - 1.0);
    }
    var yMin = ys.reduce(math.min), yMax = ys.reduce(math.max);
    final pad = math.max(2.0, (yMax - yMin) * .12);
    yMin -= pad;
    yMax += pad;

    double sx(num i) => padL + (i / (anios - 1)) * w;
    double sy(num v) => padT + (1 - (v - yMin) / (yMax - yMin)) * h;

    // Cuadrícula suave + ejes.
    final grid = Paint()
      ..color = MoiraiColors.line
      ..strokeWidth = 1;
    if (mostrarEjes) {
      final ticks = _ticks(yMin, yMax);
      for (final t in ticks) {
        final y = sy(t);
        canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
        _text(canvas, Fmt.entero(t), Offset(0, y - 6), labelStyle, maxW: padL - 6, align: TextAlign.right);
      }
      for (var i = 0; i < anios; i += (anios > 12 ? 5 : 2)) {
        final x = sx(i);
        _text(canvas, i == 0 ? 'hoy' : '+$i', Offset(x - 14, padT + h + 6), labelStyle, maxW: 28, align: TextAlign.center);
      }
      _text(canvas, 'años', Offset(padL + w - 30, padT + h + 6), labelStyle, maxW: 30, align: TextAlign.right);
    }

    // Línea identidad (edad biológica = cronológica).
    if (identidad) {
      final p = Path()
        ..moveTo(sx(0), sy(edad0))
        ..lineTo(sx(anios - 1), sy(edad0 + anios - 1));
      _dashed(canvas, p, Paint()
        ..color = MoiraiColors.ink3.withValues(alpha: .7)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke);
    }

    // Recorte horizontal según progreso (la curva "se dibuja").
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, padL + w * progress + 2, size.height));

    // Trayectorias fantasma.
    final ghost = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final n = math.min(visibles, trayectorias.length);
    for (var k = 0; k < n; k++) {
      final t = trayectorias[k];
      final alpha = comparacion != null ? .16 : .22;
      ghost.color = colorBase.withValues(alpha: alpha);
      canvas.drawPath(_line(t, sx, sy), ghost);
    }

    void banda(Curva c, Color color, {bool principal = true}) {
      final band = Path()..moveTo(sx(0), sy(c.p90[0]));
      for (var i = 1; i < c.anios.length; i++) {
        band.lineTo(sx(i), sy(c.p90[i]));
      }
      for (var i = c.anios.length - 1; i >= 0; i--) {
        band.lineTo(sx(i), sy(c.p10[i]));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = color.withValues(alpha: principal ? .16 : .12));
      canvas.drawPath(
        _line(c.mediana, sx, sy),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = principal ? 3 : 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (curva != null) banda(curva!, colorBase, principal: comparacion == null);
    if (comparacion != null) banda(comparacion!, colorComp);
    canvas.restore();

    // Punto "hoy" y puntos finales.
    if (curva != null && progress > 0) {
      canvas.drawCircle(Offset(sx(0), sy(curva!.mediana[0])), 5, Paint()..color = MoiraiColors.surface);
      canvas.drawCircle(Offset(sx(0), sy(curva!.mediana[0])), 5, Paint()
        ..color = comparacion != null ? MoiraiColors.ink2 : colorBase
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
    }
    if (progress >= 1) {
      if (curva != null && etiquetaBase != null) {
        _endLabel(canvas, Offset(sx(anios - 1), sy(curva!.mediana.last)), etiquetaBase!, comparacion != null ? MoiraiColors.ink2 : colorBase, padL + w, up: comparacion == null || curva!.mediana.last >= (comparacion?.mediana.last ?? 0));
      }
      if (comparacion != null && etiquetaComp != null) {
        _endLabel(canvas, Offset(sx(anios - 1), sy(comparacion!.mediana.last)), etiquetaComp!, colorComp, padL + w, up: comparacion!.mediana.last > (curva?.mediana.last ?? 0));
      }
    }
  }

  Path _line(List<double> vals, double Function(num) sx, double Function(num) sy) {
    final p = Path();
    for (var i = 0; i < vals.length; i++) {
      final o = Offset(sx(i), sy(vals[i]));
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        // Curva suave (Catmull-Rom simplificada con control en el punto medio).
        final prev = Offset(sx(i - 1), sy(vals[i - 1]));
        final cx = (prev.dx + o.dx) / 2;
        p.cubicTo(cx, prev.dy, cx, o.dy, o.dx, o.dy);
      }
    }
    return p;
  }

  void _endLabel(Canvas canvas, Offset at, String text, Color color, double right, {required bool up}) {
    canvas.drawCircle(at, 4.5, Paint()..color = color);
    canvas.drawCircle(at, 4.5, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final st = labelStyle.copyWith(color: color, fontWeight: FontWeight.w800, fontSize: 11);
    _text(canvas, text, Offset(right - 120, up ? at.dy - 18 : at.dy + 6), st, maxW: 120, align: TextAlign.right);
  }

  void _text(Canvas canvas, String s, Offset o, TextStyle st, {double maxW = 60, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: ui.TextDirection.ltr, textAlign: align, maxLines: 1)..layout(minWidth: maxW, maxWidth: maxW);
    tp.paint(canvas, o);
  }

  void _dashed(Canvas canvas, Path p, Paint paint, {double dash = 5, double gap = 5}) {
    for (final m in p.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  List<double> _ticks(double a, double b) {
    final span = b - a;
    final step = span > 40 ? 10.0 : span > 16 ? 5.0 : span > 8 ? 2.0 : 1.0;
    final out = <double>[];
    for (var v = (a / step).ceil() * step; v <= b; v += step) {
      out.add(v);
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _FanPainter o) =>
      o.progress != progress || o.visibles != visibles || o.curva != curva || o.comparacion != comparacion || o.trayectorias != trayectorias;
}
