import 'package:scan2/features/library/domain/document.dart';

/// Mobile Drift database stub.
/// Real persistence uses Drift + sqlite; web uses [WebDemoRepository].
class AppDatabase {
  final List<Document> _docs = [];
  int _nextId = 1;

  Future<List<Document>> getAllDocuments() async => List.unmodifiable(_docs);

  Future<Document> createDocument(String title) async {
    final doc = Document(
      id: _nextId++,
      title: title,
      createdAt: DateTime.now(),
    );
    _docs.add(doc);
    return doc;
  }

  Future<void> deleteDocument(int id) async {
    _docs.removeWhere((d) => d.id == id);
  }

  Future<void> close() async {}
}
