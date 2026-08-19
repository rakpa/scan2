import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/library/presentation/widgets/export_sheet.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  static const _exporter = ExportService();
  bool _busy = false;
  String _busyLabel = '';

  @override
  Widget build(BuildContext context) {
    // Cached in a provider so an unrelated rebuild (a dialog opening, the
    // busy flag flipping) does not re-read the document and blank the list.
    final document = ref.watch(documentProvider(widget.documentId)).valueOrNull;
    final pages = document?.pages ?? const <ScanPage>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(document?.title ?? 'Document'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename',
            onPressed: document == null ? null : () => _rename(document),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          if (document == null)
            const Center(child: CircularProgressIndicator())
          else if (pages.isEmpty)
            const Center(child: Text('This document has no pages.'))
          else
            Column(
              children: [
                _DocumentSummary(document: document),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: pages.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorder(document, oldIndex, newIndex),
                    itemBuilder: (context, index) => _PageCard(
                      key: ValueKey(pages[index].path),
                      page: pages[index],
                      index: index,
                      onEdit: () => _edit(document, pages[index]),
                      onDelete: () => _deletePage(document, pages[index]),
                    ),
                  ),
                ),
              ],
            ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (_busyLabel.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _busyLabel,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: document == null || pages.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 54,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => context.push('/camera'),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.add_rounded, size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _export(document),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: const Text('Export'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

  Future<void> _export(Document document) async {
    if (kIsWeb) {
      _showMessage('Export is available on device.');
      return;
    }

    final action = await ExportSheet.show(context, document);
    if (action == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = action == ExportAction.saveToPhotos
          ? 'Saving to Photos…'
          : 'Preparing PDF…';
    });

    try {
      final message = await runExportAction(action, document, _exporter);
      if (!mounted) return;
      if (message.isNotEmpty) _showMessage(message);
    } catch (e) {
      debugPrint('Export failed: $e');
      // Surfaced rather than swallowed: an export that silently does nothing
      // is indistinguishable from a broken button.
      if (mounted) _showMessage('Export failed: ${_readable(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readable(Object error) {
    final text = error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  Future<void> _rename(Document document) async {
    final controller = TextEditingController(text: document.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename scan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    await ref
        .read(documentRepositoryProvider)
        .renameDocument(document.id, trimmed);
    bumpLibrary(ref);
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

    await ref
        .read(documentRepositoryProvider)
        .deletePage(documentId: document.id, pagePath: page.path);
    bumpLibrary(ref);
    if (mounted && document.pageCount <= 1) context.pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Icon(
            Icons.layers_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '${document.pageCount} page'
            '${document.pageCount == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '·  ${DateFormat.yMMMd().add_jm().format(document.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 96,
                    child: PageThumbnail(
                      path: page.path,
                      cacheWidth: 216,
                      seed: index + 1,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Page ${index + 1}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.tune,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Tap to crop and enhance',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
