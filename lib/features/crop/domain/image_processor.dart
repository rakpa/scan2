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
        return 'Auto Enhance';
      case ScanFilter.grayscale:
        return 'Grayscale';
      case ScanFilter.bw:
        return 'B&W';
      case ScanFilter.enhance:
        return 'Magic Color';
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
  return encodeScan(out);
}

/// Encodes a finished page. B&W is PNG so JPEG ringing cannot blur glyph edges;
/// everything else is high-quality 4:4:4 JPEG.
Uint8List encodeScan(Raster raster) {
  // JPEG 95 / 4:4:4 stays sharp on text and encodes in a fraction of PNG time,
  // which matters when a passport is several full-resolution pages.
  return Uint8List.fromList(img.encodeJpg(raster.toImage(), quality: 95));
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
      out = _magicColor(out);
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
  final radius = _relativeRadius(src, 0.045, min: 4, max: 160);
  final localMean = localMeanLuma(luma, src.width, src.height, radius);

  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    // Ink is anything clearly below the local paper. 10% (not 12% plus a
    // further -2) still keeps paper white on a gradient while holding
    // faint pencil and planner ruling that the older cutoff bleached away.
    final v = luma[p] < localMean[p] * 0.90 ? 0 : 255;
    out.pixels[i++] = v;
    out.pixels[i++] = v;
    out.pixels[i++] = v;
  }
  return out;
}

/// Clean scanned page: neutralize paper, flatten lighting, gentle luma
/// contrast, light sharpen.
///
/// White-balance runs *before* the lighting flatten. Multiplying a cream
/// page by a luma gain first clips red and leaves blue behind — which is
/// how Auto Enhance used to cook notebooks orange. Levels are luma-only
/// for the same reason: stretching R/G/B independently reintroduces the tint.
Raster _autoEnhance(Raster src) {
  final balanced = _whiteBalancePaper(src, strength: 1);
  final flattened = _flattenLighting(
    balanced,
    targetPaper: 242,
    maxGainQ8: 563, // 2.2×
    radiusFraction: 0.08,
  );
  final contrasted = _stretchLuma(
    flattened,
    lowPct: 0.008,
    highPct: 0.995,
    mapLow: 18,
    mapHigh: 246,
  );
  return _sharpen(contrasted, amount: 0.35);
}

/// Colour document mode: keep more of the original paper warmth than Auto
/// Enhance, lift shadows gently, a touch of saturation for diagrams, then
/// sharpen. Not a second copy of Auto Enhance.
Raster _magicColor(Raster src) {
  final balanced = _whiteBalancePaper(src, strength: 0.45);
  final flattened = _flattenLighting(
    balanced,
    targetPaper: 232,
    maxGainQ8: 410, // 1.6×
    radiusFraction: 0.07,
  );
  final sat = _applySaturation(flattened, 0.05);
  return _sharpen(sat, amount: 0.45);
}

/// Divide out a blurred estimate of the page lighting so shadows lift without
/// exploding dark regions (gain is capped).
Raster _flattenLighting(
  Raster src, {
  required int targetPaper,
  required int maxGainQ8,
  required double radiusFraction,
}) {
  final luma = src.toLuma();
  final radius = _relativeRadius(src, radiusFraction, min: 8, max: 220);
  final background = localMeanLuma(luma, src.width, src.height, radius);

  final gainQ8 = Int32List(256);
  for (var v = 0; v < 256; v++) {
    final g = (targetPaper * 256) ~/ math.max(v, 8);
    gainQ8[v] = g.clamp(200, maxGainQ8);
  }

  final out = Raster(src.width, src.height);
  final dst = out.pixels;
  final srcPixels = src.pixels;
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final gain = gainQ8[background[p]];
    final r = (srcPixels[i] * gain) >> 8;
    final g = (srcPixels[i + 1] * gain) >> 8;
    final b = (srcPixels[i + 2] * gain) >> 8;
    dst[i] = r > 255 ? 255 : r;
    dst[i + 1] = g > 255 ? 255 : g;
    dst[i + 2] = b > 255 ? 255 : b;
    i += 3;
  }
  return out;
}

/// Scale channels so the brightest paper pixels are near-neutral white.
/// Cream / yellow paper was surviving illumination flatten and then getting
/// amplified by a per-channel levels stretch.
Raster _whiteBalancePaper(Raster src, {double strength = 1}) {
  final luma = src.toLuma();
  final histogram = Int32List(256);
  for (final v in luma) {
    histogram[v]++;
  }
  final cutoff = _histogramPercentile(histogram, luma.length, 0.70);
  var sumR = 0;
  var sumG = 0;
  var sumB = 0;
  var n = 0;
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    if (luma[p] >= cutoff) {
      sumR += src.pixels[i];
      sumG += src.pixels[i + 1];
      sumB += src.pixels[i + 2];
      n++;
    }
    i += 3;
  }
  if (n < 16) return src;

  final meanR = sumR / n;
  final meanG = sumG / n;
  final meanB = sumB / n;
  final paper = math.max(meanR, math.max(meanG, meanB));
  if (paper < 8) return src;

  var sR = 1 + ((paper / math.max(meanR, 1)) - 1) * strength;
  var sG = 1 + ((paper / math.max(meanG, 1)) - 1) * strength;
  var sB = 1 + ((paper / math.max(meanB, 1)) - 1) * strength;
  sR = sR.clamp(0.72, 1.55);
  sG = sG.clamp(0.72, 1.55);
  sB = sB.clamp(0.72, 1.55);

  final lift = (244 / paper).clamp(1.0, 1.12);
  sR *= lift;
  sG *= lift;
  sB *= lift;

  final out = Raster(src.width, src.height);
  i = 0;
  for (var p = 0; p < luma.length; p++) {
    out.pixels[i] = (src.pixels[i] * sR).round().clamp(0, 255);
    out.pixels[i + 1] = (src.pixels[i + 1] * sG).round().clamp(0, 255);
    out.pixels[i + 2] = (src.pixels[i + 2] * sB).round().clamp(0, 255);
    i += 3;
  }
  return out;
}

/// Contrast on luma only, then add the same delta to R/G/B so chroma (and
/// any leftover paper tint) is not independently stretched.
Raster _stretchLuma(
  Raster src, {
  required double lowPct,
  required double highPct,
  required int mapLow,
  required int mapHigh,
}) {
  final luma = src.toLuma();
  final histogram = Int32List(256);
  for (final v in luma) {
    histogram[v]++;
  }
  final low = _histogramPercentile(histogram, luma.length, lowPct);
  final high = _histogramPercentile(histogram, luma.length, highPct);
  if (high - low < 24) return src;

  final lut = Uint8List(256);
  final span = (high - low).toDouble();
  final mapped = (mapHigh - mapLow).toDouble();
  for (var v = 0; v < 256; v++) {
    lut[v] = (mapLow + ((v - low) / span) * mapped).round().clamp(0, 255);
  }

  final out = Raster(src.width, src.height);
  var i = 0;
  for (var p = 0; p < luma.length; p++) {
    final delta = lut[luma[p]] - luma[p];
    var r = src.pixels[i] + delta;
    var g = src.pixels[i + 1] + delta;
    var b = src.pixels[i + 2] + delta;
    out.pixels[i] = r < 0 ? 0 : (r > 255 ? 255 : r);
    out.pixels[i + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
    out.pixels[i + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
    i += 3;
  }
  return out;
}

int _histogramPercentile(Int32List histogram, int total, double pct) {
  final target = (total * pct).round().clamp(1, total);
  var running = 0;
  for (var v = 0; v < 256; v++) {
    running += histogram[v];
    if (running >= target) return v;
  }
  return 255;
}
