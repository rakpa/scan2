import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:scan2/core/permissions/camera_permission.dart';

/// Native document scanner — VisionKit on iOS, ML Kit Document Scanner on Android.
///
/// This is the production-quality edge detection path (platform CV), not the
/// live preview heuristic. Returns cropped page image paths, or null if cancelled.
///
/// Permission is requested once here. The `cunning_document_scanner` Dart API
/// also calls `Permission.camera.request()` before opening VisionKit, and that
/// second prompt is what crashes first launch with
/// `ERROR_ALREADY_REQUESTING_PERMISSIONS`. We talk to the plugin channel
/// directly after our own request so iOS never sees two stacked dialogs.
class NativeDocumentScanner {
  const NativeDocumentScanner();

  static const _channel = MethodChannel('cunning_document_scanner');

  static Future<List<String>?>? _inFlight;

  /// Opens the platform document scanner. Overridable in tests.
  Future<List<String>?> scan({int maxPages = 24}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _scan(maxPages: maxPages);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<List<String>?> _scan({required int maxPages}) async {
    if (kIsWeb) return null;

    final granted = await CameraPermission.ensureGranted();
    if (!granted) {
      throw const CameraAccessDenied();
    }

    final pictures = await _channel.invokeMethod<List<dynamic>>('getPictures', {
      'noOfPages': maxPages,
      'isGalleryImportAllowed': true,
    });
    return pictures?.map((e) => '$e').toList();
  }

  /// Test hook so an in-flight scan does not leak across cases.
  static void debugReset() {
    _inFlight = null;
    CameraPermission.debugReset();
  }
}
