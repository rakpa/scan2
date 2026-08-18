import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scan2/features/library/data/document_storage.dart';
import 'package:scan2/features/library/data/document_store.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('scan2_store_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// A fresh store over the same directory — i.e. the next app launch.
  DocumentStore newStore() =>
      DocumentStore(storage: DocumentStorage(overrideRoot: tempRoot));

  String makeSourceImage(String name) {
    final file = File(p.join(tempRoot.path, name));
    file.writeAsBytesSync(List<int>.filled(64, 7));
    return file.path;
  }

  test('documents survive a restart', () async {
    final first = newStore();
    final doc = await first.createDocumentFromScans([
      makeSourceImage('a.jpg'),
      makeSourceImage('b.jpg'),
    ], title: 'Tax return');
    expect(doc.pageCount, 2);

    // Reopen from disk, as the app would on next launch.
    final reopened = await newStore().getAllDocuments();
    expect(reopened, hasLength(1));
    expect(reopened.single.title, 'Tax return');
    expect(reopened.single.pageCount, 2);
    for (final page in reopened.single.pagePaths) {
      expect(File(page).existsSync(), isTrue, reason: '$page missing');
    }
  });

  test(
    'page paths are stored relative, so a moved container still resolves',
    () async {
      final store = newStore();
      await store.createDocumentFromScans([makeSourceImage('a.jpg')]);

      final manifest = File(
        p.join(tempRoot.path, 'documents', 'library.json'),
      ).readAsStringSync();
      // iOS reassigns the container path between installs; an absolute path
      // baked into the manifest would dangle after the next build.
      expect(manifest, isNot(contains(tempRoot.path)));
      expect(manifest, contains('page_000.jpg'));
    },
  );

  test('adding pages appends without overwriting existing ones', () async {
    final store = newStore();
    final doc = await store.createDocumentFromScans([makeSourceImage('a.jpg')]);
    final updated = await store.addPages(doc.id, [makeSourceImage('b.jpg')]);

    expect(updated!.pageCount, 2);
    expect(updated.pagePaths.toSet(), hasLength(2));
    expect(File(updated.pagePaths[0]).existsSync(), isTrue);
    expect(File(updated.pagePaths[1]).existsSync(), isTrue);
  });

  test(
    'deleting a document removes its files and its manifest entry',
    () async {
      final store = newStore();
      final doc = await store.createDocumentFromScans([
        makeSourceImage('a.jpg'),
      ]);
      final pagePath = doc.pagePaths.first;

      await store.deleteDocument(doc.id);
      expect(await store.getAllDocuments(), isEmpty);
      expect(File(pagePath).existsSync(), isFalse);
      expect((await newStore().getAllDocuments()), isEmpty);
    },
  );

  test('deleting the last page deletes the document', () async {
    final store = newStore();
    final doc = await store.createDocumentFromScans([makeSourceImage('a.jpg')]);
    await store.deletePage(documentId: doc.id, pagePath: doc.pagePaths.first);
    expect(await store.getAllDocuments(), isEmpty);
  });

  test('ids keep increasing across restarts', () async {
    final first = newStore();
    final a = await first.createDocumentFromScans([makeSourceImage('a.jpg')]);

    final second = newStore();
    final b = await second.createDocumentFromScans([makeSourceImage('b.jpg')]);

    expect(
      b.id,
      greaterThan(a.id),
      reason: 'a reused id would make two documents share a page directory',
    );
  });

  test('a corrupt manifest recovers the pages already on disk', () async {
    final store = newStore();
    await store.createDocumentFromScans([makeSourceImage('a.jpg')]);

    File(
      p.join(tempRoot.path, 'documents', 'library.json'),
    ).writeAsStringSync('{ this is not json');

    final recovered = await newStore().getAllDocuments();
    expect(recovered, hasLength(1));
    expect(recovered.single.pageCount, 1);
  });

  test('renaming persists', () async {
    final store = newStore();
    final doc = await store.createDocumentFromScans([makeSourceImage('a.jpg')]);
    await store.renameDocument(doc.id, 'Passport');

    final reopened = await newStore().getAllDocuments();
    expect(reopened.single.title, 'Passport');
  });
}
