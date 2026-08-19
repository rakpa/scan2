import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual system for Scan2.
///
/// Typography stays on the platform default face — the intent is a more
/// confident surface, not a different voice. What changes is everything
/// around it: a deeper brand colour, flatter cards that rely on a hairline
/// border instead of drop shadow, generous corner radii, and consistent
/// control heights, so the app reads as considered rather than default.
class AppTheme {
  const AppTheme._();

  /// Deep, slightly violet blue. Reads as "document tooling" rather than
  /// stock Material blue.
  static const seed = Color(0xFF2B4ACB);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF7F8FC)
          : scheme.surface,
      textTheme: text.copyWith(
        // Slightly tightened headings; the default tracking looks loose at
        // display sizes on a small screen.
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0.5,
        backgroundColor: isLight ? const Color(0xFFF7F8FC) : scheme.surface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 0.6 : 0.4),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        extendedTextStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        overlayShape: SliderComponentShape.noOverlay,
      ),
    );
  }
}
