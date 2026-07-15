import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/library/data/drift/database.dart' as drift_db;

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      final docs = repo.getAllDocuments();

      if (docs.isEmpty) {
        return _emptyState(context);
      }

      return ListView.builder(
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final doc = docs[index];
          return ListTile(
            leading: const Icon(Icons.description),
            title: Text(doc.title),
            subtitle: Text('${doc.pageCount} pages'),
            onTap: () => context.push('/library/document/${doc.id}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                repo.deleteDocument(doc.id);
                (context as Element).markNeedsBuild();
              },
            ),
          );
        },
      );
    } else {
      final db = dbOrRepo as drift_db.AppDatabase;
      return FutureBuilder(
        future: db.getAllDocuments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return _emptyState(context);
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return ListTile(
                leading: const Icon(Icons.description),
                title: Text(doc.title),
                subtitle: Text('${doc.pageCount} pages • ${doc.createdAt.toLocal()}'),
                onTap: () => context.push('/library/document/${doc.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await db.deleteDocument(doc.id);
                    (context as Element).markNeedsBuild();
                  },
                ),
              );
            },
          );
        },
      );
    }
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.document_scanner_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No documents yet', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Tap + to start scanning'),
        ],
      ),
    );
  }
}