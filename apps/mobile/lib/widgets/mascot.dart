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
///
/// El movimiento calca el Lottie `moirai-plain.json` de la web (la versión
/// que se queda quieta en su sitio, no la que cruza la pantalla): la campana
/// sube y baja rígida cada 2 s colgada de un pivote arriba; los tentáculos la
/// siguen con retraso, se abren en abanico y vuelven a caer juntos en cada
/// pulso; y una deriva lenta de 12 s inclina el cuerpo a un lado, sostiene, y
/// vuelve, con la cola arrastrándose hacia el lado contrario.
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
  /// Pulso de nado: el cuerpo sube y baja; los tentáculos van con retraso
  /// sobre esta misma fase y se abren en abanico, como en una medusa real.
  late final AnimationController _swim = AnimationController(vsync: this, duration: _ritmo(widget.mood))..repeat();

  /// Deriva lenta: se inclina a un lado, sostiene, vuelve (un ciclo de 12 s,
  /// igual que el Lottie). No depende del ánimo.
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  late final AnimationController _bubbles = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800))..repeat();
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 6500))..repeat();
  late final AnimationController _mood = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  /// El Lottie pulsa cada 2 s. Cuando piensa nada más rápido; cuando da una
  /// noticia delicada, más lento.
  static Duration _ritmo(MascotMood m) => switch (m) {
    MascotMood.working => const Duration(milliseconds: 1500),
    MascotMood.happy => const Duration(milliseconds: 1800),
    MascotMood.gentle => const Duration(milliseconds: 2800),
    MascotMood.idle => const Duration(milliseconds: 2000),
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
    _drift.dispose();
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
          animation: Listenable.merge([_swim, _drift, _bubbles, _blink, _mood]),
          builder: (_, _) => CustomPaint(
            painter: _MedusaPainter(
              swim: _swim.value,
              drift: _drift.value,
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
    required this.drift,
    required this.bubbles,
    required this.blink,
    required this.moodT,
    required this.mood,
    required this.halo,
  });

  final double swim, drift, bubbles, blink, moodT;
  final MascotMood mood;
  final bool halo;

  /// Tentáculos: (x de arranque, desplazamiento del extremo en x e y, grosor,
  /// barrido del abanico en x (con signo, hacia afuera) y en y (hacia arriba)).
  /// Los dos de afuera barren casi horizontal y se abren mucho más que los
  /// del medio, que cuelgan largos, como en el ícono y en el Lottie.
  static const _tentaculos = <(double, double, double, double, double, double)>[
    (34, -20, 19, 7.2, -3.0, 2.6),
    (44, -8, 30, 6.8, -1.8, 1.4),
    (58, 9, 32, 6.8, 2.4, 1.2),
    (67, 20, 19, 7.2, 3.0, 2.6),
  ];

  /// Pivotes (viewBox 100): el cuerpo cuelga de lo alto de la campana y la
  /// cola gira desde el borde inferior, como los nulos del Lottie.
  static const _pivoteCuerpo = Offset(51, 15.5);
  static const _pivoteCola = Offset(51, 59);

  /// Deriva lenta en [-1, 1]: +1 = inclinada a la derecha, −1 = a la
  /// izquierda. Calca los keyframes del Lottie (loop de 360 frames): sostiene
  /// a un lado 5 s, cambia en 1 s, sostiene 5 s, vuelve en 1 s.
  static double _deriva(double t) {
    const ida = .422, llegada = .503, vuelta = .919;
    if (t < ida) return 1;
    if (t < llegada) return 1 - 2 * Curves.easeInOut.transform((t - ida) / (llegada - ida));
    if (t < vuelta) return -1;
    return -1 + 2 * Curves.easeInOut.transform((t - vuelta) / (1 - vuelta));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final u = s / 100; // viewBox 100×100
    final detalle = s >= 44; // brillos y mejillas solo cuando se ven

    // Fase 0 = cuerpo en lo más alto. Campana rígida (en el Lottie no se
    // deforma): solo sube y baja ±2,5 u con ease-in-out, que es casi un coseno.
    final fase = swim * 2 * math.pi;
    final dy = -2.5 * u * math.cos(fase);
    // La cola llega tarde (≈132° de retraso, como el nulo de la cola) y se
    // abre en abanico justo después de que el cuerpo pasa por arriba.
    final dyCola = -2.5 * u * math.cos(fase - 2.30);
    final abanico = math.cos(fase - 2 * math.pi / 3); // +1 abiertos, −1 juntos
    // Deriva: el cuerpo se inclina −1° ± 6° y la cola se arrastra al lado
    // contrario. El Lottie gira la cola ±19°, pero con los tentáculos de
    // afuera casi horizontales eso los levanta por encima de la campana y
    // parecen brazos; acá giran poco y se desplazan más, que lee igual.
    final deriva = _deriva(drift);
    final giroCuerpo = (-1 + 6 * deriva) * math.pi / 180;
    final giroCola = 8 * deriva * math.pi / 180;
    final dxCola = -3.0 * u * deriva;

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
    // Todo el cuerpo (campana + cola) cuelga del pivote superior.
    canvas.translate(_pivoteCuerpo.dx * u, _pivoteCuerpo.dy * u);
    canvas.rotate(giroCuerpo);
    canvas.translate(-_pivoteCuerpo.dx * u, -_pivoteCuerpo.dy * u);

    // ── Tentáculos (detrás de la campana) ──────────────────────────────────
    // Un tono por debajo de la campana, no un contorno negro: en el ícono
    // cuerpo y tentáculos son del mismo color.
    canvas.save();
    canvas.translate(dxCola + _pivoteCola.dx * u, dyCola + _pivoteCola.dy * u);
    canvas.rotate(giroCola);
    canvas.translate(-_pivoteCola.dx * u, -_pivoteCola.dy * u);
    final tinta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(MoiraiColors.blue, MoiraiColors.blueInk, .5)!;
    const baseY = 52.0;
    for (final (x0, dx, caida, grosor, barridoX, barridoY) in _tentaculos) {
      // Cae recto y después se abre: la curva del ícono. El extremo barre en
      // abanico (afuera y arriba cuando se abre, adentro y abajo cuando cae).
      final finX = (x0 + dx + abanico * barridoX) * u;
      final finY = (baseY + caida - abanico * barridoY) * u;
      final p = Path()
        ..moveTo(x0 * u, (baseY - 6) * u)
        ..cubicTo(
          (x0 + dx * .06) * u,
          (baseY + caida * .5) * u,
          (x0 + dx * .62 + abanico * barridoX * .55) * u,
          (baseY + caida * .95 - abanico * barridoY * .5) * u,
          finX,
          finY,
        );
      canvas.drawPath(p, Paint.from(tinta)..strokeWidth = grosor * u);
      canvas.drawCircle(Offset(finX, finY), grosor / 2 * u, Paint()..color = tinta.color);
    }
    canvas.restore(); // cola

    // ── Campana ────────────────────────────────────────────────────────────
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
