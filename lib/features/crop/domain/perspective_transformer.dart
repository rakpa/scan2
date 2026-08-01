import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/features/camera/domain/quad_detector.dart';

class _WarpRequest {
  final Uint8List bytes;
  final double tlX, tlY, trX, trY, brX, brY, blX, blY;

  const _WarpRequest({
    required this.bytes,
    required this.tlX,
    required this.tlY,
    required this.trX,
    required this.trY,
    required this.brX,
    required this.brY,
    required this.blX,
    required this.blY,
  });
}

class PerspectiveTransformer {
  /// Perspective-corrects [imageBytes] using the normalized [quad].
  ///
  /// When the quad is essentially full-frame, returns the original bytes.
  Future<Uint8List> warp({
    required List<int> imageBytes,
    required Quad quad,
    Size? imageSize,
  }) async {
    final bytes =
        imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes);

    if (_isFullFrame(quad)) return bytes;

    return compute(
      _warpIsolate,
      _WarpRequest(
        bytes: bytes,
        tlX: quad.topLeft.dx,
        tlY: quad.topLeft.dy,
        trX: quad.topRight.dx,
        trY: quad.topRight.dy,
        brX: quad.bottomRight.dx,
        brY: quad.bottomRight.dy,
        blX: quad.bottomLeft.dx,
        blY: quad.bottomLeft.dy,
      ),
    );
  }

  bool _isFullFrame(Quad quad) {
    const eps = 0.02;
    return (quad.topLeft - const Offset(0, 0)).distance < eps &&
        (quad.topRight - const Offset(1, 0)).distance < eps &&
        (quad.bottomRight - const Offset(1, 1)).distance < eps &&
        (quad.bottomLeft - const Offset(0, 1)).distance < eps;
  }
}

Uint8List _warpIsolate(_WarpRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;

  final src = img.bakeOrientation(decoded);
  final w = src.width.toDouble();
  final h = src.height.toDouble();

  final tl = Offset(request.tlX * w, request.tlY * h);
  final tr = Offset(request.trX * w, request.trY * h);
  final br = Offset(request.brX * w, request.brY * h);
  final bl = Offset(request.blX * w, request.blY * h);

  final topW = (tr - tl).distance;
  final bottomW = (br - bl).distance;
  final leftH = (bl - tl).distance;
  final rightH = (br - tr).distance;

  final outW = topW > bottomW ? topW.round() : bottomW.round();
  final outH = leftH > rightH ? leftH.round() : rightH.round();
  if (outW < 8 || outH < 8) return request.bytes;

  final dst = img.Image(width: outW, height: outH);
  for (var y = 0; y < outH; y++) {
    final v = outH == 1 ? 0.0 : y / (outH - 1);
    for (var x = 0; x < outW; x++) {
      final u = outW == 1 ? 0.0 : x / (outW - 1);
      final top = Offset.lerp(tl, tr, u)!;
      final bottom = Offset.lerp(bl, br, u)!;
      final sample = Offset.lerp(top, bottom, v)!;
      final px = sample.dx.round().clamp(0, src.width - 1);
      final py = sample.dy.round().clamp(0, src.height - 1);
      dst.setPixel(x, y, src.getPixel(px, py));
    }
  }

  return Uint8List.fromList(img.encodeJpg(dst, quality: 92));
}
