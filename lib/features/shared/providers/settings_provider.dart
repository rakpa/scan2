import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoCapture = true,
    this.defaultFilter = ScanFilter.magic,
    this.shutterSound = true,
    this.useInAppCamera = false,
  });

  final ThemeMode themeMode;

  /// Release the shutter automatically once the page is recognised and still.
  /// On by default: it is the reason to use a scanner rather than the camera.
  final bool autoCapture;

  /// Filter pre-selected for freshly captured pages.
  final ScanFilter defaultFilter;

  final bool shutterSound;

  /// Capture with Scan2's own camera instead of the platform scanner.
  ///
  /// Off by default. The platform scanner (VisionKit / ML Kit) detects edges
  /// noticeably better than the in-app geometric detector, particularly on
  /// small documents and patterned surfaces. The in-app camera stays available
  /// for anyone who wants its batch strip and live overlay.
  final bool useInAppCamera;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? autoCapture,
    ScanFilter? defaultFilter,
    bool? shutterSound,
    bool? useInAppCamera,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      autoCapture: autoCapture ?? this.autoCapture,
      defaultFilter: defaultFilter ?? this.defaultFilter,
      shutterSound: shutterSound ?? this.shutterSound,
      useInAppCamera: useInAppCamera ?? this.useInAppCamera,
    );
  }
}

/// Settings backed by shared_preferences.
///
/// These were previously in-memory only, so every preference reset on each
/// launch — including auto-capture, which a user turning it off would have to
/// turn off again every single time.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _restore();
  }

  static const _themeKey = 'settings.themeMode';
  static const _autoCaptureKey = 'settings.autoCapture';
  static const _filterKey = 'settings.defaultFilter';
  static const _shutterKey = 'settings.shutterSound';
  static const _inAppCameraKey = 'settings.useInAppCamera';

  SharedPreferences? _prefs;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      final themeIndex = prefs.getInt(_themeKey);
      final filterIndex = prefs.getInt(_filterKey);
      state = AppSettings(
        themeMode: themeIndex != null && themeIndex < ThemeMode.values.length
            ? ThemeMode.values[themeIndex]
            : ThemeMode.system,
        autoCapture: prefs.getBool(_autoCaptureKey) ?? true,
        defaultFilter:
            filterIndex != null && filterIndex < ScanFilter.values.length
            ? ScanFilter.values[filterIndex]
            : ScanFilter.magic,
        shutterSound: prefs.getBool(_shutterKey) ?? true,
        useInAppCamera: prefs.getBool(_inAppCameraKey) ?? false,
      );
    } catch (e) {
      debugPrint('Settings unavailable, using defaults: $e');
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setInt(_themeKey, mode.index);
  }

  void setAutoCapture(bool value) {
    state = state.copyWith(autoCapture: value);
    _prefs?.setBool(_autoCaptureKey, value);
  }

  void setDefaultFilter(ScanFilter filter) {
    state = state.copyWith(defaultFilter: filter);
    _prefs?.setInt(_filterKey, filter.index);
  }

  void setShutterSound(bool value) {
    state = state.copyWith(shutterSound: value);
    _prefs?.setBool(_shutterKey, value);
  }

  void setUseInAppCamera(bool value) {
    state = state.copyWith(useInAppCamera: value);
    _prefs?.setBool(_inAppCameraKey, value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});
