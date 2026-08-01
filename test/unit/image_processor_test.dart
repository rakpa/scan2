import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

void main() {
  final processor = ImageProcessor();

  test('original filter returns identical bytes when tone is neutral', () async {
    final input = _solidJpeg(width: 32, height: 32, r: 120, g: 130, b: 140);
    final out = await processor.applyFilter(
      imageBytes: input,
      filter: ScanFilter.original,
    );
    expect(out, input);
  });

  test('bw filter produces near black/white pixels', () async {
    final input = _solidJpeg(width: 48, height: 48, r: 200, g: 200, b: 200);
    final out = await processor.applyFilter(
      imageBytes: input,
      filter: ScanFilter.bw,
    );
    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    final p = decoded!.getPixel(10, 10);
    expect(p.r, anyOf(0, 255));
    expect(p.r, p.g);
    expect(p.g, p.b);
  });

  test('sharp filter returns a different encoded image', () async {
    // Gradient so sharpen has edges to work with.
    final image = img.Image(width: 64, height: 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final v = ((x + y) * 2).clamp(0, 255);
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    final input = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final out = await processor.applyFilter(
      imageBytes: input,
      filter: ScanFilter.enhance,
    );
    expect(out, isNot(equals(input)));
    expect(img.decodeImage(out), isNotNull);
  });

  test('labels include Original, B&W, and Sharp', () {
    expect(ImageProcessor.labelFor(ScanFilter.original), 'Original');
    expect(ImageProcessor.labelFor(ScanFilter.bw), 'B&W');
    expect(ImageProcessor.labelFor(ScanFilter.enhance), 'Sharp');
  });
}
