import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies scanner temp images into permanent app storage.
///
/// Layout: `<appDocuments>/documents/<documentId>/page_000.jpg`
class DocumentStorage {
  DocumentStorage({Directory? overrideRoot}) : _overrideRoot = overrideRoot;

  /// Injected in tests so the store can run without platform channels.
  final Directory? _overrideRoot;

  Directory? _cachedRoot;

  Future<Directory> documentsRoot() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;

    final base = _overrideRoot ?? await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, 'documents'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _cachedRoot = root;
    return root;
  }

  Future<String> rootPath() async => (await documentsRoot()).path;

  Future<String> importPage({
    required String documentId,
    required int index,
    required String sourcePath,
  }) async {
    final root = await documentsRoot();
    final docDir = Directory(p.join(root.path, documentId));
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }

    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final fileName = 'page_${index.toString().padLeft(3, '0')}$extension';
    final destination = p.join(docDir.path, fileName);
    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<void> writePageBytes({
    required String pagePath,
    required List<int> bytes,
  }) async {
    final file = File(pagePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteDocumentFiles(String documentId) async {
    final root = await documentsRoot();
    final docDir = Directory(p.join(root.path, documentId));
    if (await docDir.exists()) {
      await docDir.delete(recursive: true);
    }
  }
}
