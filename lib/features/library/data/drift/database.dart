import 'package:scan2/features/library/data/document_storage.dart';
import 'package:scan2/features/library/domain/document.dart';

/// In-memory document store with on-disk page images.
/// (Drift codegen can replace this later; file persistence is what matters now.)
class AppDatabase {
  AppDatabase({DocumentStorage? storage})
      : _storage = storage ?? DocumentStorage();

  final DocumentStorage _storage;
  final List<Document> _docs = [];
  int _nextId = 1;

  Future<List<Document>> getAllDocuments() async => List.unmodifiable(_docs);

  Future<Document?> getDocument(int id) async {
    try {
      return _docs.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Document> createDocument(String title) async {
    final doc = Document(
      id: _nextId++,
      title: title,
      createdAt: DateTime.now(),
    );
    _docs.add(doc);
    return doc;
  }

  /// Imports scanner page paths into a new document.
  ///
  /// Set [edgesAlreadyApplied] for VisionKit / ML Kit results that are already
  /// perspective-cropped so crop UI can skip manual edge handles.
  Future<Document> createDocumentFromScans(
    List<String> sourcePaths, {
    String? title,
    bool edgesAlreadyApplied = false,
  }) async {
    if (sourcePaths.isEmpty) {
      throw ArgumentError('sourcePaths must not be empty');
    }

    final now = DateTime.now();
    final id = _nextId++;
    final docId = 'doc_$id';
    final stored = <String>[];

    for (var i = 0; i < sourcePaths.length; i++) {
      stored.add(
        await _storage.importPage(
          documentId: docId,
          index: i,
          sourcePath: sourcePaths[i],
        ),
      );
    }

    final doc = Document(
      id: id,
      title: title ?? _defaultTitle(now),
      createdAt: now,
      pagePaths: stored,
      edgesAlreadyApplied: edgesAlreadyApplied,
    );
    _docs.insert(0, doc);
    return doc;
  }

  /// Overwrites an existing page image (e.g. after crop + filter save).
  Future<Document?> replacePageBytes({
    required int documentId,
    required String pagePath,
    required List<int> bytes,
  }) async {
    final index = _docs.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;

    await _storage.writePageBytes(pagePath: pagePath, bytes: bytes);
    return _docs[index];
  }

  /// Finds the document that owns [pagePath], if any.
  Future<Document?> findDocumentByPagePath(String pagePath) async {
    for (final doc in _docs) {
      if (doc.pagePaths.contains(pagePath)) return doc;
    }
    return null;
  }

  Future<void> deleteDocument(int id) async {
    _docs.removeWhere((d) {
      if (d.id != id) return false;
      _storage.deleteDocumentFiles('doc_$id');
      return true;
    });
  }

  String _defaultTitle(DateTime now) {
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return 'Scan $m/$d $h:$min';
  }

  Future<void> close() async {}
}
