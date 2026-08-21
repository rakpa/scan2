import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/ocr/domain/on_device_ocr.dart';

import '../support/scene_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scan2_import');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('isPdfPath recognises PDFs regardless of case', () {
    expect(isPdfPath('invoice.PDF'), isTrue);
    expect(isPdfPath('/tmp/page.jpg'), isFalse);
  });

  test('file imports keep the full image instead of cropping again', () async {
    final scene = buildColorScene(
      corners: const [
        Offset(210, 190),
        Offset(700, 210),
        Offset(780, 1000),
        Offset(130, 970),
      ],
    );
    final path = '${temp.path}/page.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(scene.toImage(), quality: 92));

    final pages = await prepareImportPages(
      paths: [path],
      filter: ScanFilter.original,
      options: ImportPrepareOptions.files,
    );

    expect(pages, hasLength(1));
    expect(
      pages.first.quad == null ||
          PerspectiveTransformer.isFullFrame(pages.first.quad!),
      isTrue,
      reason: 'imported files must not be sent through a second crop',
    );
  });

  test('photo imports still detect a page so the editor can review it', () async {
    final scene = buildColorScene(
      corners: const [
        Offset(210, 190),
        Offset(700, 210),
        Offset(780, 1000),
        Offset(130, 970),
      ],
    );
    final path = '${temp.path}/photo.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(scene.toImage(), quality: 92));

    final pages = await prepareImportPages(
      paths: [path],
      filter: ScanFilter.magic,
      options: ImportPrepareOptions.photos,
    );

    expect(pages, hasLength(1));
    expect(pages.first.quad, isNotNull);
    expect(
      PerspectiveTransformer.isFullFrame(pages.first.quad!),
      isFalse,
      reason: 'a photo of a page on a desk should still find the paper',
    );
  });

  test('PDF imports rasterize each page before review', () async {
    final pngPath = '${temp.path}/from_pdf.png';
    final raster = img.Image(width: 40, height: 50);
    img.fill(raster, color: img.ColorRgb8(240, 240, 245));
    File(pngPath).writeAsBytesSync(img.encodePng(raster));

    final pages = await prepareImportPages(
      paths: ['${temp.path}/doc.pdf'],
      filter: ScanFilter.original,
      options: ImportPrepareOptions.files,
      rasterizePdf: (path) async => [pngPath],
    );

    expect(pages, hasLength(1));
    expect(pages.first.originalPath, pngPath);
  });

  test('injected OCR engine is used', () async {
    final ocr = OnDeviceOcr(engine: (_) async => 'Invoice 42');
    final text = await ocr.recognize(Uint8List.fromList([1, 2, 3]));
    expect(text, 'Invoice 42');
  });
}
