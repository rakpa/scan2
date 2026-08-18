import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';

import '../support/scene_builder.dart';

/// A page photographed at an angle: the top edge is further away, so it is
/// noticeably narrower than the bottom.
const _perspectiveCorners = [
  Offset(220, 180),
  Offset(690, 205),
  Offset(790, 1010),
  Offset(120, 980),
];

int _luma(Raster r, int x, int y) {
  final i = (y * r.width + x) * 3;
  return (r.pixels[i] * 77 + r.pixels[i + 1] * 150 + r.pixels[i + 2] * 29) >> 8;
}

/// Mean luma over a small patch, to sample past the noise.
double _patchLuma(Raster r, double fx, double fy, {int radius = 6}) {
  final cx = (fx * r.width).round().clamp(radius, r.width - radius - 1);
  final cy = (fy * r.height).round().clamp(radius, r.height - radius - 1);
  var sum = 0;
  var n = 0;
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      sum += _luma(r, x, y);
      n++;
    }
  }
  return sum / n;
}

void main() {
  group('capture pipeline', () {
    late Raster scene;

    setUp(() {
      scene = buildColorScene(corners: _perspectiveCorners);
    });

    test('finds the page in a full-resolution capture', () {
      final quad = detectQuadInRaster(scene);
      expect(quad, isNotNull);

      // Compare against ground truth in normalized space.
      final found = quad!.corners;
      final expected = [
        for (final c in _perspectiveCorners)
          Offset(c.dx / scene.width, c.dy / scene.height),
      ];
      final diagonal = math.sqrt(2);
      var error = 0.0;
      for (var i = 0; i < 4; i++) {
        error += (found[i] - expected[i]).distance;
      }
      error = (error / 4) / diagonal;
      expect(
        error,
        lessThan(0.02),
        reason: 'corner error ${(error * 100).toStringAsFixed(2)}%',
      );
    });

    test('warping removes the perspective taper', () {
      final quad = detectQuadInRaster(scene)!;
      final warped = warpRaster(scene, quad);
      expect(warped, isNotNull);

      // The whole output should be page, not desk. Sample just inside each
      // corner: if the warp were misaligned, background would bleed in.
      for (final point in [
        const Offset(0.04, 0.04),
        const Offset(0.96, 0.04),
        const Offset(0.96, 0.96),
        const Offset(0.04, 0.96),
      ]) {
        expect(
          _patchLuma(warped!, point.dx, point.dy),
          greaterThan(120),
          reason: 'desk visible at $point — the crop is off the page',
        );
      }
    });

    test('warped output has the page aspect ratio, not the frame ratio', () {
      final quad = detectQuadInRaster(scene)!;
      final warped = warpRaster(scene, quad)!;

      // Ground-truth page: ~570 wide (bottom edge) by ~810 tall.
      const expectedAspect = 670 / 810;
      final actual = warped.width / warped.height;
      expect(actual, closeTo(expectedAspect, 0.18));
    });

    test('perspective correction recovers page coordinates', () {
      // Registration marks printed at known positions on the page. After
      // correction each must sit at that same fraction of the output image —
      // that is what "perspective corrected" means, and it is the property a
      // bilinear blend of the four corners does not have: it maps the border
      // correctly but distorts everything inside it.
      const marks = [
        Offset(0.25, 0.25),
        Offset(0.75, 0.25),
        Offset(0.50, 0.50),
        Offset(0.25, 0.75),
        Offset(0.75, 0.75),
      ];
      final marked = buildColorScene(
        corners: _perspectiveCorners,
        markers: marks,
        textLines: 0,
      );

      final quad = detectQuadInRaster(marked)!;
      final warped = warpRaster(marked, quad)!;

      for (final mark in marks) {
        final found = findMarker(warped, mark);
        expect(found, isNotNull, reason: 'no registration mark near $mark');
        final error = (found! - mark).distance;
        expect(
          error,
          lessThan(0.02),
          reason:
              'mark $mark landed at $found '
              '(${(error * 100).toStringAsFixed(1)}% off)',
        );
      }
    });

    test('Auto enhancement flattens the lighting and whitens the paper', () {
      final quad = detectQuadInRaster(scene)!;
      final warped = warpRaster(scene, quad)!;
      final enhanced = applyAdjustments(
        warped,
        const ScanAdjustments(filter: ScanFilter.magic),
      );

      // Paper margins, left versus right, where the lighting gradient was.
      final beforeGap =
          (_patchLuma(warped, 0.04, 0.5) - _patchLuma(warped, 0.96, 0.5)).abs();
      final afterGap =
          (_patchLuma(enhanced, 0.04, 0.5) - _patchLuma(enhanced, 0.96, 0.5))
              .abs();

      expect(
        afterGap,
        lessThan(beforeGap),
        reason: 'shading across the page should be reduced',
      );
      expect(
        _patchLuma(enhanced, 0.96, 0.5),
        greaterThan(200),
        reason: 'the dim side of the page should end up white',
      );
    });

    test('full-frame quads skip the warp entirely', () {
      expect(
        PerspectiveTransformer.isFullFrame(const Quad.fullFrame()),
        isTrue,
      );
      expect(
        PerspectiveTransformer.isFullFrame(const Quad.centered()),
        isFalse,
      );
    });
  });
}
