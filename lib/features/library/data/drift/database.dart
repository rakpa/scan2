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

  /// Imports VisionKit / ML Kit cropped page paths into a new document.
  Future<Document> createDocumentFromScans(
    List<String> sourcePaths, {
    String? title,
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
    );
    _docs.insert(0, doc);
    return doc;
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
