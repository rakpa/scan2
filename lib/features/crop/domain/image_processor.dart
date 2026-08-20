import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';

/// Scan enhancement presets, in the order they appear in the crop screen.
enum ScanFilter { original, magic, grayscale, bw, enhance }

/// Tone + filter settings for one page.
@immutable
class ScanAdjustments {
  const ScanAdjustments({
    this.filter = ScanFilter.magic,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
    this.saturation = 0,
  });

  final ScanFilter filter;

  /// -1..1, neutral at 0.
  final double brightness;

  /// -1..1, neutral at 0.
  final double contrast;

  /// -1..1, neutral at 0. Positive sharpens; negative softens.
  final double sharpness;

  /// -1..1, neutral at 0. Negative desaturates; positive boosts colour.
  final double saturation;

  bool get isNeutralTone =>
      brightness.abs() < 0.001 &&
      contrast.abs() < 0.001 &&
      sharpness.abs() < 0.001 &&
      saturation.abs() < 0.001;

  bool get isNoOp => filter == ScanFilter.original && isNeutralTone;

  ScanAdjustments copyWith({
    ScanFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
    double? saturation,
  }) {
    return ScanAdjustments(
      filter: filter ?? this.filter,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      sharpness: sharpness ?? this.sharpness,
      saturation: saturation ?? this.saturation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanAdjustments &&
      other.filter == filter &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.sharpness == sharpness &&
      other.saturation == saturation;

  @override
  int get hashCode =>
      Object.hash(filter, brightness, contrast, sharpness, saturation);
}

class ImageProcessor {
  /// Applies [adjustments] to encoded [imageBytes] and returns encoded JPEG.
  ///
  /// This decodes and re-encodes, so it costs seconds on a full-resolution
  /// camera frame. The crop screen uses it only when saving; interactive
  /// preview goes through [ScanPreview] instead.
  Future<Uint8List> applyFilter({
    required List<int> imageBytes,
    required ScanFilter filter,
    double brightness = 0,
    double contrast = 0,
    double sharpness = 0,
    double saturation = 0,
  }) async {
    final bytes = imageBytes is Uint8List
        ? imageBytes
        : Uint8List.fromList(imageBytes);
    final adjustments = ScanAdjustments(
      filter: filter,
      brightness: brightness,
      contrast: contrast,
      sharpness: sharpness,
      saturation: saturation,
    );
    if (adjustments.isNoOp) return bytes;

    return compute(
      _applyFilterIsolate,
      _FilterRequest(bytes: bytes, adjustments: adjustments),
    );
  }

  static String labelFor(ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.magic:
        return 'Auto';
      case ScanFilter.grayscale:
        return 'Grayscale';
      case ScanFilter.bw:
        return 'B&W';
      case ScanFilter.enhance:
        return 'Sharpness';
    }
  }
}

class _FilterRequest {
  const _FilterRequest({required this.bytes, required this.adjustments});

  final Uint8List bytes;
  final ScanAdjustments adjustments;
}

Uint8List _applyFilterIsolate(_FilterRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;

  final raster = Raster.fromImage(img.bakeOrientation(decoded));
  final out = applyAdjustments(raster, request.adjustments);
  return Uint8List.fromList(img.encodeJpg(out.toImage(), quality: 92));
}

// ---------------------------------------------------------------------------
// Filter kernels — pure raster math so the preview and the saved page run the
// exact same code, only at different resolutions.
// ---------------------------------------------------------------------------

/// Applies tone then the selected filter, returning a new raster.
Raster applyAdjustments(Raster src, ScanAdjustments adjustments) {
  var out = (adjustments.brightness.abs() < 0.001 &&
          adjustments.contrast.abs() < 0.001)
      ? src.clone()
      : _applyTone(src, adjustments.brightness, adjustments.contrast);

  if (adjustments.saturation.abs() >= 0.001) {
    out = _applySaturation(out, adjustments.saturation);
  }

  switch (adjustments.filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.grayscale:
      out = _grayscale(out);
    case ScanFilter.bw:
      out = _adaptiveBlackAndWhite(out);
    case ScanFilter.magic:
      out = _autoEnhance(out);
    case ScanFilter.enhance:
      out = _sharpen(out, amount: 1.1);
  }

  if (adjustments.sharpness.abs() >= 0.001) {
    if (adjustments.sharpness > 0) {
      out = _sharpen(out, amount: adjustments.sharpness * 1.15);
    } else {
      out = _soften(out, amount: -adjustments.sharpness);
    }
  }
  return out;
}

/// amount -1..1: 0 unchanged, -1 grayscale, +1 boosted colour.
Raster _applySaturation(Raster src, double amount) {
  final factor = 1.0 + amount;
  final luma = src.toLuma();
  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final y = luma[p];
    out.pixels[i] = (y + (src.pixels[i] - y) * factor).round().clamp(0, 255);
    out.pixels[i + 1] = (y + (src.pixels[i + 1] - y) * factor)
        .round()
        .clamp(0, 255);
    out.pixels[i + 2] = (y + (src.pixels[i + 2] - y) * factor)
        .round()
        .clamp(0, 255);
    i += 3;
  }
  return out;
}

/// Blur mixed back in, used for negative sharpness.
Raster _soften(Raster src, {required double amount}) {
  final luma = src.toLuma();
  final radius = _relativeRadius(src, 0.008, min: 1, max: 24);
  final blurred = blurLuma(luma, src.width, src.height, radius);
  final mix = (amount.clamp(0.0, 1.0) * 256).round();
  final keep = 256 - mix;
  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final b = blurred[p];
    out.pixels[i] = ((src.pixels[i] * keep) + (b * mix)) >> 8;
    out.pixels[i + 1] = ((src.pixels[i + 1] * keep) + (b * mix)) >> 8;
    out.pixels[i + 2] = ((src.pixels[i + 2] * keep) + (b * mix)) >> 8;
    i += 3;
  }
  return out;
}

/// Brightness/contrast as a single 256-entry lookup table.
Raster _applyTone(Raster src, double brightness, double contrast) {
  final lut = Uint8List(256);
  // Contrast pivots around mid-grey; brightness is an additive offset.
  final c = 1.0 + contrast * 0.85;
  final b = brightness * 90.0;
  for (var i = 0; i < 256; i++) {
    lut[i] = (((i - 128) * c) + 128 + b).round().clamp(0, 255);
  }

  final out = Raster(src.width, src.height);
  for (var i = 0; i < src.pixels.length; i++) {
    out.pixels[i] = lut[src.pixels[i]];
  }
  return out;
}

Raster _grayscale(Raster src) {
  final luma = src.toLuma();
  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final v = luma[p];
    out.pixels[i++] = v;
    out.pixels[i++] = v;
    out.pixels[i++] = v;
  }
  return out;
}

/// Radius proportional to the image so results look the same at preview and
/// full resolution — a fixed pixel radius would sharpen a thumbnail far more
/// aggressively than the page it previews.
int _relativeRadius(Raster src, double fraction, {int min = 1, int max = 400}) {
  final base = math.min(src.width, src.height) * fraction;
  return base.round().clamp(min, max);
}

/// Unsharp mask driven by the luma channel, so colour stays intact.
Raster _sharpen(Raster src, {required double amount}) {
  final luma = src.toLuma();
  final radius = _relativeRadius(src, 0.004, min: 1, max: 24);
  final blurred = blurLuma(luma, src.width, src.height, radius);

  // Fixed-point amount: the inner loop runs once per pixel on images up to
  // 12MP, where a double multiply and .round() per channel is measurable.
  final amountQ8 = (amount * 256).round();

  final out = Raster(src.width, src.height);
  final dst = out.pixels;
  final srcPixels = src.pixels;
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final delta = ((luma[p] - blurred[p]) * amountQ8) >> 8;
    var r = srcPixels[i] + delta;
    var g = srcPixels[i + 1] + delta;
    var b = srcPixels[i + 2] + delta;
    dst[i] = r < 0 ? 0 : (r > 255 ? 255 : r);
    dst[i + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
    dst[i + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
    i += 3;
  }
  return out;
}

/// Bradley-style adaptive threshold: compare each pixel against the local
/// mean rather than one global cutoff, so a page lit unevenly (a shadow from
/// the phone itself, most of the time) still binarises cleanly.
Raster _adaptiveBlackAndWhite(Raster src) {
  final luma = src.toLuma();
  final radius = _relativeRadius(src, 0.06, min: 4, max: 220);
  final localMean = localMeanLuma(luma, src.width, src.height, radius);

  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    // 12% below the local mean marks ink; the small absolute floor keeps
    // flat paper from turning into noise where the local mean is the pixel.
    final cutoff = localMean[p] * 0.88;
    final v = luma[p] < cutoff - 2 ? 0 : 255;
    out.pixels[i++] = v;
    out.pixels[i++] = v;
    out.pixels[i++] = v;
  }
  return out;
}

/// The "scanned page" look: flatten uneven lighting by dividing out a
/// heavily blurred estimate of the background, stretch what is left onto a
/// clean white point, then sharpen lightly.
Raster _autoEnhance(Raster src) {
  final luma = src.toLuma();
  final radius = _relativeRadius(src, 0.09, min: 6, max: 260);
  final background = localMeanLuma(luma, src.width, src.height, radius);

  // The gain depends only on the background value, which is a byte — so all
  // 256 possible gains are precomputed once as fixed point rather than doing
  // a floating-point divide per pixel.
  final gainQ8 = Int32List(256);
  for (var v = 0; v < 256; v++) {
    gainQ8[v] = (235 * 256) ~/ math.max(v, 1);
  }

  final normalized = Raster(src.width, src.height);
  final dst = normalized.pixels;
  final srcPixels = src.pixels;
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    // Ratio of pixel to local paper brightness, mapped so paper lands at 235.
    final gain = gainQ8[background[p]];
    final r = (srcPixels[i] * gain) >> 8;
    final g = (srcPixels[i + 1] * gain) >> 8;
    final b = (srcPixels[i + 2] * gain) >> 8;
    dst[i] = r > 255 ? 255 : r;
    dst[i + 1] = g > 255 ? 255 : g;
    dst[i + 2] = b > 255 ? 255 : b;
    i += 3;
  }

  final stretched = _stretchLevels(normalized);
  return _sharpen(stretched, amount: 0.55);
}

/// Percentile-based levels stretch: pin the 2nd percentile to black and the
/// 98th to white so faint pencil and grey scans gain real contrast without
/// letting a single specular highlight define the white point.
Raster _stretchLevels(Raster src) {
  final luma = src.toLuma();
  final histogram = Int32List(256);
  for (final v in luma) {
    histogram[v]++;
  }

  final total = luma.length;
  final lowTarget = (total * 0.02).round();
  final highTarget = (total * 0.98).round();

  var low = 0;
  var high = 255;
  var running = 0;
  for (var v = 0; v < 256; v++) {
    running += histogram[v];
    if (running >= lowTarget) {
      low = v;
      break;
    }
  }
  running = 0;
  for (var v = 0; v < 256; v++) {
    running += histogram[v];
    if (running >= highTarget) {
      high = v;
      break;
    }
  }
  if (high - low < 16) return src;

  final lut = Uint8List(256);
  final span = (high - low).toDouble();
  for (var v = 0; v < 256; v++) {
    lut[v] = (((v - low) / span) * 255).round().clamp(0, 255);
  }

  final out = Raster(src.width, src.height);
  for (var i = 0; i < src.pixels.length; i++) {
    out.pixels[i] = lut[src.pixels[i]];
  }
  return out;
}
