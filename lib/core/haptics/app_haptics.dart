import 'package:flutter/services.dart';

/// One place for Scanella's haptic map so widgets do not sprinkle raw
/// [HapticFeedback] calls.
///
/// Generators are prepared on the native side so the first tap after a screen
/// appears is not late. System haptic-off settings are respected by the
/// platform APIs; this helper never forces a buzz.
class AppHaptics {
  const AppHaptics._();

  static const _channel = MethodChannel('scanella/haptics');

  static Future<void> prepare() => _invoke('prepare');

  /// Tabs, filter chips, small icons, list rows, text buttons.
  static Future<void> selection() => _invoke('selection');

  /// Secondary actions: Share, Export, Print, Crop, Rotate, Adjust.
  static Future<void> impactLight() => _invoke('impactLight');

  /// Primary button, large flow card, camera FAB.
  static Future<void> impactMedium() => _invoke('impactMedium');

  /// Save completed, copy success, Enhance applied.
  static Future<void> success() => _invoke('success');

  /// Failed detect, save error.
  static Future<void> error() => _invoke('error');

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

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      await _fallback(method);
    } catch (_) {
      // Never let a haptic failure block a tap.
    }
  }

  /// Tests and platforms without the channel still get a best-effort buzz.
  static Future<void> _fallback(String method) {
    return switch (method) {
      'selection' => HapticFeedback.selectionClick(),
      'impactLight' => HapticFeedback.lightImpact(),
      'impactMedium' => HapticFeedback.mediumImpact(),
      'success' => HapticFeedback.mediumImpact(),
      'error' => HapticFeedback.heavyImpact(),
      _ => Future<void>.value(),
    };
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
