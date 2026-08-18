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
    ref.watch(libraryRevisionProvider);
    final repository = ref.watch(documentRepositoryProvider);

    return Scaffold(
      body: FutureBuilder<List<Document>>(
        future: repository.getAllDocuments(),
        builder: (context, snapshot) {
          final documents = _filter(snapshot.data ?? const []);
          final loading =
              snapshot.connectionState == ConnectionState.waiting;

          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('Scan2'),
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
                ],
              ),
              if ((snapshot.data ?? const []).isNotEmpty)
                SliverToBoxAdapter(child: _buildSearchField()),
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
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  sliver: SliverList.separated(
                    itemCount: documents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _DocumentTile(
                      document: documents[index],
                      onDeleted: () => _confirmDelete(documents[index]),
                      onRenamed: () => _promptRename(documents[index]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/camera'),
        icon: const Icon(Icons.document_scanner),
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SearchBar(
        hintText: 'Search scans',
        leading: const Icon(Icons.search),
        onChanged: (value) => setState(() => _query = value),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
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

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onDeleted,
    required this.onRenamed,
  });

  final Document document;
  final VoidCallback onDeleted;
  final VoidCallback onRenamed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail =
        document.pages.isNotEmpty ? document.pages.first.path : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push('/library/document/${document.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: thumbnail != null && !kIsWeb
                      ? Image.file(
                          File(thumbnail),
                          fit: BoxFit.cover,
                          cacheWidth: 168,
                          errorBuilder: (_, __, ___) => const _ThumbFallback(),
                        )
                      : const _ThumbFallback(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${document.pageCount} page'
                      '${document.pageCount == 1 ? '' : 's'} · '
                      '${DateFormat.yMMMd().add_jm().format(document.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') onRenamed();
                  if (value == 'delete') onDeleted();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
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
      child: const Center(child: Icon(Icons.description_outlined)),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text('No scans yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Point the camera at a document and Scan2 finds the edges, '
              'straightens the page and cleans it up automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
    return const Center(child: Text('No scans match that search.'));
  }
}
