import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/document_folder.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

enum DocumentSort {
  newest('Date (Newest)'),
  oldest('Date (Oldest)'),
  nameAz('Name A-Z'),
  nameZa('Name Z-A'),
  size('File size');

  const DocumentSort(this.label);

  final String label;
}

enum _DateFilter { any, today, week, month }

/// Screen 12: local document library.
class DocumentsView extends ConsumerStatefulWidget {
  const DocumentsView({super.key, this.highlightDocumentId});

  /// Newly saved document to visually emphasise after Screen 11.
  final int? highlightDocumentId;

  @override
  ConsumerState<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends ConsumerState<DocumentsView> {
  static const _exporter = ExportService();

  String _query = '';
  bool _searchOpen = false;
  DocumentSort _sort = DocumentSort.newest;
  bool _gridView = false;
  String _category = 'All';
  String? _typeFilter;
  _DateFilter _dateFilter = _DateFilter.any;
  bool _favoritesOnly = false;
  bool _busy = false;

  DocumentStore? get _store {
    final repo = ref.read(documentRepositoryProvider);
    return repo is DocumentStore ? repo : null;
  }

  List<DocumentFolder> get _folders {
    final cached = _store?.cachedFolders;
    if (cached != null && cached.isNotEmpty) return cached;
    return DocumentFolder.defaults;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentsProvider);
    final all = async.valueOrNull;
    final documents = _sorted(_filtered(all ?? const []));
    final loading = all == null && async.isLoading;

    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _TopBar(
                    searchOpen: _searchOpen,
                    gridView: _gridView,
                    onSearch: () => setState(() {
                      _searchOpen = !_searchOpen;
                      if (!_searchOpen) _query = '';
                    }),
                    onToggleLayout: () =>
                        setState(() => _gridView = !_gridView),
                    onAdd: _add,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _TitleBlock(count: all?.length ?? 0),
                ),
                if (_searchOpen)
                  SliverToBoxAdapter(child: _searchField()),
                SliverToBoxAdapter(
                  child: _CategoryChips(
                    selected: _category,
                    onSelected: (name) => setState(() => _category = name),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SortFilterRow(
                    sort: _sort,
                    filterActive: _hasExtraFilters,
                    onSort: (value) => setState(() => _sort = value),
                    onFilter: _openFilters,
                  ),
                ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (documents.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _query.isEmpty && _category == 'All' && !_hasExtraFilters
                        ? const _EmptyLibrary()
                        : const _NoResults(),
                  )
                else if (_gridView)
                  _grid(documents)
                else
                  _list(documents),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _hasExtraFilters =>
      _typeFilter != null ||
      _dateFilter != _DateFilter.any ||
      _favoritesOnly;

  List<Document> _filtered(List<Document> documents) {
    final needle = _query.trim().toLowerCase();
    final now = DateTime.now();
    return [
      for (final doc in documents)
        if (_passes(doc, needle, now)) doc,
    ];
  }

  bool _passes(Document doc, String needle, DateTime now) {
    final folder = _folderName(doc);
    if (_category != 'All' && folder != _category) return false;
    if (_typeFilter != null && doc.typeLabel != _typeFilter) return false;
    if (_favoritesOnly && !doc.favorited) return false;
    if (!_inDateRange(doc.createdAt, now)) return false;
    if (needle.isEmpty) return true;
    final haystack = [
      doc.title,
      doc.fileName,
      doc.typeLabel,
      doc.documentType,
      folder,
      doc.formattedSize,
      DateFormat.yMMMd().format(doc.createdAt),
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
  }

  bool _inDateRange(DateTime created, DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    switch (_dateFilter) {
      case _DateFilter.any:
        return true;
      case _DateFilter.today:
        return !created.isBefore(start);
      case _DateFilter.week:
        return !created.isBefore(start.subtract(const Duration(days: 7)));
      case _DateFilter.month:
        return !created.isBefore(start.subtract(const Duration(days: 30)));
    }
  }

  List<Document> _sorted(List<Document> documents) {
    final list = [...documents];
    switch (_sort) {
      case DocumentSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case DocumentSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case DocumentSort.nameAz:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case DocumentSort.nameZa:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case DocumentSort.size:
        list.sort(
          (a, b) => (b.fileSizeBytes ?? 0).compareTo(a.fileSizeBytes ?? 0),
        );
    }
    return list;
  }

  String _folderName(Document document) {
    final id = document.folderId;
    for (final folder in _folders) {
      if (folder.id == id) return folder.name;
    }
    return 'Invoices';
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        autofocus: true,
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
          fillColor: Brand.canvas,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.blue, width: 1.6),
          ),
        ),
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
          (context, index) => _DocumentGridCard(
            document: documents[index],
            folderName: _folderName(documents[index]),
            highlighted: widget.highlightDocumentId == documents[index].id,
            onTap: () => _open(documents[index]),
            onMore: () => _more(documents[index]),
            onFavorite: () => _toggleFavorite(documents[index]),
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
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _DocumentListCard(
          document: documents[index],
          folderName: _folderName(documents[index]),
          highlighted: widget.highlightDocumentId == documents[index].id,
          onTap: () => _open(documents[index]),
          onMore: () => _more(documents[index]),
          onFavorite: () => _toggleFavorite(documents[index]),
        ),
      ),
    );
  }

  void _open(Document document) {
    context.push('/library/document/${document.id}');
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('Scan Document'),
                  onTap: () => Navigator.pop(ctx, 'scan'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Import from Gallery'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Import from Files'),
                  onTap: () => Navigator.pop(ctx, 'files'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'scan':
        context.push('/camera');
      case 'gallery':
        await importGalleryAsDocument(context, ref, title: 'Photo scan');
      case 'files':
        await importFilesAsDocument(context, ref);
    }
  }

  Future<void> _openFilters() async {
    var type = _typeFilter;
    var date = _dateFilter;
    var favorites = _favoritesOnly;
    var category = _category;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filter', style: BrandType.title),
                    const SizedBox(height: 12),
                    const Text('File type', style: BrandType.caption),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Any'),
                          selected: type == null,
                          onSelected: (_) => setSheet(() => type = null),
                        ),
                        ChoiceChip(
                          label: const Text('PDF'),
                          selected: type == 'PDF',
                          onSelected: (_) => setSheet(() => type = 'PDF'),
                        ),
                        ChoiceChip(
                          label: const Text('JPG'),
                          selected: type == 'JPG',
                          onSelected: (_) => setSheet(() => type = 'JPG'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Category', style: BrandType.caption),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final name in DocumentFolder.chipNames)
                          ChoiceChip(
                            label: Text(name),
                            selected: category == name,
                            onSelected: (_) => setSheet(() => category = name),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Date', style: BrandType.caption),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Any'),
                          selected: date == _DateFilter.any,
                          onSelected: (_) =>
                              setSheet(() => date = _DateFilter.any),
                        ),
                        ChoiceChip(
                          label: const Text('Today'),
                          selected: date == _DateFilter.today,
                          onSelected: (_) =>
                              setSheet(() => date = _DateFilter.today),
                        ),
                        ChoiceChip(
                          label: const Text('Last 7 days'),
                          selected: date == _DateFilter.week,
                          onSelected: (_) =>
                              setSheet(() => date = _DateFilter.week),
                        ),
                        ChoiceChip(
                          label: const Text('Last 30 days'),
                          selected: date == _DateFilter.month,
                          onSelected: (_) =>
                              setSheet(() => date = _DateFilter.month),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Favorites only'),
                      value: favorites,
                      onChanged: (v) => setSheet(() => favorites = v),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (applied != true || !mounted) return;
    setState(() {
      _typeFilter = type;
      _dateFilter = date;
      _favoritesOnly = favorites;
      _category = category;
    });
  }

  Future<void> _toggleFavorite(Document document) async {
    final store = _store;
    if (store == null) return;
    await store.setFavorited(document.id, !document.favorited);
    bumpLibrary(ref);
  }

  Future<void> _more(Document document) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('Rename'),
                  onTap: () => Navigator.pop(ctx, 'rename'),
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('Move'),
                  onTap: () => Navigator.pop(ctx, 'move'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Duplicate'),
                  onTap: () => Navigator.pop(ctx, 'duplicate'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('Share'),
                  onTap: () => Navigator.pop(ctx, 'share'),
                ),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Save to Files'),
                  onTap: () => Navigator.pop(ctx, 'files'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Save to Gallery'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Brand.pdfRed),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Brand.pdfRed),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _rename(document);
      case 'move':
        await _move(document);
      case 'duplicate':
        await _duplicate(document);
      case 'share':
        await _run(() => _exporter.sharePdf(document));
      case 'files':
        await _run(() async {
          final saved = await _exporter.savePdfToFiles(document);
          if (saved && mounted) _toast('PDF saved to Files');
        });
      case 'gallery':
        await _run(() async {
          final saved = await _exporter.saveToPhotos(document);
          if (mounted) {
            _toast('Saved $saved page${saved == 1 ? '' : 's'} to Gallery');
          }
        });
      case 'delete':
        await _delete(document);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Document document) async {
    final controller = TextEditingController(text: document.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    await ref.read(documentRepositoryProvider).renameDocument(
      document.id,
      trimmed,
    );
    bumpLibrary(ref);
  }

  Future<void> _move(Document document) async {
    final folders = _folders;
    final chosen = await showModalBottomSheet<DocumentFolder>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text('Move to folder', style: BrandType.title),
                ),
                for (final folder in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined, color: Brand.blue),
                    title: Text(folder.name),
                    onTap: () => Navigator.pop(ctx, folder),
                  ),
              ],
            ),
          ),
        );
      },
    );
    final store = _store;
    if (chosen == null || store == null || !mounted) return;
    await store.setDocumentFolder(document.id, chosen.id);
    bumpLibrary(ref);
  }

  Future<void> _duplicate(Document document) async {
    final store = _store;
    if (store == null) return;
    setState(() => _busy = true);
    try {
      final copy = await store.duplicateDocument(document.id);
      bumpLibrary(ref);
      if (mounted && copy != null) _toast('Duplicated as ${copy.title}');
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(documentRepositoryProvider).deleteDocument(document.id);
    bumpLibrary(ref);
  }

  void _toast(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchOpen,
    required this.gridView,
    required this.onSearch,
    required this.onToggleLayout,
    required this.onAdd,
  });

  final bool searchOpen;
  final bool gridView;
  final VoidCallback onSearch;
  final VoidCallback onToggleLayout;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
      child: Row(
        children: [
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ScanellaWordmark(fontSize: 22, color: Brand.blue),
            ),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: onSearch,
            icon: Icon(
              searchOpen ? Icons.close_rounded : Icons.search_rounded,
              color: Brand.ink,
            ),
          ),
          Tooltip(
            message: gridView ? 'Show as list' : 'Show as grid',
            child: Material(
              color: Brand.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Brand.outline),
              ),
              child: InkWell(
                onTap: onToggleLayout,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    gridView
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    color: Brand.ink,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Brand.blue,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAdd,
              child: const Tooltip(
                message: 'Add',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Documents', style: BrandType.display),
          const SizedBox(height: 4),
          Text(
            '$count Document${count == 1 ? '' : 's'}',
            style: BrandType.caption,
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        cacheExtent: 800,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final name in DocumentFolder.chipNames)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                name: name,
                selected: selected == name,
                onTap: () => onSelected(name),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (name) {
    'All' => Icons.folder_rounded,
    'Invoices' => Icons.description_outlined,
    'Receipts' => Icons.receipt_long_outlined,
    'Notes' => Icons.edit_note_rounded,
    'ID Cards' => Icons.badge_outlined,
    _ => Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Brand.blue : Brand.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Brand.blue : Brand.outline),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                _icon,
                size: 16,
                color: selected ? Colors.white : Brand.grey,
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  color: selected ? Colors.white : Brand.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortFilterRow extends StatelessWidget {
  const _SortFilterRow({
    required this.sort,
    required this.filterActive,
    required this.onSort,
    required this.onFilter,
  });

  final DocumentSort sort;
  final bool filterActive;
  final ValueChanged<DocumentSort> onSort;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          PopupMenuButton<DocumentSort>(
            tooltip: 'Sort',
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              for (final option in DocumentSort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Sort by: ${sort.label}',
                    style: BrandType.caption.copyWith(
                      color: Brand.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18, color: Brand.grey),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onFilter,
            icon: Icon(
              Icons.filter_list_rounded,
              size: 18,
              color: filterActive ? Brand.blue : Brand.grey,
            ),
            label: Text(
              'Filter',
              style: BrandType.caption.copyWith(
                color: filterActive ? Brand.blue : Brand.grey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentListCard extends StatelessWidget {
  const _DocumentListCard({
    required this.document,
    required this.folderName,
    required this.highlighted,
    required this.onTap,
    required this.onMore,
    required this.onFavorite,
  });

  final Document document;
  final String folderName;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final pages = document.pageCount;
    final meta =
        '${DateFormat.yMMMd().format(document.createdAt)}  •  '
        '$pages Page${pages == 1 ? '' : 's'}  •  ${document.formattedSize}';

    return Material(
      color: Brand.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted ? Brand.blue : Brand.outline,
              width: highlighted ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Brand.ink.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(document: document, highlighted: highlighted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandType.title,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandType.caption,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.folder_outlined,
                            size: 14,
                            color: Brand.grey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BrandType.caption,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      tooltip: 'More',
                      onPressed: onMore,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_horiz_rounded, color: Brand.ink),
                    ),
                    IconButton(
                      tooltip: document.favorited
                          ? 'Remove from favorites'
                          : 'Favorite',
                      onPressed: onFavorite,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        document.favorited
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: document.favorited
                            ? const Color(0xFFF5B301)
                            : Brand.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentGridCard extends StatelessWidget {
  const _DocumentGridCard({
    required this.document,
    required this.folderName,
    required this.highlighted,
    required this.onTap,
    required this.onMore,
    required this.onFavorite,
  });

  final Document document;
  final String folderName;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: highlighted ? Brand.blue : Brand.outline,
                        width: highlighted ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: _Thumb(
                        document: document,
                        highlighted: highlighted,
                        fill: true,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'More',
                    onPressed: onMore,
                    icon: const Icon(Icons.more_horiz_rounded, color: Brand.ink),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: IconButton(
                    tooltip: 'Favorite',
                    onPressed: onFavorite,
                    icon: Icon(
                      document.favorited
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: document.favorited
                          ? const Color(0xFFF5B301)
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            document.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandType.title,
          ),
          Text(
            '${DateFormat.yMMMd().format(document.createdAt)}  •  '
            '${document.pageCount} Page${document.pageCount == 1 ? '' : 's'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandType.caption,
          ),
          Text(
            '${document.formattedSize}  •  $folderName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandType.caption,
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.document,
    required this.highlighted,
    this.fill = false,
  });

  final Document document;
  final bool highlighted;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final child = Stack(
      fit: StackFit.expand,
      children: [
        PageThumbnail(
          path: document.thumbnailPath,
          cacheWidth: fill ? 420 : 216,
          seed: document.id,
          fit: BoxFit.cover,
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: _TypeTag(label: document.typeLabel),
        ),
        if (highlighted)
          const Positioned(left: 6, top: 6, child: _NewBadge()),
      ],
    );
    if (fill) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 72, height: 92, child: child),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final pdf = label == 'PDF';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: pdf ? Brand.pdfRed : Brand.docBlue,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(40, 0, 40, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 48, color: Brand.greyLight),
            SizedBox(height: 16),
            Text('Nothing scanned yet', style: BrandType.title),
            SizedBox(height: 8),
            Text(
              'Tap + to scan a document or import from Gallery or Files. '
              'Everything stays on this device.',
              textAlign: TextAlign.center,
              style: BrandType.subtitle,
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 42, color: Brand.greyLight),
            SizedBox(height: 12),
            Text('No documents match', style: BrandType.subtitle),
          ],
        ),
      ),
    );
  }
}
