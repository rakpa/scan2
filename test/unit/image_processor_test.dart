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

    test('labels match the names shown in the crop screen', () {
      expect(ImageProcessor.labelFor(ScanFilter.original), 'Original');
      expect(ImageProcessor.labelFor(ScanFilter.grayscale), 'Grayscale');
      expect(ImageProcessor.labelFor(ScanFilter.enhance), 'Sharpness');
      expect(ImageProcessor.labelFor(ScanFilter.bw), 'B&W');
      expect(ImageProcessor.labelFor(ScanFilter.magic), 'Auto');
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
      expect(afterGap.abs(), lessThan(40),
          reason: 'lighting gradient should be largely removed');

      // And paper should end up genuinely bright.
      expect(paperAt(out, 117, 45), greaterThan(180));
    });

    test('Sharpness raises local contrast at an edge', () {
      final source = _unevenlyLitPage();
      final out = applyAdjustments(
        source,
        const ScanAdjustments(filter: ScanFilter.enhance),
      );

      int lumaAt(Raster r, int x, int y) => r.pixels[(y * r.width + x) * 3];

      // Step across an ink boundary (paper at x=7, ink at x=4).
      final before =
          (lumaAt(source, 7, 45) - lumaAt(source, 4, 45)).abs();
      final after = (lumaAt(out, 7, 45) - lumaAt(out, 4, 45)).abs();
      expect(after, greaterThan(before),
          reason: 'unsharp mask should widen the ink/paper gap');
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
  });
}
