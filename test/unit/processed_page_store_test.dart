import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/library/data/document_storage.dart';
import 'package:scan2/features/library/data/document_store.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('scan2_processed');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  DocumentStore newStore() =>
      DocumentStore(storage: DocumentStorage(overrideRoot: tempRoot));

  /// Stands in for a camera capture on disk.
  String capture(String name, int fill) {
    final file = File(p.join(tempRoot.path, name));
    file.writeAsBytesSync(List<int>.filled(128, fill));
    return file.path;
  }

  ProcessedPage processed(String originalPath, int fill) => ProcessedPage(
    originalPath: originalPath,
    bytes: Uint8List.fromList(List<int>.filled(64, fill)),
    quad: const Quad(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.12),
      bottomRight: Offset(0.88, 0.9),
      bottomLeft: Offset(0.12, 0.88),
    ),
    adjustments: const ScanAdjustments(
      filter: ScanFilter.magic,
      brightness: 0.2,
    ),
  );

  test('a batch is saved as one document with originals kept', () async {
    final store = newStore();
    final doc = await store.createProcessedDocument(
      pages: [
        processed(capture('a.jpg', 1), 200),
        processed(capture('b.jpg', 2), 201),
      ],
    );

    expect(doc.pageCount, 2, reason: 'a batch is one document, not two');

    for (final page in doc.pages) {
      expect(File(page.path).existsSync(), isTrue);
      expect(page.originalPath, isNotNull);
      expect(
        File(page.originalPath!).existsSync(),
        isTrue,
        reason: 'the untouched capture must be kept for re-editing',
      );

      // The page holds the processed bytes; the original holds the capture.
      expect(File(page.path).lengthSync(), 64);
      expect(File(page.originalPath!).lengthSync(), 128);
      expect(page.canReedit, isTrue);
    }
  });

  test('crop and filter settings survive a restart', () async {
    final store = newStore();
    await store.createProcessedDocument(
      pages: [processed(capture('a.jpg', 1), 200)],
    );

    final reopened = (await newStore().getAllDocuments()).single;
    final page = reopened.pages.single;

    expect(page.adjustments.filter, ScanFilter.magic);
    expect(page.adjustments.brightness, closeTo(0.2, 1e-9));
    expect(page.quad, isNotNull);
    expect(
      page.quad!.topRight.dy,
      closeTo(0.12, 1e-9),
      reason: 'reopening the editor must restore the exact crop',
    );
    expect(page.originalPath, isNotNull);
    expect(File(page.originalPath!).existsSync(), isTrue);
  });

  test('appending pages does not overwrite earlier ones', () async {
    final store = newStore();
    final doc = await store.createProcessedDocument(
      pages: [processed(capture('a.jpg', 1), 200)],
    );
    final firstPagePath = doc.pages.single.path;

    final updated = await store.addProcessedPages(doc.id, [
      processed(capture('b.jpg', 2), 201),
    ]);

    expect(updated!.pageCount, 2);
    expect(updated.pages.map((p) => p.path).toSet(), hasLength(2));
    expect(updated.pages.first.path, firstPagePath);
    for (final page in updated.pages) {
      expect(File(page.path).existsSync(), isTrue);
      expect(File(page.originalPath!).existsSync(), isTrue);
    }
  });

  test('re-saving a page updates its bytes and its stored settings', () async {
    final store = newStore();
    final doc = await store.createProcessedDocument(
      pages: [processed(capture('a.jpg', 1), 200)],
    );
    final page = doc.pages.single;

    await store.replacePageBytes(
      documentId: doc.id,
      pagePath: page.path,
      bytes: Uint8List.fromList(List<int>.filled(99, 7)),
      quad: const Quad.fullFrame(),
      adjustments: const ScanAdjustments(filter: ScanFilter.bw),
    );

    final reopened = (await newStore().getAllDocuments()).single.pages.single;
    expect(File(reopened.path).lengthSync(), 99);
    expect(reopened.adjustments.filter, ScanFilter.bw);
    expect(reopened.quad!.topLeft, Offset.zero);
    expect(
      File(reopened.originalPath!).lengthSync(),
      128,
      reason: 'the original must not be touched by a re-save',
    );
  });

  test('deleting a page removes its original too', () async {
    final store = newStore();
    final doc = await store.createProcessedDocument(
      pages: [
        processed(capture('a.jpg', 1), 200),
        processed(capture('b.jpg', 2), 201),
      ],
    );
    final removed = doc.pages.first;

    await store.deletePage(documentId: doc.id, pagePath: removed.path);

    expect(File(removed.path).existsSync(), isFalse);
    expect(
      File(removed.originalPath!).existsSync(),
      isFalse,
      reason: 'an orphaned original would leak disk space',
    );
    expect((await store.getAllDocuments()).single.pageCount, 1);
  });

  test('reordering pages persists', () async {
    final store = newStore();
    final doc = await store.createProcessedDocument(
      pages: [
        processed(capture('a.jpg', 1), 200),
        processed(capture('b.jpg', 2), 201),
        processed(capture('c.jpg', 3), 202),
      ],
    );
    final originalOrder = doc.pages.map((p) => p.path).toList();

    await store.reorderPages(doc.id, 0, 2);

    final reopened = (await newStore().getAllDocuments()).single;
    expect(reopened.pages.map((p) => p.path).toList(), [
      originalOrder[1],
      originalOrder[2],
      originalOrder[0],
    ]);
  });

  test(
    'recovery from a corrupt manifest pairs pages with their originals',
    () async {
      final store = newStore();
      await store.createProcessedDocument(
        pages: [processed(capture('a.jpg', 1), 200)],
      );

      File(
        p.join(tempRoot.path, 'documents', 'library.json'),
      ).writeAsStringSync('not json at all');

      final recovered = (await newStore().getAllDocuments()).single;
      expect(
        recovered.pageCount,
        1,
        reason: 'the .orig file must not be counted as a second page',
      );
      expect(recovered.pages.single.originalPath, isNotNull);
    },
  );
}
