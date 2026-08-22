import 'package:intl/intl.dart';

/// Formato es-CO: miles con punto, decimales con coma, un decimal máximo.
/// "8.240" · "6,4" · "+2,4".
abstract final class Fmt {
  static final _int = NumberFormat.decimalPattern('es_CO');
  static final _one = NumberFormat('#,##0.0', 'es_CO');
  static final _coef = NumberFormat('#,##0.###', 'es_CO');

  static String entero(num v) => _int.format(v.round());

  static String decimal(num v) => _one.format(v);

  /// Un decimal, pero sin ",0" cuando es entero exacto: 4 → "4", 4.1 → "4,1".
  static String corto(num v) {
    if ((v - v.roundToDouble()).abs() < 0.05) return entero(v);
    return decimal(v);
  }

  /// Delta con signo explícito: "+2,4" / "−0,3" (menos tipográfico).
  static String delta(num v) {
    final s = corto(v.abs());
    if (v.abs() < 0.05) return '0';
    return v > 0 ? '+$s' : '−$s';
  }

  /// Coeficientes chicos con signo (hasta 3 decimales): "−0,002", "+0,05".
  static String coeficiente(num v) {
    if (v == 0) return '0';
    final s = _coef.format(v.abs());
    return v > 0 ? '+$s' : '−$s';
  }

  static String anios(num v) => '${corto(v)} ${v.abs() == 1 ? 'año' : 'años'}';

  static String pct(num v) => '${entero(v)}%';

  /// "entre 3,2 y 5,0"
  static String rango(num a, num b) => 'entre ${decimal(a)} y ${decimal(b)}';

  /// "entre +1,1 y +8,6"
  static String rangoDelta(num a, num b) => 'entre ${delta(a)} y ${delta(b)}';
}
