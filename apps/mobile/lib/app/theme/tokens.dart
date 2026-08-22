import 'package:flutter/material.dart';

/// Paleta Moirai. Mismos valores que `design/tokens-hex.mjs` (oklch → sRGB):
/// azul clínico suave como marca, verde para "bien/mejora", ámbar para
/// atención. No existe rojo en el sistema: las malas noticias se dan con
/// contexto, no con alarma.
abstract final class MoiraiColors {
  static const bg = Color(0xFFF3FBFC);
  static const surface = Color(0xFFFEFFFF);
  static const surface2 = Color(0xFFEBF6F8);
  static const ink = Color(0xFF222F3B);
  static const ink2 = Color(0xFF626D78);
  static const ink3 = Color(0xFF8C97A0);
  static const line = Color(0xFFDBE5E8);
  static const blue = Color(0xFF6BAED1);
  static const blueSoft = Color(0xFFD5EEFC);
  static const blueInk = Color(0xFF2C5D7E);
  static const green = Color(0xFF76B590);
  static const greenSoft = Color(0xFFD9F0E1);
  static const greenInk = Color(0xFF2B5E45);
  static const amber = Color(0xFFCFAB72);
  static const amberSoft = Color(0xFFFAECD7);
  static const amberInk = Color(0xFF77562F);

  /// Azul de acción (botón primario, números protagonistas). Viene del DS de
  /// los mockups (`--sky-500`).
  static const action = Color(0xFF2C8BCF);
  static const actionSoft = Color(0xFFEFF8FE);

  /// Gris de las trayectorias "si sigues igual".
  static const ghost = Color(0xFFB5C2CC);

  /// Azul del ícono de la app y del splash de Android (`design/app-icons/`,
  /// `android/app/src/main/res/values/colors.xml`). Es la marca en el
  /// launcher, no un color de UI: dentro de la app manda [action].
  static const brand = Color(0xFF0096EA);
}

/// Escala de espaciado base 4 (del DS): 2, 4, 8, 12, 16, 20, 24, 32, 40, 56.
abstract final class Sp {
  static const double x1 = 2;
  static const double x2 = 4;
  static const double x3 = 8;
  static const double x4 = 12;
  static const double x5 = 16;
  static const double x6 = 20;
  static const double x7 = 24;
  static const double x8 = 32;
  static const double x9 = 40;
  static const double x10 = 56;

  /// Gutter horizontal de pantalla y padding de card.
  static const double gutter = 20;

  /// Separación entre cards apiladas / entre secciones.
  static const double stackCard = 14;
  static const double stackSection = 28;
}

/// Radios: nada afilado. 8 es el mínimo del sistema.
abstract final class Rad {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double card = 24;
  static const double sheet = 32;
  static const double pill = 999;
}

/// Duraciones y curvas. Suave, nunca brusco; los números grandes hacen
/// count-up (~900 ms) y nada parpadea.
abstract final class Motion {
  static const instant = Duration(milliseconds: 80);
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 340);
  static const reveal = Duration(milliseconds: 520);
  static const count = Duration(milliseconds: 900);
  static const draw = Duration(milliseconds: 1400);

  static const soft = Cubic(.32, .72, 0, 1);
  static const out = Cubic(.2, .8, .2, 1);
  static const bounce = Cubic(.34, 1.4, .64, 1);
}
