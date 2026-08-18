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
  final List<Document> _documents = [];
  int _nextId = 1;

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
  }) async =>
      getDocument(documentId);

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
    final remaining =
        doc.pages.where((page) => page.path != pagePath).toList();
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
  if (kIsWeb) return WebDemoRepository();
  final store = DocumentStore();
  ref.onDispose(store.close);
  return store;
});
