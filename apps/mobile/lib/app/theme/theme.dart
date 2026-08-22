import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Tema Material 3 de Moirai. Una sola apariencia (clara) en Android e iOS:
/// misma tipografía, mismos radios, mismas transiciones.
abstract final class MoiraiTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MoiraiColors.action,
      brightness: Brightness.light,
    ).copyWith(
      primary: MoiraiColors.action,
      onPrimary: Colors.white,
      primaryContainer: MoiraiColors.blueSoft,
      onPrimaryContainer: MoiraiColors.blueInk,
      secondary: MoiraiColors.green,
      onSecondary: Colors.white,
      secondaryContainer: MoiraiColors.greenSoft,
      onSecondaryContainer: MoiraiColors.greenInk,
      tertiary: MoiraiColors.amber,
      tertiaryContainer: MoiraiColors.amberSoft,
      onTertiaryContainer: MoiraiColors.amberInk,
      surface: MoiraiColors.bg,
      onSurface: MoiraiColors.ink,
      onSurfaceVariant: MoiraiColors.ink2,
      surfaceContainerLowest: MoiraiColors.surface,
      surfaceContainerLow: MoiraiColors.surface,
      surfaceContainer: MoiraiColors.surface2,
      surfaceContainerHigh: MoiraiColors.surface2,
      surfaceContainerHighest: MoiraiColors.line,
      outline: MoiraiColors.ink3,
      outlineVariant: MoiraiColors.line,
      // No hay rojo en el sistema: los errores se muestran en ámbar.
      error: MoiraiColors.amberInk,
      onError: Colors.white,
      errorContainer: MoiraiColors.amberSoft,
      onErrorContainer: MoiraiColors.amberInk,
    );

    final body = GoogleFonts.nunitoTextTheme();
    final display = GoogleFonts.fredoka();

    TextStyle d(double size, {FontWeight w = FontWeight.w500, double h = 1.1}) =>
        display.copyWith(
          fontSize: size,
          fontWeight: w,
          height: h,
          color: MoiraiColors.ink,
          letterSpacing: -0.2,
        );

    final textTheme = body
        .copyWith(
          // Números grandes y títulos en Fredoka.
          displayLarge: d(72, h: 0.95),
          displayMedium: d(56, h: 0.96),
          displaySmall: d(40, h: 1.0),
          headlineLarge: d(30, h: 1.15),
          headlineMedium: d(26, h: 1.15),
          headlineSmall: d(22, h: 1.2),
          titleLarge: d(20, h: 1.2),
          titleMedium: body.titleMedium?.copyWith(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            color: MoiraiColors.ink,
            height: 1.3,
          ),
          titleSmall: body.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MoiraiColors.ink,
          ),
          bodyLarge: body.bodyLarge?.copyWith(
            fontSize: 16.5,
            height: 1.5,
            color: MoiraiColors.ink,
          ),
          bodyMedium: body.bodyMedium?.copyWith(
            fontSize: 15,
            height: 1.5,
            color: MoiraiColors.ink2,
          ),
          bodySmall: body.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.4,
            color: MoiraiColors.ink3,
          ),
          labelLarge: body.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          labelMedium: body.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: MoiraiColors.ink2,
          ),
          labelSmall: body.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: MoiraiColors.ink3,
          ),
        )
        .apply(bodyColor: MoiraiColors.ink, displayColor: MoiraiColors.ink);

    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.pill));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MoiraiColors.bg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      // Mismas transiciones en ambas plataformas.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: MoiraiColors.ink, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: MoiraiColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.card),
          side: const BorderSide(color: MoiraiColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: pill,
          textStyle: display.copyWith(fontSize: 16.5, fontWeight: FontWeight.w500),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: pill,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: pill,
          side: const BorderSide(color: MoiraiColors.line, width: 1.5),
          foregroundColor: MoiraiColors.ink,
          textStyle: display.copyWith(fontSize: 16.5, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          foregroundColor: MoiraiColors.blueInk,
          textStyle: body.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: const BorderSide(color: MoiraiColors.line, width: 1.5),
        backgroundColor: MoiraiColors.surface,
        selectedColor: MoiraiColors.blueSoft,
        checkmarkColor: MoiraiColors.blueInk,
        labelStyle: body.labelLarge?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoiraiColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          borderSide: const BorderSide(color: MoiraiColors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          borderSide: const BorderSide(color: MoiraiColors.amber, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          borderSide: const BorderSide(color: MoiraiColors.amber, width: 2),
        ),
        labelStyle: body.bodyMedium?.copyWith(color: MoiraiColors.ink2),
        hintStyle: body.bodyMedium?.copyWith(color: MoiraiColors.ink3),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 6,
        activeTrackColor: MoiraiColors.action,
        inactiveTrackColor: MoiraiColors.line,
        thumbColor: Colors.white,
        overlayColor: Color(0x222C8BCF),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 3),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : MoiraiColors.ink3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MoiraiColors.green : MoiraiColors.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MoiraiColors.surface.withValues(alpha: .92),
        surfaceTintColor: Colors.transparent,
        indicatorColor: MoiraiColors.blueSoft,
        height: 72,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          body.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? MoiraiColors.blueInk : MoiraiColors.ink2,
            size: 24,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MoiraiColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rad.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MoiraiColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.card)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MoiraiColors.ink,
        contentTextStyle: body.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MoiraiColors.action,
        linearTrackColor: MoiraiColors.line,
      ),
      dividerTheme: const DividerThemeData(color: MoiraiColors.line, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: MoiraiColors.blueInk,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
