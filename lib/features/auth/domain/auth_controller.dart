import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is using the app, as far as this device knows.
@immutable
class AuthState {
  const AuthState({this.name, this.email, this.signedIn = false});

  final String? name;
  final String? email;
  final bool signedIn;

  String get displayName => name?.trim().isNotEmpty == true
      ? name!.trim()
      : (email?.split('@').first ?? 'there');
}

/// Local-only account state.
///
/// There is no server behind Scanella yet, so this records a profile on the
/// device and unlocks the app. It deliberately never stores a password: a
/// password kept locally cannot authenticate anything and would only be a
/// liability. When a backend exists, this class is the single place that has
/// to start talking to it.
class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState()) {
    _restore();
  }

  static const _nameKey = 'auth.name';
  static const _emailKey = 'auth.email';
  static const _signedInKey = 'auth.signedIn';

  SharedPreferences? _prefs;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      state = AuthState(
        name: prefs.getString(_nameKey),
        email: prefs.getString(_emailKey),
        signedIn: prefs.getBool(_signedInKey) ?? false,
      );
    } catch (e) {
      debugPrint('Account state unavailable: $e');
    }
  }

  Future<void> signUp({required String name, required String email}) async {
    state = AuthState(name: name, email: email, signedIn: true);
    await _persist();
  }

  Future<void> signIn({required String email}) async {
    state = AuthState(name: state.name, email: email, signedIn: true);
    await _persist();
  }

  /// Enters the app without an account. Everything works offline, so this is
  /// a real option rather than a dead end.
  Future<void> continueWithoutAccount() async {
    state = const AuthState(signedIn: true);
    await _persist();
  }

  Future<void> signOut() async {
    state = const AuthState();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setBool(_signedInKey, state.signedIn);
    final name = state.name;
    final email = state.email;
    if (name == null) {
      await prefs.remove(_nameKey);
    } else {
      await prefs.setString(_nameKey, name);
    }
    if (email == null) {
      await prefs.remove(_emailKey);
    } else {
      await prefs.setString(_emailKey, email);
    }
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

/// Shared validation so both auth screens reject the same input.
class AuthValidators {
  const AuthValidators._();

  static String? name(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your name';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your email address';
    // Deliberately loose: the only authority on a valid address is whether
    // mail to it arrives, and strict patterns reject real addresses.
    if (!RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(text)) {
      return 'That does not look like an email address';
    }
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Choose a password';
    if (text.length < 8) return 'Use at least 8 characters';
    return null;
  }
}
