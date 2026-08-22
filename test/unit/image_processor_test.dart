import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';

Uint8List _solidJpeg({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// A page lit unevenly from left to right, with dark "ink" strokes on it.
/// This is the case a global threshold gets wrong.
Raster _unevenlyLitPage({int width = 120, int height = 90}) {
  final raster = Raster(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Paper falls from bright on the left to dim on the right.
      var v = (235 - (x / width) * 130).round();
      // Ink: every 10th column is much darker than its surroundings.
      if (x % 10 == 3 || x % 10 == 4) {
        v = (v * 0.45).round();
      }
      final i = (y * width + x) * 3;
      raster.pixels[i] = v;
      raster.pixels[i + 1] = v;
      raster.pixels[i + 2] = v;
    }
  }
  return raster;
}

/// Warm cream notebook paper — the capture that used to cook orange under
/// Auto Enhance because per-channel levels clipped red and left blue behind.
Raster _creamNotebookPage({int width = 96, int height = 72}) {
  final raster = Raster(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final shade = 1.0 - (x / width) * 0.32;
      final ink = x % 12 == 5 || x % 12 == 6;
      final i = (y * width + x) * 3;
      raster.pixels[i] = (ink ? 46 : (214 * shade).round()).clamp(0, 255);
      raster.pixels[i + 1] = (ink ? 40 : (188 * shade).round()).clamp(0, 255);
      raster.pixels[i + 2] = (ink ? 34 : (142 * shade).round()).clamp(0, 255);
    }
  }
  return raster;
}

void _expectNeutralPaper(Raster page, int x, int y, {String? reason}) {
  final i = (y * page.width + x) * 3;
  final r = page.pixels[i];
  final g = page.pixels[i + 1];
  final b = page.pixels[i + 2];
  expect(r - b, lessThan(28), reason: reason);
  expect((r - g).abs(), lessThan(18), reason: reason);
  expect(r, greaterThan(200), reason: reason);
  expect(b, greaterThan(190), reason: reason);
}

void main() {
  final processor = ImageProcessor();

  group('ImageProcessor', () {
    test('original with neutral tone returns the bytes untouched', () async {
      final input = _solidJpeg(width: 32, height: 32, r: 120, g: 130, b: 140);
      final out = await processor.applyFilter(
        imageBytes: input,
        filter: ScanFilter.original,
      );
      expect(out, same(input));
    });

    test('grayscale neutralises colour', () async {
      final input = _solidJpeg(width: 32, height: 32, r: 220, g: 30, b: 30);
      final out = await processor.applyFilter(
        imageBytes: input,
        filter: ScanFilter.grayscale,
      );
      final pixel = img.decodeImage(out)!.getPixel(16, 16);
      expect(pixel.r, closeTo(pixel.g, 2));
      expect(pixel.g, closeTo(pixel.b, 2));
      // Rec. 601 luma of (220,30,30) is ~86, not the 220 a naive max() gives.
      expect(pixel.r, closeTo(86, 8));
    });

    test('B&W encodes as a compact JPEG, not a huge PNG', () async {
      final input = _solidJpeg(width: 32, height: 32, r: 40, g: 40, b: 40);
      final out = await processor.applyFilter(
        imageBytes: input,
        filter: ScanFilter.bw,
      );
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
    });

    test('labels match the names shown in the crop screen', () {
      expect(ImageProcessor.labelFor(ScanFilter.original), 'Original');
      expect(ImageProcessor.labelFor(ScanFilter.grayscale), 'Grayscale');
      expect(ImageProcessor.labelFor(ScanFilter.enhance), 'Magic Color');
      expect(ImageProcessor.labelFor(ScanFilter.bw), 'B&W');
      expect(ImageProcessor.labelFor(ScanFilter.magic), 'Auto Enhance');
    });
  });

  group('filter kernels', () {
    test('B&W keeps ink black and paper white despite uneven lighting', () {
      final out = applyAdjustments(
        _unevenlyLitPage(),
        const ScanAdjustments(filter: ScanFilter.bw),
      );

      // Every pixel must be fully black or fully white.
      for (var i = 0; i < out.pixels.length; i += 3) {
        expect(out.pixels[i], anyOf(0, 255));
      }

      int lumaAt(int x, int y) => out.pixels[(y * out.width + x) * 3];

      // Ink stays black and paper stays white on BOTH the brightly lit left
      // edge and the dim right edge. A single global cutoff cannot do this:
      // paper on the right is darker than ink on the left.
      expect(lumaAt(3, 45), 0, reason: 'ink on the bright side');
      expect(lumaAt(7, 45), 255, reason: 'paper on the bright side');
      expect(lumaAt(113, 45), 0, reason: 'ink on the dim side');
      expect(lumaAt(117, 45), 255, reason: 'paper on the dim side');
    });

    test('Auto flattens uneven lighting across the page', () {
      final source = _unevenlyLitPage();
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.magic),
      );

      int paperAt(Raster r, int x, int y) => r.pixels[(y * r.width + x) * 3];

      // Before: paper on the right is far darker than paper on the left.
      final beforeGap = paperAt(source, 7, 45) - paperAt(source, 117, 45);
      final afterGap = paperAt(out, 7, 45) - paperAt(out, 117, 45);
      expect(beforeGap, greaterThan(90));
      expect(
        afterGap.abs(),
        lessThan(40),
        reason: 'lighting gradient should be largely removed',
      );

      // And paper should end up genuinely bright.
      expect(paperAt(out, 117, 45), greaterThan(180));
    });

    test('Magic Color raises local contrast at an edge', () {
      final source = _unevenlyLitPage();
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.enhance),
      );

      int lumaAt(Raster r, int x, int y) => r.pixels[(y * r.width + x) * 3];

      // Step across an ink boundary (paper at x=7, ink at x=4).
      final before = (lumaAt(source, 7, 45) - lumaAt(source, 4, 45)).abs();
      final after = (lumaAt(out, 7, 45) - lumaAt(out, 4, 45)).abs();
      expect(
        after,
        greaterThan(before),
        reason: 'unsharp mask should widen the ink/paper gap',
      );
    });

    test('Auto Enhance does not turn cream paper orange', () {
      final source = _creamNotebookPage();
      final i = (36 * source.width + 8) * 3;
      expect(
        source.pixels[i] - source.pixels[i + 2],
        greaterThan(50),
        reason: 'fixture must start as warm cream, not already-white paper',
      );

      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.magic),
      );
      _expectNeutralPaper(
        out,
        8,
        36,
        reason: 'bright side should be near-white, not yellow',
      );
      _expectNeutralPaper(
        out,
        88,
        36,
        reason: 'dim side should be near-white after lighting flatten',
      );
    });

    test('Magic Color keeps cream paper from going orange', () {
      final out = applyAdjustments(
        _creamNotebookPage(),
        const ScanAdjustments(filter: ScanFilter.enhance),
      );
      final i = (36 * out.width + 8) * 3;
      expect(
        out.pixels[i] - out.pixels[i + 2],
        lessThan(45),
        reason: 'partial white-balance should still kill the burnt look',
      );
      expect(out.pixels[i], greaterThan(190));
    });

    test('B&W keeps faint planner ruling instead of bleaching it', () {
      final page = Raster(80, 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 80; x++) {
          final ruling = y % 8 == 3;
          final v = ruling ? 178 : 210;
          final i = (y * 80 + x) * 3;
          page.pixels[i] = v;
          page.pixels[i + 1] = v;
          page.pixels[i + 2] = v;
        }
      }
      final out = applyAdjustments(
        page,
        const ScanAdjustments(filter: ScanFilter.bw),
      );
      expect(out.pixels[(3 * 80 + 40) * 3], 0, reason: 'faint ruling is ink');
      expect(out.pixels[(6 * 80 + 40) * 3], 255, reason: 'paper stays white');
    });

    test('Original leaves pixels untouched', () {
      final source = _unevenlyLitPage();
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.original),
      );
      expect(out.pixels, source.pixels);
    });

    test('brightness and contrast move tone in the expected direction', () {
      final source = _unevenlyLitPage();
      int mid(Raster r) => r.pixels[((45 * r.width) + 60) * 3];

      final brighter = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.original, brightness: 0.5),
      );
      final darker = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.original, brightness: -0.5),
      );
      expect(mid(brighter), greaterThan(mid(source)));
      expect(mid(darker), lessThan(mid(source)));
    });

    test('saturation toward -1 collapses colour toward luma', () {
      final source = Raster(8, 8);
      for (var i = 0; i < source.pixels.length; i += 3) {
        source.pixels[i] = 220;
        source.pixels[i + 1] = 30;
        source.pixels[i + 2] = 40;
      }
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.original, saturation: -1),
      );
      expect(out.pixels[0], closeTo(out.pixels[1], 2));
      expect(out.pixels[1], closeTo(out.pixels[2], 2));
    });

    test('positive sharpness widens an ink edge on the original', () {
      final source = _unevenlyLitPage();
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.original, sharpness: 1),
      );
      int lumaAt(Raster r, int x, int y) => r.pixels[(y * r.width + x) * 3];
      final before = (lumaAt(source, 7, 45) - lumaAt(source, 4, 45)).abs();
      final after = (lumaAt(out, 7, 45) - lumaAt(out, 4, 45)).abs();
      expect(after, greaterThan(before));
    });
  });
}
