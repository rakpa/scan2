import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scan2/core/theme/brand.dart';

/// Visual system for Scanella — splash, home and post-scan share it.
///
/// The type scale is [BrandType]. The face comes from the platform
/// (San Francisco on iOS, Roboto on Android) so welcome screens and the
/// crop/library screens no longer mix two fonts.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final generated = ColorScheme.fromSeed(
      seedColor: Brand.blue,
      brightness: brightness,
    );
    final scheme = generated.copyWith(
      primary: Brand.blue,
      onPrimary: Colors.white,
      surface: isLight ? Brand.canvas : generated.surface,
    );

    final platform = Typography.material2021(platform: defaultTargetPlatform);
    final baseFace = isLight ? platform.black : platform.white;

    TextStyle face(TextStyle brand, {Color? color}) {
      return baseFace.bodyMedium!
          .copyWith(
            fontSize: brand.fontSize,
            fontWeight: brand.fontWeight,
            letterSpacing: brand.letterSpacing,
            height: brand.height,
            color: color ?? (isLight ? brand.color : scheme.onSurface),
          );
    }

    final text = TextTheme(
      displaySmall: face(BrandType.display),
      headlineMedium: face(BrandType.headline),
      headlineSmall: face(BrandType.headline),
      titleLarge: face(BrandType.title),
      titleMedium: face(
        BrandType.title.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      titleSmall: face(
        BrandType.title.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      bodyLarge: face(BrandType.body),
      bodyMedium: face(BrandType.body),
      bodySmall: face(BrandType.caption),
      labelLarge: face(BrandType.button, color: Brand.ink),
      labelMedium: face(BrandType.caption.copyWith(fontWeight: FontWeight.w600)),
      labelSmall: face(BrandType.caption.copyWith(fontSize: 11)),
    );

    final platformFace = baseFace.bodyMedium!;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      typography: platform,
      fontFamily: platformFace.fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: isLight ? Brand.canvas : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: isLight ? Brand.canvas : scheme.surface,
        foregroundColor: isLight ? Brand.ink : scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: isLight ? Brand.surface : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Brand.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.blue,
          foregroundColor: Colors.white,
          textStyle: face(BrandType.button, color: Colors.white),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusButton),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.blue,
          textStyle: face(BrandType.button, color: Brand.blue),
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusButton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.blue,
          textStyle: face(BrandType.link),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        showCheckmark: false,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        extendedTextStyle: face(BrandType.button, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        iconColor: Brand.ink,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: isLight ? Brand.surface : scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Brand.surface : scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Brand.surface : scheme.surfaceContainerLow,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: face(BrandType.body, color: Colors.white),
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 1,
        color: Brand.outline,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Brand.blue,
        thumbColor: Brand.blue,
        overlayShape: SliderComponentShape.noOverlay,
      ),
    );
  }
}
