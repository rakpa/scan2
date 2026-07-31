import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/library/data/drift/database.dart' as drift_db;
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when scans are saved.
    ref.watch(libraryRevisionProvider);
    final dbOrRepo = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan2 Library'),
        actions: [
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('DEMO MODE', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.orange.shade100,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _buildBody(context, ref, dbOrRepo),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/camera'),
        icon: const Icon(Icons.camera_alt),
        label: const Text('New Scan'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, dynamic dbOrRepo) {
    if (kIsWeb) {
      final repo = dbOrRepo as dynamic;
      final docs = repo.getAllDocuments() as List<Document>;
      return _docList(context, docs, (id) {
        repo.deleteDocument(id);
        bumpLibrary(ref);
      });
    }

    final db = dbOrRepo as drift_db.AppDatabase;
    return FutureBuilder<List<Document>>(
      future: db.getAllDocuments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data ?? [];
        return _docList(context, docs, (id) async {
          await db.deleteDocument(id);
          bumpLibrary(ref);
        });
      },
    );
  }

  Widget _docList(
    BuildContext context,
    List<Document> docs,
    void Function(int id) onDelete,
  ) {
    if (docs.isEmpty) return _emptyState(context);

    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final thumb = doc.pagePaths.isNotEmpty ? doc.pagePaths.first : null;
        return ListTile(
          leading: thumb != null && !kIsWeb
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(thumb),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.description),
                  ),
                )
              : const Icon(Icons.description),
          title: Text(doc.title),
          subtitle: Text(
            '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'
            ' • ${doc.createdAt.toLocal()}',
          ),
          onTap: () => context.push('/library/document/${doc.id}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => onDelete(doc.id),
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No documents yet', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Tap New Scan — use “Scan with auto edges” for VisionKit edge detection',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
