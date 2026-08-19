import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'package:scan2/features/camera/domain/document_quad_detector.dart';

/// Four-corner document boundary in normalized 0–1 image coordinates.
class Quad {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Default frame inset from the preview edges.
  const Quad.centered()
    : topLeft = const Offset(0.12, 0.18),
      topRight = const Offset(0.88, 0.18),
      bottomRight = const Offset(0.88, 0.82),
      bottomLeft = const Offset(0.12, 0.82);

  /// Full-bleed rectangle — used when edges were already applied by the
  /// native scanner (VisionKit / ML Kit).
  const Quad.fullFrame()
    : topLeft = Offset.zero,
      topRight = const Offset(1, 0),
      bottomRight = const Offset(1, 1),
      bottomLeft = const Offset(0, 1);

  factory Quad.fromCorners(List<Offset> corners) {
    assert(corners.length == 4);
    final ordered = DocumentQuadDetector.orderCorners(corners);
    return Quad(
      topLeft: ordered[0],
      topRight: ordered[1],
      bottomRight: ordered[2],
      bottomLeft: ordered[3],
    );
  }

  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  Quad copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return Quad(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  Quad withCorner(int index, Offset value) {
    switch (index) {
      case 0:
        return copyWith(topLeft: value);
      case 1:
        return copyWith(topRight: value);
      case 2:
        return copyWith(bottomRight: value);
      case 3:
        return copyWith(bottomLeft: value);
      default:
        return this;
    }
  }

  /// Pulls every corner toward the centre by [fraction] of the quad's size.
  ///
  /// Detected borders land within a pixel or two of the paper edge, which is
  /// accurate but leaves a thin dark rim of desk around the cropped page.
  /// Cropping marginally inside the detected border trims that rim; the
  /// fraction of a millimetre of paper it costs is invisible.
  Quad shrink(double fraction) {
    if (fraction <= 0) return this;
    final centre = Offset(
      (topLeft.dx + topRight.dx + bottomRight.dx + bottomLeft.dx) / 4,
      (topLeft.dy + topRight.dy + bottomRight.dy + bottomLeft.dy) / 4,
    );
    Offset pull(Offset corner) =>
        Offset.lerp(corner, centre, fraction) ?? corner;
    return Quad(
      topLeft: pull(topLeft),
      topRight: pull(topRight),
      bottomRight: pull(bottomRight),
      bottomLeft: pull(bottomLeft),
    );
  }

  /// Fraction of the frame this quad covers (shoelace over normalized
  /// coordinates, so the result is already a ratio).
  double get areaRatio {
    final pts = corners;
    var area = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return area.abs() / 2;
  }

  Quad lerp(Quad other, double t) {
    return Quad(
      topLeft: Offset.lerp(topLeft, other.topLeft, t)!,
      topRight: Offset.lerp(topRight, other.topRight, t)!,
      bottomRight: Offset.lerp(bottomRight, other.bottomRight, t)!,
      bottomLeft: Offset.lerp(bottomLeft, other.bottomLeft, t)!,
    );
  }

  double averageCornerDistance(Quad other) {
    final a = corners;
    final b = other.corners;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      sum += (a[i] - b[i]).distance;
    }
    return sum / 4;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Quad &&
        other.topLeft == topLeft &&
        other.topRight == topRight &&
        other.bottomRight == bottomRight &&
        other.bottomLeft == bottomLeft;
  }

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

/// Live / still-image document edge detector.
class QuadDetector {
  const QuadDetector();

  static const _detector = DocumentQuadDetector();
  static const _analysisWidth = 240;

  /// Detects document corners from a still image file.
  Future<Quad> detectQuadFromPath(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const Quad.centered();

    final gray = img.grayscale(decoded);
    final targetW = _analysisWidth;
    final targetH = (targetW * gray.height / gray.width).round().clamp(48, 360);
    final resized = img.copyResize(gray, width: targetW, height: targetH);

    final lum = Uint8List(targetW * targetH);
    for (var y = 0; y < targetH; y++) {
      for (var x = 0; x < targetW; x++) {
        lum[y * targetW + x] = resized.getPixel(x, y).r.toInt();
      }
    }

    final detection = _detector.detect(lum, targetW, targetH);
    if (detection == null) return const Quad.centered();
    return Quad.fromCorners(detection.corners);
  }

  /// Detects from a downscaled grayscale luminance grid (live preview path).
  QuadDetection? detectFromLuminance(Uint8List lum, int width, int height) {
    return _detector.detect(lum, width, height);
  }
}
