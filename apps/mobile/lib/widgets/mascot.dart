import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme/tokens.dart';

/// Estados de ánimo de la mascota. Nunca "triste": una mascota triste
/// amplifica el miedo (anotación del diseño).
enum MascotMood { idle, working, gentle, happy }

/// Moirai, la mascota. Un compañero redondo que respira, parpadea y, cuando
/// trabaja, tiene tres puntos orbitando. Dibujada en código (sin assets).
class MoiraiMascot extends StatefulWidget {
  const MoiraiMascot({super.key, this.size = 120, this.mood = MascotMood.idle});

  final double size;
  final MascotMood mood;

  @override
  State<MoiraiMascot> createState() => _MoiraiMascotState();
}

class _MoiraiMascotState extends State<MoiraiMascot> with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 6500))..repeat();
  late final AnimationController _mood = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  @override
  void didUpdateWidget(covariant MoiraiMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _mood.forward(from: 0);
  }

  @override
  void dispose() {
    _breath.dispose();
    _orbit.dispose();
    _blink.dispose();
    _mood.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _orbit, _blink, _mood]),
          builder: (_, _) => CustomPaint(
            painter: _MascotPainter(
              breath: _breath.value,
              orbit: _orbit.value,
              blink: _blink.value,
              moodT: Curves.easeOut.transform(_mood.value),
              mood: widget.mood,
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.breath, required this.orbit, required this.blink, required this.moodT, required this.mood});

  final double breath, orbit, blink, moodT;
  final MascotMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final u = s / 100; // unidades relativas (viewBox 100)

    // Respiración: sube y crece apenas.
    final br = math.sin(breath * 2 * math.pi);
    final dy = -1.5 * u * br;
    final scale = 1 + 0.018 * br;

    // Halo radial detrás.
    final halo = Paint()
      ..shader = RadialGradient(colors: [MoiraiColors.blue.withValues(alpha: .28), MoiraiColors.blue.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 50 * u));
    canvas.drawCircle(c, 50 * u, halo);

    canvas.save();
    canvas.translate(c.dx, c.dy + dy);
    canvas.scale(scale);
    canvas.translate(-50 * u, -50 * u);

    // Cuerpo: blob redondeado con degradado suave.
    final body = Path()
      ..moveTo(50 * u, 12 * u)
      ..cubicTo(74 * u, 12 * u, 88 * u, 30 * u, 88 * u, 52 * u)
      ..cubicTo(88 * u, 74 * u, 72 * u, 88 * u, 50 * u, 88 * u)
      ..cubicTo(28 * u, 88 * u, 12 * u, 74 * u, 12 * u, 52 * u)
      ..cubicTo(12 * u, 30 * u, 26 * u, 12 * u, 50 * u, 12 * u)
      ..close();
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8FC6E6), MoiraiColors.blue, Color(0xFF4F96C2)],
        stops: [0, .55, 1],
      ).createShader(Rect.fromLTWH(0, 0, 100 * u, 100 * u));
    canvas.drawShadow(body, MoiraiColors.blueInk.withValues(alpha: .35), 6 * u, false);
    canvas.drawPath(body, bodyPaint);

    // Brillo superior.
    final gloss = Paint()
      ..shader = RadialGradient(center: const Alignment(-.4, -.6), radius: .7, colors: [Colors.white.withValues(alpha: .55), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, 0, 100 * u, 100 * u));
    canvas.drawPath(body, gloss);

    // Mejillas.
    final cheek = Paint()..color = const Color(0xFFF7C8B8).withValues(alpha: .55);
    canvas.drawOval(Rect.fromCenter(center: Offset(28 * u, 58 * u), width: 12 * u, height: 7 * u), cheek);
    canvas.drawOval(Rect.fromCenter(center: Offset(72 * u, 58 * u), width: 12 * u, height: 7 * u), cheek);

    // Ojos: parpadeo en una ventana corta del ciclo.
    final blinkPhase = blink;
    double open = 1;
    if (blinkPhase > .92 && blinkPhase < .98) {
      final t = (blinkPhase - .92) / .06;
      open = 1 - math.sin(t * math.pi) * .9;
    }
    final eyeY = mood == MascotMood.gentle ? 45 * u : 43 * u;
    final eyePaint = Paint()
      ..color = MoiraiColors.ink
      ..style = PaintingStyle.fill;
    final eyeStroke = Paint()
      ..color = MoiraiColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * u
      ..strokeCap = StrokeCap.round;

    if (mood == MascotMood.happy) {
      // Ojos felices: arcos.
      for (final x in [37.0, 63.0]) {
        final p = Path()
          ..moveTo((x - 5) * u, eyeY + 1 * u)
          ..quadraticBezierTo(x * u, (eyeY - 6 * u), (x + 5) * u, eyeY + 1 * u);
        canvas.drawPath(p, eyeStroke);
      }
    } else {
      for (final x in [37.0, 63.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x * u, eyeY), width: 7 * u, height: 8.5 * u * math.max(open, .08)), eyePaint);
        // Brillo del ojo.
        if (open > .5) {
          canvas.drawCircle(Offset((x + 1.4) * u, eyeY - 2 * u), 1.4 * u, Paint()..color = Colors.white.withValues(alpha: .9));
        }
      }
    }

    // Boca según ánimo.
    final mouth = Path();
    switch (mood) {
      case MascotMood.happy:
        mouth
          ..moveTo(40 * u, 58 * u)
          ..quadraticBezierTo(50 * u, 68 * u, 60 * u, 58 * u);
      case MascotMood.gentle:
        mouth
          ..moveTo(44 * u, 60 * u)
          ..quadraticBezierTo(50 * u, 63 * u, 56 * u, 60 * u);
      case MascotMood.working:
        mouth.addOval(Rect.fromCenter(center: Offset(50 * u, 61 * u), width: 7 * u, height: 6 * u));
      case MascotMood.idle:
        mouth
          ..moveTo(43 * u, 59 * u)
          ..quadraticBezierTo(50 * u, 65 * u, 57 * u, 59 * u);
    }
    canvas.drawPath(
      mouth,
      Paint()
        ..color = MoiraiColors.ink.withValues(alpha: .85)
        ..style = mood == MascotMood.working ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 3 * u
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Trabajando: tres puntos orbitando (verde, ámbar, azul tenue).
    if (mood == MascotMood.working) {
      final colors = [MoiraiColors.green, MoiraiColors.amber, MoiraiColors.blueInk];
      for (var i = 0; i < 3; i++) {
        final a = orbit * 2 * math.pi + i * 2 * math.pi / 3;
        final r = 46 * u;
        final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r * .55 + dy);
        final depth = (math.sin(a) + 1) / 2; // adelante/atrás
        canvas.drawCircle(p, (2.6 + depth * 2.2) * u, Paint()..color = colors[i].withValues(alpha: .35 + depth * .65));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MascotPainter o) => true;
}
