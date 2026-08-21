import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the welcome screen has been dismissed.
///
/// Persisted, because an onboarding screen that reappears on every launch
/// stops being onboarding and becomes an obstacle.
class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier() : super(true) {
    ready = _restore();
  }

  static const _key = 'onboarding.completed';
  SharedPreferences? _prefs;

  /// Completes when the persisted intro flag has been read.
  late final Future<void> ready;

  /// Starts true so a returning user is not sent through intro if restore
  /// is slower than the first redirect. [WelcomeScreen] waits on [ready]
  /// before leaving the splash.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      state = prefs.getBool(_key) ?? false;
    } catch (e) {
      debugPrint('Onboarding state unavailable: $e');
      state = true;
    }
  }

  void complete() {
    state = true;
    _prefs?.setBool(_key, true);
  }

  void reset() {
    state = false;
    _prefs?.setBool(_key, false);
  }
}

final onboardingCompletedProvider =
    StateNotifierProvider<OnboardingNotifier, bool>((ref) {
      return OnboardingNotifier();
    });
