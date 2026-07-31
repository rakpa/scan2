import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies scanner temp images into permanent app storage.
///
/// Layout: `<appDocuments>/documents/<documentId>/page_000.jpg`
class DocumentStorage {
  Future<Directory> _documentsRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'documents'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<String> importPage({
    required String documentId,
    required int index,
    required String sourcePath,
  }) async {
    final root = await _documentsRoot();
    final docDir = Directory(p.join(root.path, documentId));
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }

    final ext =
        p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final fileName = 'page_${index.toString().padLeft(3, '0')}$ext';
    final destPath = p.join(docDir.path, fileName);
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<void> deleteDocumentFiles(String documentId) async {
    final root = await _documentsRoot();
    final docDir = Directory(p.join(root.path, documentId));
    if (await docDir.exists()) {
      await docDir.delete(recursive: true);
    }
  }
}
