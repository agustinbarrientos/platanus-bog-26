import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme/tokens.dart';

/// Estados de ánimo de la mascota. Nunca "triste": una mascota triste
/// amplifica el miedo (anotación del diseño).
enum MascotMood { idle, working, gentle, happy }

/// Moirai, la mascota: una medusa *Turritopsis dohrnii* —el único animal que
/// sabe devolver su reloj celular a un estado juvenil—, la misma silueta del
/// ícono de la app (`design/app-icons/`). Allá es blanca sobre azul de marca;
/// aquí va en negativo (campana azul, cara clara) para que se lea sobre el
/// fondo claro, incluso a 30 px en el avatar del chat.
///
/// Nada de assets: se dibuja en código para que respire, nade, parpadee y
/// cambie de ánimo en cualquier tamaño.
class MoiraiMascot extends StatefulWidget {
  const MoiraiMascot({super.key, this.size = 120, this.mood = MascotMood.idle, this.halo = true});

  final double size;
  final MascotMood mood;

  /// Halo azul detrás. Se apaga en avatares pequeños dentro de burbujas.
  final bool halo;

  @override
  State<MoiraiMascot> createState() => _MoiraiMascotState();
}

class _MoiraiMascotState extends State<MoiraiMascot> with TickerProviderStateMixin {
  /// Nado: la campana se contrae y el cuerpo sube. Los tentáculos van con
  /// retraso sobre esta misma fase, como en una medusa real.
  late final AnimationController _swim = AnimationController(vsync: this, duration: _ritmo(widget.mood))..repeat();
  late final AnimationController _bubbles = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800))..repeat();
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 6500))..repeat();
  late final AnimationController _mood = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  /// Cuando piensa nada más rápido; cuando da una noticia delicada, más lento.
  static Duration _ritmo(MascotMood m) => switch (m) {
    MascotMood.working => const Duration(milliseconds: 1900),
    MascotMood.happy => const Duration(milliseconds: 2400),
    MascotMood.gentle => const Duration(milliseconds: 4200),
    MascotMood.idle => const Duration(milliseconds: 3400),
  };

  @override
  void didUpdateWidget(covariant MoiraiMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _mood.forward(from: 0);
      // Cambiar el ritmo sin cortar el ciclo: retoma donde iba.
      _swim
        ..duration = _ritmo(widget.mood)
        ..repeat(min: 0, max: 1, period: _ritmo(widget.mood));
    }
  }

  @override
  void dispose() {
    _swim.dispose();
    _bubbles.dispose();
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
          animation: Listenable.merge([_swim, _bubbles, _blink, _mood]),
          builder: (_, _) => CustomPaint(
            painter: _MedusaPainter(
              swim: _swim.value,
              bubbles: _bubbles.value,
              blink: _blink.value,
              moodT: Curves.easeOut.transform(_mood.value),
              mood: widget.mood,
              halo: widget.halo,
            ),
          ),
        ),
      ),
    );
  }
}

class _MedusaPainter extends CustomPainter {
  _MedusaPainter({
    required this.swim,
    required this.bubbles,
    required this.blink,
    required this.moodT,
    required this.mood,
    required this.halo,
  });

  final double swim, bubbles, blink, moodT;
  final MascotMood mood;
  final bool halo;

  /// Tentáculos: (x de arranque, desplazamiento del extremo en x e y, grosor,
  /// desfase de la onda). Los dos de afuera barren casi horizontal y los del
  /// medio cuelgan largos, como en el ícono.
  static const _tentaculos = <(double, double, double, double, double)>[
    (34, -23, 17, 7.2, 0.00),
    (44, -8, 31, 6.8, 0.16),
    (58, 9, 33, 6.8, 0.32),
    (67, 23, 18, 7.2, 0.48),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final u = s / 100; // viewBox 100×100
    final detalle = s >= 44; // brillos y mejillas solo cuando se ven

    final fase = swim * 2 * math.pi;
    final pulso = math.sin(fase);
    // La contracción de la campana empuja el cuerpo hacia arriba.
    final dy = -2.4 * u * pulso;
    final anchoCampana = 1 + .045 * pulso;
    final altoCampana = 1 - .038 * pulso;

    if (halo) {
      final r = 52 * u;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [MoiraiColors.blue.withValues(alpha: .22), MoiraiColors.blue.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Burbujas del pensamiento: suben por detrás mientras trabaja.
    if (mood == MascotMood.working || mood == MascotMood.happy) {
      _burbujas(canvas, c, u, dy);
    }

    canvas.save();
    canvas.translate(c.dx - 50 * u, c.dy - 50 * u + dy);

    // ── Tentáculos (detrás de la campana) ──────────────────────────────────
    // Un tono por debajo de la campana, no un contorno negro: en el ícono
    // cuerpo y tentáculos son del mismo color.
    final tinta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(MoiraiColors.blue, MoiraiColors.blueInk, .5)!;
    const baseY = 52.0;
    for (final (x0, dx, caida, grosor, desf) in _tentaculos) {
      final onda = math.sin(fase - desf * 2 * math.pi);
      // Cae recto y después se abre: la curva del ícono.
      final finX = (x0 + dx + onda * 3.4) * u;
      final finY = (baseY + caida * (1 - .05 * onda)) * u;
      final p = Path()
        ..moveTo(x0 * u, (baseY - 6) * u)
        ..cubicTo(
          (x0 + dx * .06) * u,
          (baseY + caida * .5) * u,
          (x0 + dx * .62 + onda * 1.6) * u,
          (baseY + caida * .95) * u,
          finX,
          finY,
        );
      canvas.drawPath(p, Paint.from(tinta)..strokeWidth = grosor * u);
      canvas.drawCircle(Offset(finX, finY), grosor / 2 * u, Paint()..color = tinta.color);
    }

    // ── Campana ────────────────────────────────────────────────────────────
    canvas.save();
    canvas.translate(50 * u, 40 * u);
    canvas.scale(anchoCampana, altoCampana);
    canvas.translate(-50 * u, -40 * u);

    // El `close()` final traza la recta que forma la punta doblada del ícono.
    final campana = Path()
      ..moveTo(33 * u, 13 * u)
      ..cubicTo(60 * u, 6 * u, 78 * u, 21 * u, 78 * u, 41 * u)
      ..cubicTo(78 * u, 55 * u, 68 * u, 63 * u, 55 * u, 63 * u)
      ..lineTo(45 * u, 63 * u)
      ..cubicTo(32 * u, 63 * u, 24 * u, 55 * u, 24 * u, 41 * u)
      ..cubicTo(24 * u, 33 * u, 26 * u, 27 * u, 29 * u, 23 * u)
      ..close();

    canvas.drawShadow(campana, MoiraiColors.blueInk.withValues(alpha: .30), 5 * u, false);
    canvas.drawPath(
      campana,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA9DCF2), MoiraiColors.blue, Color(0xFF4C87AC)],
          stops: [0, .5, 1],
        ).createShader(Rect.fromLTWH(20 * u, 8 * u, 60 * u, 58 * u)),
    );

    if (detalle) {
      // Brillo de gelatina arriba a la izquierda.
      canvas.drawPath(
        campana,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.45, -.75),
            radius: .75,
            colors: [Colors.white.withValues(alpha: .5), Colors.white.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(20 * u, 8 * u, 60 * u, 58 * u)),
      );
    }

    _cara(canvas, u, detalle);
    canvas.restore(); // campana
    canvas.restore(); // cuerpo
  }

  /// Ojos y boca del ícono —dos puntos y una media luna— en claro sobre la
  /// campana azul.
  void _cara(Canvas canvas, double u, bool detalle) {
    final claro = Paint()..color = MoiraiColors.surface;
    final trazo = Paint()
      ..color = MoiraiColors.surface
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.4 * u;

    final gentil = mood == MascotMood.gentle;
    final ojoY = (gentil ? 41.5 : 40.0) * u;
    const ojos = [41.5, 62.5];

    // Parpadeo: una ventana corta del ciclo, nunca un titileo.
    var abierto = 1.0;
    if (blink > .93 && blink < .985) {
      abierto = 1 - math.sin((blink - .93) / .055 * math.pi) * .92;
    }
    if (gentil) abierto *= .62;

    if (mood == MascotMood.happy) {
      for (final x in ojos) {
        canvas.drawPath(
          Path()
            ..moveTo((x - 5.8) * u, ojoY + 2 * u)
            ..quadraticBezierTo(x * u, (ojoY - 6 * u), (x + 5.8) * u, ojoY + 2 * u),
          trazo,
        );
      }
    } else {
      for (final x in ojos) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x * u, ojoY),
            width: 10.6 * u,
            height: 10.6 * u * math.max(abierto, .1),
          ),
          claro,
        );
      }
    }

    // Boca: la media luna del ícono (borde recto arriba, curva abajo).
    final bocaC = Offset(51.5 * u, 49 * u);
    switch (mood) {
      case MascotMood.happy:
        canvas.drawPath(
          Path()..addArc(Rect.fromCenter(center: bocaC, width: 18 * u, height: 16 * u), 0, math.pi),
          claro,
        );
      case MascotMood.idle:
        canvas.drawPath(
          Path()..addArc(Rect.fromCenter(center: bocaC, width: 14.5 * u, height: 12 * u), 0, math.pi),
          claro,
        );
      case MascotMood.gentle:
        // Sonrisa mínima y serena: nunca una mueca triste.
        canvas.drawPath(
          Path()
            ..moveTo(45.5 * u, 49 * u)
            ..quadraticBezierTo(51.5 * u, 52.5 * u, 57.5 * u, 49 * u),
          trazo,
        );
      case MascotMood.working:
        canvas.drawOval(Rect.fromCenter(center: bocaC, width: 7.5 * u, height: 8.5 * u), claro);
    }
  }

  /// Tres burbujas que suben y se desvanecen. Reemplazan al spinner: la
  /// mascota está pensando, no la app está trabada.
  void _burbujas(Canvas canvas, Offset c, double u, double dy) {
    const n = 3;
    for (var i = 0; i < n; i++) {
      final t = (bubbles + i / n) % 1;
      final x = c.dx + (i.isEven ? 27 : -29) * u + math.sin(t * 3.1 + i) * 4 * u;
      final y = c.dy + dy + (32 - 74 * t) * u;
      final alpha = math.sin(t * math.pi).clamp(0.0, 1.0) * .55;
      canvas.drawCircle(
        Offset(x, y),
        (2.2 + 2.4 * t) * u,
        Paint()
          ..color = MoiraiColors.blue.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * u,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MedusaPainter o) => true;
}
