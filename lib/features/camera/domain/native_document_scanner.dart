import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Native document scanner — VisionKit on iOS, ML Kit Document Scanner on Android.
///
/// This is the production-quality edge detection path (platform CV), not the
/// live preview heuristic. Returns cropped page image paths, or null if cancelled.
class NativeDocumentScanner {
  const NativeDocumentScanner();

  Future<List<String>?> scan({int maxPages = 24}) async {
    if (kIsWeb) return null;

    final granted = await _ensureCameraPermission();
    if (!granted) {
      throw StateError(
        'Camera permission is required to scan documents. '
        'Enable it in Settings and try again.',
      );
    }

    return CunningDocumentScanner.getPictures(
      noOfPages: maxPages,
      isGalleryImportAllowed: true,
    );
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    status = await Permission.camera.request();
    return status.isGranted;
  }
}
