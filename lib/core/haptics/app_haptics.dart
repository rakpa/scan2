import 'package:flutter/services.dart';

/// One place for Scanella's haptic map so widgets do not sprinkle raw
/// [HapticFeedback] calls.
///
/// Selection / light / medium use Flutter's generators (the same path as the
/// camera shutter). Success / error go through the native channel, which can
/// play [UINotificationFeedbackGenerator].
class AppHaptics {
  const AppHaptics._();

  static const _channel = MethodChannel('scanella/haptics');

  static Future<void> prepare() async {
    try {
      await _channel.invokeMethod<void>('prepare');
    } catch (_) {}
  }

  /// Tabs, chips, small icons, list rows, text buttons.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Secondary actions: Share, Export, Print, Crop, Rotate, Adjust.
  /// Also used for large home tiles so the tap is feelable.
  static Future<void> impactLight() => HapticFeedback.lightImpact();

  /// Primary button, camera FAB.
  static Future<void> impactMedium() => HapticFeedback.mediumImpact();

  /// Save completed, copy success, Enhance applied.
  static Future<void> success() => _invokeNative('success', HapticFeedback.mediumImpact);

  /// Failed detect, save error.
  static Future<void> error() => _invokeNative('error', HapticFeedback.heavyImpact);

  static Future<void> play(AppHaptic haptic) {
    return switch (haptic) {
      AppHaptic.none => Future<void>.value(),
      AppHaptic.selection => selection(),
      AppHaptic.impactLight => impactLight(),
      AppHaptic.impactMedium => impactMedium(),
      AppHaptic.success => success(),
      AppHaptic.error => error(),
    };
  }

  static Future<void> _invokeNative(
    String method,
    Future<void> Function() fallback,
  ) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      await fallback();
    }
  }
}

enum AppHaptic {
  none,
  selection,
  impactLight,
  impactMedium,
  success,
  error,
}
