import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/library/data/drift/database.dart';
import 'package:scan2/features/library/domain/document.dart' as domain;

/// Simple in-memory document store for Web demo mode
class WebDemoRepository {
  final List<domain.Document> _documents = [];
  int _nextId = 1;

  List<domain.Document> getAllDocuments() => List.unmodifiable(_documents);

  domain.Document? getDocument(int id) {
    try {
      return _documents.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  domain.Document createDocument(String title) {
    final doc = domain.Document(
      id: _nextId++,
      title: title,
      createdAt: DateTime.now(),
    );
    _documents.add(doc);
    return doc;
  }

  void deleteDocument(int id) {
    _documents.removeWhere((d) => d.id == id);
  }

  void addPageToDocument(int documentId) {
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return;
    final old = _documents[index];
    _documents[index] = old.copyWith(
      pagePaths: [...old.pagePaths, 'demo_page_${old.pageCount}'],
    );
  }
}

final webDemoRepositoryProvider = Provider<WebDemoRepository>((ref) {
  return WebDemoRepository();
});

/// Bumps when the library changes so screens rebuild.
final libraryRevisionProvider = StateProvider<int>((ref) => 0);

void bumpLibrary(WidgetRef ref) {
  ref.read(libraryRevisionProvider.notifier).state++;
}

/// Main database provider — uses real storage on mobile, in-memory demo on web
final appDatabaseProvider = Provider<dynamic>((ref) {
  if (kIsWeb) {
    return ref.watch(webDemoRepositoryProvider);
  } else {
    final db = AppDatabase();
    ref.onDispose(() => db.close());
    return db;
  }
});
