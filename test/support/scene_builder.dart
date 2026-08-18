import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';

/// Renders synthetic "photo of a document" scenes with a known ground-truth
/// quad, so detector accuracy can be measured rather than eyeballed.
class Scene {
  Scene({
    required this.luma,
    required this.width,
    required this.height,
    required this.corners,
  });

  final Uint8List luma;
  final int width;
  final int height;

  /// Ground-truth page corners in pixel coordinates, ordered TL, TR, BR, BL.
  final List<Offset> corners;

  List<Offset> get normalizedCorners => corners
      .map((c) => Offset(c.dx / width, c.dy / height))
      .toList(growable: false);
}

/// Builds a scene with a page over a background.
///
/// Defaults model the common case: a light page on a mid-grey desk, lit
/// slightly unevenly, with printed text and sensor noise.
Scene buildScene({
  int width = 240,
  int height = 180,
  required List<Offset> corners,
  int pageBrightness = 225,
  int backgroundBrightness = 110,
  double lightingFalloff = 0.18,
  double noise = 3,
  bool text = true,
  int seed = 7,
  double backgroundTexture = 0,
}) {
  final random = math.Random(seed);
  final luma = Uint8List(width * height);

  // Background: a gentle gradient plus optional texture (wood grain, a desk
  // mat) so detectors are not rewarded for assuming a flat backdrop.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var v = backgroundBrightness.toDouble();
      v += (x / width - 0.5) * 12;
      v += (y / height - 0.5) * 8;
      if (backgroundTexture > 0) {
        v += math.sin(x * 0.4) * backgroundTexture;
        v += math.sin(y * 0.27 + 1.3) * backgroundTexture * 0.6;
      }
      v += (random.nextDouble() - 0.5) * noise * 2;
      luma[y * width + x] = v.round().clamp(0, 255);
    }
  }

  // Page: point-in-polygon fill with a lighting gradient across the sheet.
  final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = Offset(x + 0.5, y + 0.5);
      if (!_insideQuad(p, tl, tr, br, bl)) continue;
      var v = pageBrightness.toDouble();
      v *= 1 - lightingFalloff * (x / width);
      v += (random.nextDouble() - 0.5) * noise * 2;
      luma[y * width + x] = v.round().clamp(0, 255);
    }
  }

  if (text) {
    final homography = Homography.unitSquareTo(tl, tr, br, bl);
    // Body text as dark bands in page-local space, inset from the margins.
    for (var line = 0; line < 14; line++) {
      final v = 0.14 + line * 0.055;
      if (v > 0.9) break;
      final lineLength = 0.55 + (line % 4) * 0.08;
      for (var t = 0.0; t < lineLength; t += 0.0025) {
        final u = 0.12 + t;
        final p = homography.map(u, v);
        _stamp(luma, width, height, p, 55);
      }
    }
  }

  return Scene(luma: luma, width: width, height: height, corners: corners);
}

void _stamp(Uint8List luma, int w, int h, Offset p, int value) {
  final x = p.dx.round();
  final y = p.dy.round();
  for (var dy = 0; dy <= 1; dy++) {
    for (var dx = 0; dx <= 1; dx++) {
      final xx = x + dx;
      final yy = y + dy;
      if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      luma[yy * w + xx] = value;
    }
  }
}

bool _insideQuad(Offset p, Offset a, Offset b, Offset c, Offset d) {
  return _sameSide([a, b, c, d], p);
}

bool _sameSide(List<Offset> poly, Offset p) {
  var positive = false;
  var negative = false;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    if (cross > 0) positive = true;
    if (cross < 0) negative = true;
    if (positive && negative) return false;
  }
  return true;
}

/// Mean corner distance between two ordered quads, as a fraction of the
/// image diagonal — the natural resolution-independent accuracy measure.
double cornerError(
  List<Offset> found,
  List<Offset> expected,
  int width,
  int height,
) {
  final diagonal = math.sqrt(width * width + height * height);
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    final f = Offset(found[i].dx * width, found[i].dy * height);
    sum += (f - expected[i]).distance;
  }
  return (sum / 4) / diagonal;
}

/// Renders a colour scene as an RGB [Raster], for exercising the full capture
/// pipeline (detect → warp → enhance) rather than the detector alone.
Raster buildColorScene({
  int width = 900,
  int height = 1200,
  required List<Offset> corners,
  int pageR = 236,
  int pageG = 233,
  int pageB = 226,
  int backgroundR = 96,
  int backgroundG = 88,
  int backgroundB = 80,
  double lightingFalloff = 0.22,
  int seed = 11,
  int textLines = 20,
  List<Offset> markers = const [],
}) {
  final random = math.Random(seed);
  final raster = Raster(width, height);

  void put(int x, int y, int r, int g, int b) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 3;
    raster.pixels[i] = r.clamp(0, 255);
    raster.pixels[i + 1] = g.clamp(0, 255);
    raster.pixels[i + 2] = b.clamp(0, 255);
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final n = (random.nextDouble() - 0.5) * 6;
      put(
        x,
        y,
        (backgroundR + n).round(),
        (backgroundG + n).round(),
        (backgroundB + n).round(),
      );
    }
  }

  final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!_insideQuad(Offset(x + 0.5, y + 0.5), tl, tr, br, bl)) continue;
      // Light falls off across the sheet, as it does when a phone shades it.
      final shade = 1 - lightingFalloff * (x / width);
      final n = (random.nextDouble() - 0.5) * 4;
      put(
        x,
        y,
        (pageR * shade + n).round(),
        (pageG * shade + n).round(),
        (pageB * shade + n).round(),
      );
    }
  }

  // Printed text in page-local space, so it stays inside the page under any
  // perspective.
  final homography = Homography.unitSquareTo(tl, tr, br, bl);
  for (var line = 0; line < textLines; line++) {
    final v = 0.08 + line * (0.84 / textLines);
    final length = 0.62 + (line % 5) * 0.05;
    for (var t = 0.0; t < length; t += 0.0012) {
      final p = homography.map(0.10 + t, v);
      for (var dy = 0; dy < 3; dy++) {
        for (var dx = 0; dx < 3; dx++) {
          put(p.dx.round() + dx, p.dy.round() + dy, 38, 36, 40);
        }
      }
    }
  }

  // Registration marks at known page-local (u, v). Recovering these from a
  // warped image is the direct test of whether perspective was corrected.
  for (final marker in markers) {
    final p = homography.map(marker.dx, marker.dy);
    for (var dy = -5; dy <= 5; dy++) {
      for (var dx = -5; dx <= 5; dx++) {
        put(p.dx.round() + dx, p.dy.round() + dy, 12, 12, 14);
      }
    }
  }

  return raster;
}

/// Centre of the darkest blob nearest [expected] in page-relative coordinates,
/// or null when no marker is found there.
Offset? findMarker(
  Raster raster,
  Offset expected, {
  double searchRadius = 0.12,
}) {
  final cx = expected.dx * raster.width;
  final cy = expected.dy * raster.height;
  final radius = searchRadius * math.max(raster.width, raster.height);

  var sumX = 0.0, sumY = 0.0, count = 0;
  final x0 = math.max(0, (cx - radius).floor());
  final x1 = math.min(raster.width - 1, (cx + radius).ceil());
  final y0 = math.max(0, (cy - radius).floor());
  final y1 = math.min(raster.height - 1, (cy + radius).ceil());

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * raster.width + x) * 3;
      final luma =
          (raster.pixels[i] * 77 +
              raster.pixels[i + 1] * 150 +
              raster.pixels[i + 2] * 29) >>
          8;
      // Markers are far darker than printed text.
      if (luma > 25) continue;
      sumX += x;
      sumY += y;
      count++;
    }
  }
  if (count < 20) return null;
  return Offset(sumX / count / raster.width, sumY / count / raster.height);
}
