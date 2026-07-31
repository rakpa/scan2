import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class DocumentDetailScreen extends ConsumerWidget {
  final int documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String title = 'Document $documentId';
    int pageCount = 0;

    if (kIsWeb) {
      final repo = ref.watch(webDemoRepositoryProvider);
      final docs = repo.getAllDocuments();
      final match = docs.where((d) => d.id == documentId);
      if (match.isNotEmpty) {
        title = match.first.title;
        pageCount = match.first.pageCount;
      }
    }

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
      body: pageCount == 0
          ? const Center(
              child: Text('No pages in this document yet'),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: pageCount,
              itemBuilder: (context, index) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/crop'),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.description, size: 48),
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
  }
}
