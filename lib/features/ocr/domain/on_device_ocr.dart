import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// On-device text recognition: Vision on iOS, ML Kit on Android.
class OnDeviceOcr {
  OnDeviceOcr({this.engine});

  static const channel = MethodChannel('scanella/ocr');

  /// Injected in tests so widget tests do not need a platform view.
  final Future<String> Function(Uint8List bytes)? engine;

  Future<String> recognize(Uint8List bytes) async {
    if (engine != null) return engine!(bytes);
    if (kIsWeb) {
      throw StateError('OCR is available on iOS and Android.');
    }
    try {
      final text = await channel.invokeMethod<String>('recognize', bytes);
      return (text ?? '').trim();
    } on MissingPluginException {
      throw StateError('Text recognition is not available on this build.');
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Could not read text from that image.');
    }
  }
}
