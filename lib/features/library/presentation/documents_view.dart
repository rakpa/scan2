import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

enum DocumentSort {
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name'),
  pages('Most pages');

  const DocumentSort(this.label);

  final String label;
}

/// The documents workspace: search, sort, grid or list, and multi-select.
class DocumentsView extends ConsumerStatefulWidget {
  const DocumentsView({super.key, this.highlightDocumentId});

  /// Newly saved document to visually emphasise after Screen 11.
  final int? highlightDocumentId;

  @override
  ConsumerState<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends ConsumerState<DocumentsView> {
  String _query = '';
  DocumentSort _sort = DocumentSort.newest;
  bool _gridView = true;
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentsProvider);
    final all = async.valueOrNull;
    final documents = _sorted(_filtered(all ?? const []));
    final loading = all == null && async.isLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _selecting
                  ? _SelectionBar(
                      count: _selected.length,
                      onCancel: () => setState(_selected.clear),
                      onSelectAll: () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(documents.map((d) => d.id));
                      }),
                      onDelete: () => _deleteSelected(documents),
                    )
                  : _Header(count: all?.length ?? 0),
            ),
            if ((all ?? const []).isNotEmpty) ...[
              SliverToBoxAdapter(child: _searchField()),
              SliverToBoxAdapter(child: _toolBar(documents.length)),
            ],
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
            else if (_gridView)
              _grid(documents)
            else
              _list(documents),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------

  List<Document> _filtered(List<Document> documents) {
    if (_query.isEmpty) return documents;
    final needle = _query.toLowerCase();
    return [
      for (final doc in documents)
        if (doc.title.toLowerCase().contains(needle)) doc,
    ];
  }

  List<Document> _sorted(List<Document> documents) {
    final list = [...documents];
    switch (_sort) {
      case DocumentSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case DocumentSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case DocumentSort.name:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case DocumentSort.pages:
        list.sort((a, b) => b.pageCount.compareTo(a.pageCount));
    }
    return list;
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: BrandType.body,
        decoration: InputDecoration(
          hintText: 'Search documents',
          hintStyle: BrandType.body.copyWith(color: Brand.greyLight),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
            color: Brand.greyLight,
          ),
          isDense: true,
          filled: true,
          fillColor: Brand.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.blue, width: 1.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.outline),
          ),
        ),
      ),
    );
  }

  Widget _toolBar(int shown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
      child: Row(
        children: [
          Text(
            '$shown document${shown == 1 ? '' : 's'}',
            style: BrandType.caption,
          ),
          const Spacer(),
          PopupMenuButton<DocumentSort>(
            initialValue: _sort,
            tooltip: 'Sort',
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final option in DocumentSort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.swap_vert_rounded,
                    size: 19,
                    color: Brand.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(_sort.label, style: BrandType.caption),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: _gridView ? 'Show as list' : 'Show as grid',
            icon: Icon(
              _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              size: 21,
            ),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<Document> documents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 140),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 0.62,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: documents.length,
          (context, index) => _DocumentTile(
            document: documents[index],
            index: index,
            selected: _selected.contains(documents[index].id),
            selecting: _selecting,
            highlighted:
                widget.highlightDocumentId == documents[index].id,
            onTap: () => _open(documents[index]),
            onToggle: () => _toggle(documents[index]),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Document> documents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 140),
      sliver: SliverList.separated(
        itemCount: documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _DocumentRow(
          document: documents[index],
          index: index,
          selected: _selected.contains(documents[index].id),
          selecting: _selecting,
          highlighted: widget.highlightDocumentId == documents[index].id,
          onTap: () => _open(documents[index]),
          onToggle: () => _toggle(documents[index]),
        ),
      ),
    );
  }

  void _open(Document document) {
    if (_selecting) {
      _toggle(document);
      return;
    }
    context.push('/library/document/${document.id}');
  }

  void _toggle(Document document) {
    setState(() {
      if (!_selected.remove(document.id)) _selected.add(document.id);
    });
  }

  Future<void> _deleteSelected(List<Document> documents) async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count document${count == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
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

    final repository = ref.read(documentRepositoryProvider);
    for (final id in _selected.toList()) {
      await repository.deleteDocument(id);
    }
    setState(_selected.clear);
    bumpLibrary(ref);
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Documents', style: BrandType.headline),
                const SizedBox(height: 3),
                Text(
                  count == 0
                      ? 'Everything you scan lives here'
                      : '$count saved on this device',
                  style: BrandType.caption,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 21),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onCancel,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          Text(
            '$count selected',
            style: BrandType.title,
          ),
          const Spacer(),
          TextButton(onPressed: onSelectAll, child: const Text('All')),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
            onPressed: onDelete,
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.index,
    required this.selected,
    required this.selecting,
    required this.highlighted,
    required this.onTap,
    required this.onToggle,
  });

  final Document document;
  final int index;
  final bool selected;
  final bool selecting;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: highlighted ? ValueKey('highlight-${document.id}') : null,
      onTap: onTap,
      onLongPress: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (selected || highlighted) ? Brand.blue : Brand.outline,
                  width: (selected || highlighted) ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageThumbnail(
                      path: document.pages.isEmpty
                          ? null
                          : document.pages.first.path,
                      cacheWidth: 420,
                      seed: document.id + index,
                    ),
                    if (document.pageCount > 1)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _PageBadge(count: document.pageCount),
                      ),
                    if (selecting)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _SelectionDot(selected: selected),
                      )
                    else if (highlighted)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: _NewBadge(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            document.title,
            style: BrandType.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat.MMMd().format(document.createdAt),
            style: BrandType.caption,
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.index,
    required this.selected,
    required this.selecting,
    required this.highlighted,
    required this.onTap,
    required this.onToggle,
  });

  final Document document;
  final int index;
  final bool selected;
  final bool selecting;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: highlighted ? ValueKey('highlight-${document.id}') : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: (selected || highlighted) ? Brand.blue : Brand.outline,
          width: (selected || highlighted) ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 54,
                  height: 70,
                  child: PageThumbnail(
                    path: document.pages.isEmpty
                        ? null
                        : document.pages.first.path,
                    cacheWidth: 162,
                    seed: document.id + index,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: BrandType.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${document.pageCount} page'
                      '${document.pageCount == 1 ? '' : 's'} · '
                      '${DateFormat.yMMMd().format(document.createdAt)}',
                      style: BrandType.caption,
                    ),
                  ],
                ),
              ),
              if (selecting)
                _SelectionDot(selected: selected)
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Brand.greyLight,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Brand.blue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'New',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PageBadge extends StatelessWidget {
  const _PageBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.copy_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: BrandType.caption.copyWith(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.85),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : null,
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
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 118,
              height: 150,
              child: Stack(
                children: [
                  // Two tilted sheets behind the front page, so the empty
                  // state reads as "a stack of documents" at a glance.
                  Transform.rotate(
                    angle: -0.16,
                    child: _GhostSheet(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Transform.rotate(
                    angle: 0.10,
                    child: _GhostSheet(
                      color: theme.colorScheme.surfaceContainerHigh,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 84,
                      height: 108,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.document_scanner_outlined,
                        size: 38,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text('Nothing scanned yet', style: BrandType.title),
            const SizedBox(height: 10),
            const Text(
              'Tap the scan button below. Your device finds the page edges '
              'and Scan2 straightens and cleans it up.',
              textAlign: TextAlign.center,
              style: BrandType.subtitle,
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostSheet extends StatelessWidget {
  const _GhostSheet({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 108,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: Brand.greyLight,
            ),
            SizedBox(height: 12),
            Text(
              'No documents match that search',
              style: BrandType.subtitle,
            ),
          ],
        ),
      ),
    );
  }
}
