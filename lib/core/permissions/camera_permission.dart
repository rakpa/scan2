import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Serializes camera permission prompts.
///
/// `permission_handler` on iOS keeps a single in-flight native request. A
/// second `Permission.camera.request()` while the first dialog is up — or
/// even immediately after it returns — throws
/// `ERROR_ALREADY_REQUESTING_PERMISSIONS` and the scanner error screen.
class CameraPermission {
  CameraPermission._();

  static const alreadyRequestingCode = 'ERROR_ALREADY_REQUESTING_PERMISSIONS';

  static Future<bool>? _inFlight;
  static Duration _pollInterval = const Duration(milliseconds: 200);

  /// True when the user has allowed the camera (including iOS "limited").
  static Future<bool> ensureGranted() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _ensureGranted();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  static Future<bool> _ensureGranted() async {
    var status = await Permission.camera.status;
    if (_isUsable(status)) return true;
    if (status.isPermanentlyDenied || status.isRestricted) return false;

    try {
      status = await Permission.camera.request();
    } on PlatformException catch (e) {
      if (e.code != alreadyRequestingCode) rethrow;
      status = await _waitForInFlightRequest();
    }
    return _isUsable(status);
  }

  static bool _isUsable(PermissionStatus status) =>
      status.isGranted || status.isLimited || status.isProvisional;

  /// Another caller (or the system scanner plugin) already opened the
  /// permission dialog. Wait it out instead of stacking a second request.
  static Future<PermissionStatus> _waitForInFlightRequest() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(_pollInterval);
      final status = await Permission.camera.status;
      if (_isUsable(status) ||
          status.isPermanentlyDenied ||
          status.isRestricted) {
        return status;
      }
    }
    try {
      return await Permission.camera.request();
    } on PlatformException catch (e) {
      if (e.code != alreadyRequestingCode) rethrow;
      return Permission.camera.status;
    }
  }

  /// Human copy for the scanner error screen. Never dump a PlatformException.
  static String describeError(Object error) {
    if (error is CameraAccessDenied) {
      return error.message;
    }
    if (_isAlreadyRequesting(error)) {
      return 'The camera is still asking for permission. Tap Try again.';
    }
    if (error is PlatformException) {
      return 'Couldn’t open the scanner. Check camera access and try again.';
    }
    final text = error.toString();
    if (text.contains(alreadyRequestingCode) ||
        text.contains('already running')) {
      return 'The camera is still asking for permission. Tap Try again.';
    }
    return 'Couldn’t open the scanner. Check camera access and try again.';
  }

  static bool _isAlreadyRequesting(Object error) {
    return error is PlatformException && error.code == alreadyRequestingCode;
  }

  /// Test hook so permission state does not leak across cases.
  @visibleForTesting
  static void debugReset() {
    _inFlight = null;
    _pollInterval = const Duration(milliseconds: 200);
  }

  @visibleForTesting
  static void debugPollInterval(Duration duration) {
    _pollInterval = duration;
  }
}

/// Thrown when the user has not allowed the camera.
class CameraAccessDenied implements Exception {
  const CameraAccessDenied();

  String get message =>
      'Scanella needs camera access to scan documents. '
      'Enable Camera in Settings and try again.';

  @override
  String toString() => message;
}
