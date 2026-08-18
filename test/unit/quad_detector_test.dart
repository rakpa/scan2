import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/document_quad_detector.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

void main() {
  group('Quad', () {
    test('centered has inset corners', () {
      const q = Quad.centered();
      expect(q.topLeft.dx, lessThan(0.2));
      expect(q.bottomRight.dx, greaterThan(0.8));
    });

    test('fullFrame covers the entire image', () {
      const q = Quad.fullFrame();
      expect(q.topLeft, Offset.zero);
      expect(q.topRight, const Offset(1, 0));
      expect(q.bottomRight, const Offset(1, 1));
      expect(q.bottomLeft, const Offset(0, 1));
    });

    test('lerp moves corners', () {
      const a = Quad.centered();
      final b = a.copyWith(topLeft: const Offset(0.2, 0.2));
      final mid = a.lerp(b, 0.5);
      expect(mid.topLeft.dx, closeTo(0.16, 0.001));
    });
  });

  group('DocumentQuadDetector', () {
    test('finds a bright rectangle on a dark background', () {
      const w = 80;
      const h = 100;
      final lum = Uint8List(w * h);

      // Dark background
      for (var i = 0; i < lum.length; i++) {
        lum[i] = 20;
      }
      // Bright document rectangle
      for (var y = 20; y < 80; y++) {
        for (var x = 15; x < 65; x++) {
          lum[y * w + x] = 220;
        }
      }

      final result = const DocumentQuadDetector().detect(lum, w, h);
      expect(result, isNotNull);
      expect(result!.corners.length, 4);
      expect(result.confidence, greaterThan(0.2));

      // Corners should roughly sit near the rectangle.
      final xs = result.corners.map((c) => c.dx).toList()..sort();
      final ys = result.corners.map((c) => c.dy).toList()..sort();
      expect(xs.first, lessThan(0.35));
      expect(xs.last, greaterThan(0.65));
      expect(ys.first, lessThan(0.35));
      expect(ys.last, greaterThan(0.65));
    });

    test('returns null on uniform noise-free image', () {
      const w = 64;
      const h = 64;
      final lum = Uint8List(w * h);
      for (var i = 0; i < lum.length; i++) {
        lum[i] = 128;
      }
      final result = const DocumentQuadDetector().detect(lum, w, h);
      expect(result, isNull);
    });
  });
}
