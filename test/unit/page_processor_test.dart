import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';

import '../support/scene_builder.dart';

void main() {
  // compute() needs a binding to hand work to a background isolate.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String capturePath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scan2_page_processor');
    final scene = buildColorScene(
      corners: const [
        Offset(210, 190),
        Offset(700, 210),
        Offset(780, 1000),
        Offset(130, 970),
      ],
    );
    capturePath = '${temp.path}/capture.jpg';
    File(
      capturePath,
    ).writeAsBytesSync(img.encodeJpg(scene.toImage(), quality: 92));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('PageProcessor', () {
    // These cross an isolate boundary, so they also prove the request and
    // result types are actually sendable — something the analyzer cannot check
    // and that only fails at runtime, on device.
    test('processes a capture into a cropped, enhanced page', () async {
      final result = await const PageProcessor().process(
        imagePath: capturePath,
        adjustments: const ScanAdjustments(filter: ScanFilter.magic),
      );

      expect(result.quad, isNotNull, reason: 'edges should be detected');
      expect(result.adjustments.filter, ScanFilter.magic);

      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);

      // The page occupies well under the full frame, so a correct crop must
      // come out smaller than the capture.
      expect(decoded!.width, lessThan(900));
      expect(decoded.height, lessThan(1200));
      // ...and still be a substantial image, not a sliver.
      expect(decoded.width, greaterThan(400));
      expect(decoded.height, greaterThan(600));
    });

    test('honours an explicit quad instead of detecting', () async {
      const half = Quad(
        topLeft: Offset(0, 0),
        topRight: Offset(0.5, 0),
        bottomRight: Offset(0.5, 1),
        bottomLeft: Offset(0, 1),
      );
      final result = await const PageProcessor().process(
        imagePath: capturePath,
        quad: half,
      );

      expect(result.quad, half);
      final decoded = img.decodeImage(result.bytes)!;
      // Half the width of the 900px capture.
      expect(decoded.width, closeTo(450, 12));
      expect(decoded.height, closeTo(1200, 20));
    });

    test(
      'falls back to the live outline when the still detects nothing',
      () async {
        // A blank frame: nothing for the detector to find.
        final blank = img.Image(width: 600, height: 800);
        img.fill(blank, color: img.ColorRgb8(130, 130, 130));
        final blankPath = '${temp.path}/blank.jpg';
        File(blankPath).writeAsBytesSync(img.encodeJpg(blank, quality: 92));

        const live = Quad(
          topLeft: Offset(0.2, 0.2),
          topRight: Offset(0.8, 0.2),
          bottomRight: Offset(0.8, 0.8),
          bottomLeft: Offset(0.2, 0.8),
        );

        final withoutFallback = await const PageProcessor().process(
          imagePath: blankPath,
        );
        expect(withoutFallback.quad, isNull);

        final withFallback = await const PageProcessor().process(
          imagePath: blankPath,
          fallbackQuad: live,
        );
        expect(
          withFallback.quad,
          live,
          reason: 'the tracked outline should be used when detection fails',
        );

        // And it must actually crop to it: 60% of 600x800.
        final decoded = img.decodeImage(withFallback.bytes)!;
        expect(decoded.width, closeTo(360, 12));
        expect(decoded.height, closeTo(480, 12));
      },
    );

    test('a pre-cropped page is enhanced but not cropped again', () async {
      // What the platform scanner hands back: already perspective-corrected.
      // Detecting edges on it again would crop into the content.
      final result = await const PageProcessor().process(
        imagePath: capturePath,
        detectEdges: false,
        adjustments: const ScanAdjustments(filter: ScanFilter.magic),
      );

      expect(result.quad, isNull, reason: 'no crop should be applied');
      final decoded = img.decodeImage(result.bytes)!;
      expect(decoded.width, 900, reason: 'dimensions must be unchanged');
      expect(decoded.height, 1200);

      // Enhancement still ran.
      final original = img.decodeImage(File(capturePath).readAsBytesSync())!;
      final before = original.getPixel(450, 600);
      final after = decoded.getPixel(450, 600);
      expect(
        (after.r - before.r).abs() + (after.g - before.g).abs(),
        greaterThan(0),
        reason: 'the Auto filter should still have been applied',
      );
    });

    test('render re-derives from source bytes', () async {
      final source = File(capturePath).readAsBytesSync();
      final rendered = await const PageProcessor().render(
        sourceBytes: source,
        quad: const Quad.fullFrame(),
        adjustments: const ScanAdjustments(filter: ScanFilter.grayscale),
      );

      final decoded = img.decodeImage(rendered)!;
      // Full-frame quad: same dimensions, but now neutral grey.
      expect(decoded.width, 900);
      expect(decoded.height, 1200);
      final pixel = decoded.getPixel(450, 600);
      expect(pixel.r, closeTo(pixel.g.toDouble(), 3));
      expect(pixel.g, closeTo(pixel.b.toDouble(), 3));
    });
  });
}
