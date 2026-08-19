import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documentsAsync = ref.watch(documentsProvider);
    // valueOrNull keeps the previous list on screen while a refresh runs,
    // instead of blanking the library after every save.
    final all = documentsAsync.valueOrNull;
    final documents = _filter(all ?? const []);
    final loading = all == null && documentsAsync.isLoading;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 116,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Text(
                'Scan2',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            actions: [
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(label: Text('DEMO')),
                ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if ((all ?? const []).isNotEmpty)
            SliverToBoxAdapter(child: _buildSearchField(theme)),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (documents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _query.isEmpty
                  ? const _EmptyLibrary()
                  : const _NoResults(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  // Roughly a page shape plus room for the caption.
                  childAspectRatio: 0.66,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: documents.length,
                  (context, index) => _DocumentCard(
                    document: documents[index],
                    onDelete: () => _confirmDelete(documents[index]),
                    onRename: () => _promptRename(documents[index]),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/camera'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }

  List<Document> _filter(List<Document> documents) {
    if (_query.isEmpty) return documents;
    final needle = _query.toLowerCase();
    return [
      for (final doc in documents)
        if (doc.title.toLowerCase().contains(needle)) doc,
    ];
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search scans',
          prefixIcon: const Icon(Icons.search, size: 21),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${document.title}"?'),
        content: Text(
          '${document.pageCount} page${document.pageCount == 1 ? '' : 's'} '
          'will be permanently removed.',
        ),
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

    await ref.read(documentRepositoryProvider).deleteDocument(document.id);
    bumpLibrary(ref);
  }

  Future<void> _promptRename(Document document) async {
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
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onDelete,
    required this.onRename,
  });

  final Document document;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = document.pages.isNotEmpty
        ? document.pages.first.path
        : null;

    return Card(
      child: InkWell(
        onTap: () => context.push('/library/document/${document.id}'),
        onLongPress: onRename,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: thumbnail != null && !kIsWeb
                        ? Image.file(
                            File(thumbnail),
                            fit: BoxFit.cover,
                            // Decoded at display size; full 12MP thumbnails
                            // would blow the image cache on a long library.
                            cacheWidth: 420,
                            errorBuilder: (_, __, ___) =>
                                const _ThumbFallback(),
                          )
                        : const _ThumbFallback(),
                  ),
                  if (document.pageCount > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Badge(label: '${document.pageCount}'),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.MMMd().format(document.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      tooltip: 'More',
                      onSelected: (value) {
                        if (value == 'rename') onRename();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.description_outlined,
        size: 34,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.document_scanner_outlined,
                size: 44,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 26),
            Text('Nothing scanned yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              'Tap Scan and point the camera at a document. '
              'Scan2 finds the edges, straightens the page and cleans it up.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No scans match that search',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
