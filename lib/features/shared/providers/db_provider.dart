import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/document_repository.dart';

/// In-memory library used for the browser demo, where there is no file system
/// to persist to and no camera to scan with.
class WebDemoRepository implements DocumentRepository {
  WebDemoRepository({bool seedSampleData = false}) {
    if (seedSampleData) _seed();
  }

  final List<Document> _documents = [];
  int _nextId = 1;

  /// Sample documents for the browser demo, where there is no camera to
  /// produce any. Page thumbnails fall back to the drawn stand-in.
  void _seed() {
    const titles = [
      'Rental agreement',
      'Passport',
      'Invoice 2043',
      'Hotel receipt',
      'Insurance policy',
      'Bank statement',
    ];
    const pageCounts = [4, 1, 2, 1, 9, 3];
    final now = DateTime.now();

    for (var i = 0; i < titles.length; i++) {
      _documents.add(
        Document(
          id: _nextId++,
          title: titles[i],
          createdAt: now.subtract(Duration(days: i * 3, hours: i * 5)),
          pages: [
            for (var p = 0; p < pageCounts[i]; p++)
              ScanPage(path: 'demo_${i}_$p'),
          ],
        ),
      );
    }
  }

  @override
  Future<List<Document>> getAllDocuments() async =>
      List.unmodifiable(_documents);

  @override
  Future<Document?> getDocument(int id) async {
    for (final doc in _documents) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  @override
  Future<Document> createDocumentFromScans(
    List<String> sourcePaths, {
    String? title,
    bool edgesAlreadyApplied = false,
  }) async {
    final doc = Document(
      id: _nextId++,
      title: title ?? 'Demo scan',
      createdAt: DateTime.now(),
      pages: List.generate(
        sourcePaths.isEmpty ? 1 : sourcePaths.length,
        (i) => ScanPage(path: 'demo_page_$i'),
      ),
      edgesAlreadyApplied: edgesAlreadyApplied,
    );
    _documents.insert(0, doc);
    return doc;
  }

  @override
  Future<Document?> addPages(int documentId, List<String> sourcePaths) async {
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;
    final doc = _documents[index];
    final updated = doc.copyWith(
      pages: [
        ...doc.pages,
        for (var i = 0; i < sourcePaths.length; i++)
          ScanPage(path: 'demo_page_${doc.pageCount + i}'),
      ],
    );
    _documents[index] = updated;
    return updated;
  }

  @override
  Future<Document?> replacePageBytes({
    required int documentId,
    required String pagePath,
    required List<int> bytes,
    Quad? quad,
    ScanAdjustments? adjustments,
  }) async => getDocument(documentId);

  @override
  Future<Document?> findDocumentByPagePath(String pagePath) async {
    for (final doc in _documents) {
      if (doc.pagePaths.contains(pagePath)) return doc;
    }
    return null;
  }

  @override
  Future<void> renameDocument(int id, String title) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index != -1) {
      _documents[index] = _documents[index].copyWith(title: title);
    }
  }

  @override
  Future<void> deleteDocument(int id) async {
    _documents.removeWhere((d) => d.id == id);
  }

  @override
  Future<void> deletePage({
    required int documentId,
    required String pagePath,
  }) async {
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return;
    final doc = _documents[index];
    final remaining = doc.pages.where((page) => page.path != pagePath).toList();
    if (remaining.isEmpty) {
      _documents.removeAt(index);
    } else {
      _documents[index] = doc.copyWith(pages: remaining);
    }
  }
}

/// Bumps whenever the library changes, so screens watching it rebuild.
final libraryRevisionProvider = StateProvider<int>((ref) => 0);

void bumpLibrary(WidgetRef ref) {
  ref.read(libraryRevisionProvider.notifier).state++;
}

/// The app's document library.
final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  if (kIsWeb) return WebDemoRepository(seedSampleData: true);
  final store = DocumentStore();
  ref.onDispose(store.close);
  return store;
});

/// The library contents.
///
/// Held in a provider rather than created inline in a `FutureBuilder`: a
/// future built during `build` is a *new* future on every rebuild, which resets
/// the builder to its loading state. Typing in the library's search field
/// would flash a spinner over the results on every keystroke.
final documentsProvider = FutureProvider<List<Document>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(documentRepositoryProvider).getAllDocuments();
});

/// A single document by id.
final documentProvider = FutureProvider.family<Document?, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(documentRepositoryProvider).getDocument(id);
});
