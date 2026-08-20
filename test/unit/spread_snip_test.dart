import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/crop/domain/spread_snip.dart';

import '../support/scene_builder.dart';

Raster twoPageSpread({required bool rightFacing}) {
  const w = 1200;
  const h = 800;
  final raster = Raster(w, h);
  void put(int x, int y, int r, int g, int b) {
    final i = (y * w + x) * 3;
    raster.pixels[i] = r;
    raster.pixels[i + 1] = g;
    raster.pixels[i + 2] = b;
  }

  // Cream pages with a dark holder sitting in the gutter.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x >= 575 && x <= 625) {
        put(x, y, 18, 18, 20);
        continue;
      }
      final onRight = x > 625;
      final facing = onRight == rightFacing;
      final shade = facing ? 1.0 : 0.78;
      put(
        x,
        y,
        (236 * shade).round(),
        (233 * shade).round(),
        (226 * shade).round(),
      );
    }
  }
  return raster;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an open book with a dark gutter snips to the facing page', () {
    final spread = twoPageSpread(rightFacing: true);
    final snip = detectSpreadSnip(spread);
    expect(snip, isNotNull);
    expect(snip!.gutterX, closeTo(0.5, 0.08));
    expect(snip.keepRight, isTrue);

    final leftFacing = detectSpreadSnip(twoPageSpread(rightFacing: false));
    expect(leftFacing, isNotNull);
    expect(leftFacing!.keepRight, isFalse);
  });

  test('a single page is not treated as a spread', () {
    final page = buildColorScene(
      corners: const [
        Offset(0, 0),
        Offset(900, 0),
        Offset(900, 1200),
        Offset(0, 1200),
      ],
      backgroundR: 236,
      backgroundG: 233,
      backgroundB: 226,
    );
    expect(detectSpreadSnip(page), isNull);
  });

  test('processing a two-page snip keeps one page', () async {
    final temp = Directory.systemTemp.createTempSync('scan2_spread');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final path = '${temp.path}/spread.jpg';
    File(path).writeAsBytesSync(
      img.encodeJpg(twoPageSpread(rightFacing: true).toImage(), quality: 92),
    );

    final result = await const PageProcessor().process(
      imagePath: path,
      detectEdges: false,
      adjustments: const ScanAdjustments(filter: ScanFilter.original),
    );
    expect(result.quad, isNotNull);
    final decoded = img.decodeImage(result.bytes)!;
    expect(decoded.width, lessThan(750));
    expect(decoded.height, closeTo(800, 30));
  });
}
