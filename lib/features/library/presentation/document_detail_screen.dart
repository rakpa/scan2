import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/library/data/drift/database.dart' as drift_db;
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class DocumentDetailScreen extends ConsumerWidget {
  final int documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryRevisionProvider);

    return FutureBuilder<Document?>(
      future: _load(ref),
      builder: (context, snapshot) {
        final doc = snapshot.data;
        final title = doc?.title ?? 'Document $documentId';
        final pages = doc?.pagePaths ?? const <String>[];

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Export PDF',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        kIsWeb
                            ? 'Demo: PDF export is available on device'
                            : 'Exporting PDF…',
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share coming soon')),
                  );
                },
              ),
            ],
          ),
          body: pages.isEmpty
              ? const Center(child: Text('No pages in this document yet'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    final path = pages[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push(
                          '/crop',
                          extra: CropArgs(
                            imagePath: path,
                            edgesAlreadyApplied:
                                doc?.edgesAlreadyApplied ?? false,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: kIsWeb
                                  ? Container(
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                        child: Icon(Icons.description, size: 48),
                                      ),
                                    )
                                  : Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: Icon(Icons.broken_image),
                                        ),
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text('Page ${index + 1}'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => context.push('/camera'),
            child: const Icon(Icons.add_a_photo),
          ),
        );
      },
    );
  }

  Future<Document?> _load(WidgetRef ref) async {
    if (kIsWeb) {
      return ref.read(webDemoRepositoryProvider).getDocument(documentId);
    }
    final db = ref.read(appDatabaseProvider) as drift_db.AppDatabase;
    return db.getDocument(documentId);
  }
}
