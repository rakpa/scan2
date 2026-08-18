import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Projective (homography) map from the unit square onto an arbitrary convex
/// quad, using Heckbert's closed form for the square-to-quad case.
///
/// A bilinear blend of the four corners — the obvious thing to write, and what
/// this file used to do — is *not* a perspective correction: it leaves the
/// converging distortion in place and only stretches the sampling grid. The
/// projective divide below is what actually makes a page photographed at an
/// angle come out rectangular with straight text baselines.
@immutable
class Homography {
  const Homography._(
    this.a11,
    this.a21,
    this.a31,
    this.a12,
    this.a22,
    this.a32,
    this.a13,
    this.a23,
  );

  final double a11, a21, a31;
  final double a12, a22, a32;
  final double a13, a23;

  /// Maps (0,0)→[tl], (1,0)→[tr], (1,1)→[br], (0,1)→[bl].
  factory Homography.unitSquareTo(Offset tl, Offset tr, Offset br, Offset bl) {
    final sumX = tl.dx - tr.dx + br.dx - bl.dx;
    final sumY = tl.dy - tr.dy + br.dy - bl.dy;

    // A parallelogram needs no projective terms; the general solve would
    // divide by zero here.
    if (sumX.abs() < 1e-9 && sumY.abs() < 1e-9) {
      return Homography._(
        tr.dx - tl.dx,
        br.dx - tr.dx,
        tl.dx,
        tr.dy - tl.dy,
        br.dy - tr.dy,
        tl.dy,
        0,
        0,
      );
    }

    final dx1 = tr.dx - br.dx;
    final dx2 = bl.dx - br.dx;
    final dy1 = tr.dy - br.dy;
    final dy2 = bl.dy - br.dy;
    final den = dx1 * dy2 - dx2 * dy1;
    if (den.abs() < 1e-12) {
      return Homography._(
        tr.dx - tl.dx,
        br.dx - tr.dx,
        tl.dx,
        tr.dy - tl.dy,
        br.dy - tr.dy,
        tl.dy,
        0,
        0,
      );
    }

    final a13 = (sumX * dy2 - dx2 * sumY) / den;
    final a23 = (dx1 * sumY - sumX * dy1) / den;

    return Homography._(
      tr.dx - tl.dx + a13 * tr.dx,
      bl.dx - tl.dx + a23 * bl.dx,
      tl.dx,
      tr.dy - tl.dy + a13 * tr.dy,
      bl.dy - tl.dy + a23 * bl.dy,
      tl.dy,
      a13,
      a23,
    );
  }

  /// Maps a unit-square point to its position on the source quad.
  Offset map(double u, double v) {
    final w = a13 * u + a23 * v + 1;
    if (w.abs() < 1e-12) return Offset.zero;
    return Offset((a11 * u + a21 * v + a31) / w, (a12 * u + a22 * v + a32) / w);
  }
}

class PerspectiveTransformer {
  /// Perspective-corrects [imageBytes] using the normalized [quad].
  Future<Uint8List> warp({
    required List<int> imageBytes,
    required Quad quad,
    Size? imageSize,
  }) async {
    final bytes = imageBytes is Uint8List
        ? imageBytes
        : Uint8List.fromList(imageBytes);

    if (isFullFrame(quad)) return bytes;

    return compute(
      _warpIsolate,
      _WarpRequest(bytes: bytes, quad: _SerializableQuad.from(quad)),
    );
  }

  /// True when [quad] is (within a small tolerance) the whole image, in which
  /// case warping would only cost a re-encode.
  static bool isFullFrame(Quad quad) {
    const eps = 0.02;
    return (quad.topLeft - Offset.zero).distance < eps &&
        (quad.topRight - const Offset(1, 0)).distance < eps &&
        (quad.bottomRight - const Offset(1, 1)).distance < eps &&
        (quad.bottomLeft - const Offset(0, 1)).distance < eps;
  }
}

class _SerializableQuad {
  const _SerializableQuad(
    this.tlX,
    this.tlY,
    this.trX,
    this.trY,
    this.brX,
    this.brY,
    this.blX,
    this.blY,
  );

  factory _SerializableQuad.from(Quad q) => _SerializableQuad(
    q.topLeft.dx,
    q.topLeft.dy,
    q.topRight.dx,
    q.topRight.dy,
    q.bottomRight.dx,
    q.bottomRight.dy,
    q.bottomLeft.dx,
    q.bottomLeft.dy,
  );

  final double tlX, tlY, trX, trY, brX, brY, blX, blY;

  Quad toQuad() => Quad(
    topLeft: Offset(tlX, tlY),
    topRight: Offset(trX, trY),
    bottomRight: Offset(brX, brY),
    bottomLeft: Offset(blX, blY),
  );
}

class _WarpRequest {
  const _WarpRequest({required this.bytes, required this.quad});

  final Uint8List bytes;
  final _SerializableQuad quad;
}

Uint8List _warpIsolate(_WarpRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;

  final src = Raster.fromImage(img.bakeOrientation(decoded));
  final out = warpRaster(src, request.quad.toQuad());
  if (out == null) return request.bytes;
  return Uint8List.fromList(img.encodeJpg(out.toImage(), quality: 92));
}

/// Largest page we rasterise. Beyond this the extra pixels cost seconds and
/// buy nothing a reader can see.
const _maxWarpPixels = 12 * 1000 * 1000;

/// Perspective-corrects [src] onto an upright rectangle. Returns null when the
/// quad is degenerate.
Raster? warpRaster(Raster src, Quad quad) {
  final w = src.width.toDouble();
  final h = src.height.toDouble();

  final tl = Offset(quad.topLeft.dx * w, quad.topLeft.dy * h);
  final tr = Offset(quad.topRight.dx * w, quad.topRight.dy * h);
  final br = Offset(quad.bottomRight.dx * w, quad.bottomRight.dy * h);
  final bl = Offset(quad.bottomLeft.dx * w, quad.bottomLeft.dy * h);

  // Opposite edges disagree under perspective; the longer one is the edge
  // nearer the lens and carries the most real detail, so size to that.
  final outW = math.max((tr - tl).distance, (br - bl).distance).round();
  final outH = math.max((bl - tl).distance, (br - tr).distance).round();
  if (outW < 8 || outH < 8) return null;

  var targetW = outW;
  var targetH = outH;
  final pixels = targetW * targetH;
  if (pixels > _maxWarpPixels) {
    final scale = math.sqrt(_maxWarpPixels / pixels);
    targetW = math.max(8, (targetW * scale).round());
    targetH = math.max(8, (targetH * scale).round());
  }

  final homography = Homography.unitSquareTo(tl, tr, br, bl);
  final dst = Raster(targetW, targetH);

  final maxX = src.width - 1;
  final maxY = src.height - 1;
  var o = 0;
  for (var y = 0; y < targetH; y++) {
    final v = targetH == 1 ? 0.0 : y / (targetH - 1);
    for (var x = 0; x < targetW; x++) {
      final u = targetW == 1 ? 0.0 : x / (targetW - 1);
      final p = homography.map(u, v);

      // Bilinear sampling — nearest-neighbour visibly stair-steps text at the
      // angles documents are actually photographed at.
      final fx = p.dx.clamp(0.0, maxX.toDouble());
      final fy = p.dy.clamp(0.0, maxY.toDouble());
      final x0 = fx.floor();
      final y0 = fy.floor();
      final x1 = math.min(x0 + 1, maxX);
      final y1 = math.min(y0 + 1, maxY);
      final tx = fx - x0;
      final ty = fy - y0;

      final i00 = (y0 * src.width + x0) * 3;
      final i10 = (y0 * src.width + x1) * 3;
      final i01 = (y1 * src.width + x0) * 3;
      final i11 = (y1 * src.width + x1) * 3;

      for (var c = 0; c < 3; c++) {
        final top = src.pixels[i00 + c] * (1 - tx) + src.pixels[i10 + c] * tx;
        final bottom =
            src.pixels[i01 + c] * (1 - tx) + src.pixels[i11 + c] * tx;
        dst.pixels[o + c] = (top * (1 - ty) + bottom * ty).round().clamp(
          0,
          255,
        );
      }
      o += 3;
    }
  }
  return dst;
}
