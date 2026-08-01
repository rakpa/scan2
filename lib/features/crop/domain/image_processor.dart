import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum ScanFilter {
  original,
  magic,
  bw,
  grayscale,
  enhance,
}

class _FilterRequest {
  final Uint8List bytes;
  final ScanFilter filter;
  final double brightness;
  final double contrast;

  const _FilterRequest({
    required this.bytes,
    required this.filter,
    required this.brightness,
    required this.contrast,
  });
}

class ImageProcessor {
  /// Applies the selected scan filter and brightness/contrast adjustments.
  Future<Uint8List> applyFilter({
    required List<int> imageBytes,
    required ScanFilter filter,
    double brightness = 0,
    double contrast = 0,
  }) async {
    final bytes =
        imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes);

    // Skip decode work when nothing would change.
    if (filter == ScanFilter.original &&
        brightness.abs() < 0.001 &&
        contrast.abs() < 0.001) {
      return bytes;
    }

    return compute(
      _applyFilterIsolate,
      _FilterRequest(
        bytes: bytes,
        filter: filter,
        brightness: brightness,
        contrast: contrast,
      ),
    );
  }

  static String labelFor(ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.magic:
        return 'Magic';
      case ScanFilter.bw:
        return 'B&W';
      case ScanFilter.grayscale:
        return 'Gray';
      case ScanFilter.enhance:
        return 'Sharp';
    }
  }
}

Uint8List _applyFilterIsolate(_FilterRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;

  var image = img.bakeOrientation(decoded);
  image = _applyTone(image, request.brightness, request.contrast);

  switch (request.filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.grayscale:
      image = img.grayscale(image);
      break;
    case ScanFilter.bw:
      image = _blackAndWhite(image);
      break;
    case ScanFilter.magic:
      image = _magicEnhance(image);
      break;
    case ScanFilter.enhance:
      image = _sharpen(image);
      break;
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

img.Image _applyTone(img.Image image, double brightness, double contrast) {
  if (brightness.abs() < 0.001 && contrast.abs() < 0.001) return image;
  return img.adjustColor(
    image,
    brightness: 1.0 + (brightness * 0.45),
    contrast: 1.0 + (contrast * 0.65),
  );
}

img.Image _blackAndWhite(img.Image image) {
  var out = img.grayscale(image);
  out = img.adjustColor(out, contrast: 1.55);
  for (final p in out) {
    final v = p.luminance > 0.52 ? 255 : 0;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return out;
}

img.Image _magicEnhance(img.Image image) {
  var out = img.adjustColor(
    image,
    contrast: 1.22,
    saturation: 0.85,
    brightness: 1.03,
  );
  return _convolutionSharpen(out, amount: 0.35);
}

img.Image _sharpen(img.Image image) {
  var out = img.adjustColor(image, contrast: 1.12);
  return _convolutionSharpen(out, amount: 0.85);
}

/// Unsharp-style 3x3 kernel. [amount] 0–1 blends toward the sharpened result.
img.Image _convolutionSharpen(img.Image image, {required double amount}) {
  return img.convolution(
    image,
    filter: const [
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ],
    amount: amount.clamp(0.0, 1.0),
  );
}
