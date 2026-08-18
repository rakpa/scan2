import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/document_quad_detector.dart';

import '../support/scene_builder.dart';

/// Accuracy benchmark for the live edge detector.
///
/// Detection quality is the feature; asserting only that "something was
/// found" is how a detector that locks onto printed text instead of the page
/// border passes its tests. Every case below therefore checks the corner
/// error against a known ground truth.
typedef DetectionCase = ({
  String name,
  List<Offset> corners,
  double texture,
  int background,
  double falloff,
});

void main() {
  const detector = DocumentQuadDetector();

  /// Mean corner error must stay under this fraction of the image diagonal.
  /// At 1.5% a quad is visually on the page border; the failures this suite
  /// was written against sat at 6–16%.
  const tolerance = 0.015;

  const cases = <DetectionCase>[
    (
      name: 'straight-on, centered',
      texture: 0,
      background: 110,
      falloff: 0.18,
      corners: [
        Offset(38, 26),
        Offset(202, 26),
        Offset(202, 154),
        Offset(38, 154),
      ],
    ),
    (
      name: 'slight tilt',
      texture: 0,
      background: 110,
      falloff: 0.18,
      corners: [
        Offset(40, 30),
        Offset(200, 20),
        Offset(206, 150),
        Offset(44, 160),
      ],
    ),
    (
      name: 'perspective (leaning back)',
      texture: 0,
      background: 110,
      falloff: 0.2,
      corners: [
        Offset(58, 22),
        Offset(186, 30),
        Offset(210, 158),
        Offset(32, 150),
      ],
    ),
    (
      name: 'page fills the frame',
      texture: 0,
      background: 110,
      falloff: 0.18,
      corners: [
        Offset(12, 10),
        Offset(228, 12),
        Offset(230, 170),
        Offset(10, 168),
      ],
    ),
    (
      name: 'textured desk',
      texture: 9,
      background: 120,
      falloff: 0.18,
      corners: [
        Offset(40, 28),
        Offset(200, 26),
        Offset(202, 152),
        Offset(38, 155),
      ],
    ),
    (
      name: 'light desk, modest contrast',
      texture: 0,
      background: 195,
      falloff: 0.10,
      corners: [
        Offset(42, 30),
        Offset(198, 28),
        Offset(200, 150),
        Offset(40, 152),
      ],
    ),
    (
      name: 'very low contrast',
      texture: 0,
      background: 185,
      falloff: 0.15,
      corners: [
        Offset(42, 30),
        Offset(198, 28),
        Offset(200, 150),
        Offset(40, 152),
      ],
    ),
    (
      name: 'dense body text',
      texture: 0,
      background: 115,
      falloff: 0.18,
      corners: [
        Offset(36, 24),
        Offset(204, 26),
        Offset(206, 156),
        Offset(34, 154),
      ],
    ),
    (
      name: 'strong shadow falloff',
      texture: 0,
      background: 105,
      falloff: 0.45,
      corners: [
        Offset(44, 26),
        Offset(196, 30),
        Offset(198, 154),
        Offset(42, 150),
      ],
    ),
    (
      name: 'rotated ~12 degrees',
      texture: 0,
      background: 110,
      falloff: 0.18,
      corners: [
        Offset(58, 20),
        Offset(210, 52),
        Offset(184, 162),
        Offset(32, 130),
      ],
    ),
    (
      name: 'small page in frame',
      texture: 0,
      background: 110,
      falloff: 0.18,
      corners: [
        Offset(80, 60),
        Offset(165, 58),
        Offset(167, 125),
        Offset(78, 127),
      ],
    ),
    (
      name: 'dark desk, bright page',
      texture: 4,
      background: 55,
      falloff: 0.2,
      corners: [
        Offset(40, 28),
        Offset(200, 30),
        Offset(203, 153),
        Offset(37, 151),
      ],
    ),
  ];

  group('DocumentQuadDetector accuracy', () {
    for (final testCase in cases) {
      test('locates the page: ${testCase.name}', () {
        final scene = buildScene(
          corners: testCase.corners,
          backgroundTexture: testCase.texture,
          backgroundBrightness: testCase.background,
          lightingFalloff: testCase.falloff,
        );

        final result = detector.detect(scene.luma, scene.width, scene.height);
        expect(result, isNotNull, reason: 'no document found');

        final error = cornerError(
          result!.corners,
          scene.corners,
          scene.width,
          scene.height,
        );
        expect(
          error,
          lessThan(tolerance),
          reason:
              'corner error ${(error * 100).toStringAsFixed(2)}% '
              'exceeds ${(tolerance * 100).toStringAsFixed(1)}%',
        );
        expect(result.confidence, greaterThan(0.5));
      });
    }

    test('does not claim high confidence when the page runs off frame', () {
      // No true top edge exists here, so the detector can only guess at it.
      // What matters is that it does not report the certainty that would let
      // auto-capture fire on a truncated page.
      final scene = buildScene(
        corners: const [
          Offset(30, -14),
          Offset(205, -8),
          Offset(210, 140),
          Offset(26, 146),
        ],
        backgroundTexture: 3,
        backgroundBrightness: 100,
        lightingFalloff: 0.2,
      );

      final result = detector.detect(scene.luma, scene.width, scene.height);
      if (result != null) {
        expect(result.confidence, lessThan(0.85));
      }
    });

    test('reports nothing on a blank frame', () {
      final scene = buildScene(
        corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        backgroundBrightness: 128,
        noise: 1,
        text: false,
        lightingFalloff: 0,
      );
      expect(detector.detect(scene.luma, scene.width, scene.height), isNull);
    });

    test('stays fast enough to run on every preview frame', () {
      final scene = buildScene(corners: cases.first.corners);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        detector.detect(scene.luma, scene.width, scene.height);
      }
      stopwatch.stop();
      final perFrame = stopwatch.elapsedMicroseconds / 20 / 1000;
      expect(perFrame, lessThan(40), reason: '${perFrame}ms per frame');
    });
  });
}
