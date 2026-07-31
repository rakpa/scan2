import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppSettings {
  final ThemeMode themeMode;
  final bool autoDetectEdges;
  final bool enhanceByDefault;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoDetectEdges = false,
    this.enhanceByDefault = true,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? autoDetectEdges,
    bool? enhanceByDefault,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      autoDetectEdges: autoDetectEdges ?? this.autoDetectEdges,
      enhanceByDefault: enhanceByDefault ?? this.enhanceByDefault,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  void setThemeMode(ThemeMode mode) =>
      state = state.copyWith(themeMode: mode);

  void setAutoDetectEdges(bool value) =>
      state = state.copyWith(autoDetectEdges: value);

  void setEnhanceByDefault(bool value) =>
      state = state.copyWith(enhanceByDefault: value);
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
