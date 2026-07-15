import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/library/data/drift/database.dart';
import 'package:scan2/features/library/domain/document.dart' as domain;

/// Simple in-memory document store for Web demo mode
class WebDemoRepository {
  final List<domain.Document> _documents = [];
  int _nextId = 1;

  List<domain.Document> getAllDocuments() => List.unmodifiable(_documents);

  domain.Document createDocument(String title) {
    final doc = domain.Document(
      id: _nextId++,
      title: title,
      createdAt: DateTime.now(),
      pageCount: 0,
    );
    _documents.add(doc);
    return doc;
  }

  void deleteDocument(int id) {
    _documents.removeWhere((d) => d.id == id);
  }

  void addPageToDocument(int documentId) {
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index != -1) {
      final old = _documents[index];
      _documents[index] = old.copyWith(pageCount: old.pageCount + 1);
    }
  }
}

final webDemoRepositoryProvider = Provider<WebDemoRepository>((ref) {
  return WebDemoRepository();
});

/// Main database provider — uses real Drift on mobile, in-memory demo on web
final appDatabaseProvider = Provider<dynamic>((ref) {
  if (kIsWeb) {
    return ref.watch(webDemoRepositoryProvider);
  } else {
    final db = AppDatabase();
    ref.onDispose(() => db.close());
    return db;
  }
});