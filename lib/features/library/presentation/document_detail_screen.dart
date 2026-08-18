import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState
    extends ConsumerState<DocumentDetailScreen> {
  static const _exporter = ExportService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(libraryRevisionProvider);
    final repository = ref.watch(documentRepositoryProvider);

    return FutureBuilder<Document?>(
      future: repository.getDocument(widget.documentId),
      builder: (context, snapshot) {
        final document = snapshot.data;
        final pages = document?.pages ?? const <ScanPage>[];

        return Scaffold(
          appBar: AppBar(
            title: Text(document?.title ?? 'Document'),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export PDF',
                onPressed: document == null || _busy
                    ? null
                    : () => _share(document, asPdf: true),
              ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share images',
                onPressed: document == null || _busy
                    ? null
                    : () => _share(document, asPdf: false),
              ),
            ],
          ),
          body: Stack(
            children: [
              if (pages.isEmpty)
                const Center(child: Text('This document has no pages.'))
              else
                ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: pages.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _reorder(document!, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return _PageCard(
                      key: ValueKey(page.path),
                      page: page,
                      index: index,
                      onEdit: () => _edit(document!, page),
                      onDelete: () => _deletePage(document!, page),
                    );
                  },
                ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black38,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/camera'),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add pages'),
          ),
        );
      },
    );
  }

  void _edit(Document document, ScanPage page) {
    context.push(
      '/crop',
      extra: CropArgs(
        // Editing re-derives from the original capture when one was kept.
        imagePath: page.editSource,
        initialQuad: page.quad,
        adjustments: page.adjustments,
        edgesAlreadyApplied: document.edgesAlreadyApplied,
      ),
    );
  }

  Future<void> _reorder(Document document, int oldIndex, int newIndex) async {
    final repository = ref.read(documentRepositoryProvider);
    if (repository is! DocumentStore) return;
    await repository.reorderPages(document.id, oldIndex, newIndex);
    bumpLibrary(ref);
  }

  Future<void> _deletePage(Document document, ScanPage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this page?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(documentRepositoryProvider).deletePage(
          documentId: document.id,
          pagePath: page.path,
        );
    bumpLibrary(ref);
    if (mounted && document.pageCount <= 1) context.pop();
  }

  Future<void> _share(Document document, {required bool asPdf}) async {
    if (kIsWeb) {
      _showMessage('Export is available on device.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (asPdf) {
        await _exporter.sharePdf(document);
      } else {
        await _exporter.shareImages(document);
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) _showMessage('Could not export this document.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    super.key,
    required this.page,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final ScanPage page;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 84,
                  child: kIsWeb
                      ? const ColoredBox(color: Colors.black12)
                      : Image.file(
                          File(page.path),
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page ${index + 1}',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      page.canReedit
                          ? 'Tap to adjust edges and enhancement'
                          : 'Tap to enhance',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete page',
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
