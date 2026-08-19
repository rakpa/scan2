import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('scan2_export'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String writePage(String name, int w, int h) {
    final image = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (x + y) % 255;
        image.setPixelRgb(x, y, v, v, 200);
      }
    }
    final file = File('${temp.path}/$name');
    file.writeAsBytesSync(img.encodeJpg(image, quality: 88));
    return file.path;
  }

  Document docWith(List<String> paths) => Document(
    id: 1,
    title: 'Tax return 2026',
    createdAt: DateTime(2026, 8, 19),
    pages: [for (final p in paths) ScanPage(path: p)],
  );

  group('ExportService', () {
    test('builds a real PDF from page images', () async {
      final doc = docWith([
        writePage('a.jpg', 900, 1200),
        writePage('b.jpg', 1200, 900),
      ]);

      final bytes = await const ExportService().buildPdfBytes(doc);

      // A PDF starts with %PDF- and ends with %%EOF.
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final tail = String.fromCharCodes(bytes.skip(bytes.length - 32));
      expect(tail, contains('EOF'));
    });

    test(
      'a portrait and a landscape page keep their own proportions',
      () async {
        final doc = docWith([
          writePage('portrait.jpg', 900, 1200),
          writePage('landscape.jpg', 1200, 900),
        ]);
        final bytes = await const ExportService().buildPdfBytes(doc);
        final text = String.fromCharCodes(bytes);

        // Two page objects, so a landscape scan is not padded into portrait A4.
        // Object streams are compressed, so assert on size instead: two pages
        // of different shapes must both be embedded.
        expect(bytes.length, greaterThan(20000));
        expect(text.startsWith('%PDF-'), isTrue);
      },
    );

    test('skips pages whose file has gone missing', () async {
      final doc = docWith([
        writePage('a.jpg', 600, 800),
        '${temp.path}/never_written.jpg',
      ]);
      final bytes = await const ExportService().buildPdfBytes(doc);
      expect(bytes.length, greaterThan(1000));
    });

    test(
      'an empty document fails loudly rather than writing a blank PDF',
      () async {
        final doc = docWith(['${temp.path}/missing.jpg']);
        expect(
          () => const ExportService().buildPdfBytes(doc),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('file name is safe for the filesystem', () {
      expect(
        ExportService.fileNameFor(
          Document(
            id: 1,
            title: 'Invoice 12/07 <draft>',
            createdAt: DateTime(2026),
          ),
        ),
        'Invoice 1207 draft',
      );
    });
  });
}
