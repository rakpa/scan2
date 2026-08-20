import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/document_folder.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/library/domain/library_launch.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Screen 13: details, preview and local actions for one saved document.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  static const _exporter = ExportService();
  static final _stamp = DateFormat('MMM d, y, h:mm a');
  static final _day = DateFormat.yMMMd();

  final PageController _pager = PageController();
  int _pageIndex = 0;
  bool _busy = false;
  String _busyLabel = '';
  String _dimensions = '—';

  DocumentStore? get _store {
    final repo = ref.read(documentRepositoryProvider);
    return repo is DocumentStore ? repo : null;
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentProvider(widget.documentId)).valueOrNull;
    if (document != null) {
      final key = document.thumbnailPath;
      if (key != null && key != _dimensionKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadDimensions(document);
        });
      }
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          child: document == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    Column(
                      children: [
                        _TopBar(
                          onBack: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(
                                '/library',
                                extra: const LibraryLaunch(tab: 1),
                              );
                            }
                          },
                          onEdit: () => _edit(document),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            child: Column(
                              children: [
                                _SummaryHeader(
                                  document: document,
                                  folderName: _folderName(document),
                                  dayLabel: _day.format(document.createdAt),
                                  onRename: () => _rename(document),
                                  onFavorite: () => _toggleFavorite(document),
                                ),
                                const SizedBox(height: 16),
                                _Viewer(
                                  document: document,
                                  pageIndex: _pageIndex,
                                  controller: _pager,
                                  onPage: (i) => setState(() => _pageIndex = i),
                                  onFullscreen: () =>
                                      _fullscreen(document, _pageIndex),
                                ),
                                const SizedBox(height: 16),
                                _InfoCard(
                                  document: document,
                                  dimensions: _dimensions,
                                  created: _stamp.format(document.createdAt),
                                  modified: _stamp.format(document.lastModified),
                                ),
                                const SizedBox(height: 16),
                                _ActionRow(
                                  onShare: () => _run(
                                    'Preparing PDF…',
                                    () => _exporter.sharePdf(document),
                                  ),
                                  onSaveToFiles: () => _saveToFiles(document),
                                  onSaveToGallery: () =>
                                      _saveToGallery(document),
                                  onPrint: () => _run(
                                    'Preparing print…',
                                    () => _exporter.printPdf(document),
                                  ),
                                  onMore: () => _more(document),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: () => _openWith(document),
                              style: FilledButton.styleFrom(
                                backgroundColor: Brand.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: BrandType.button.copyWith(
                                  fontSize: 17,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.insert_drive_file_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('Open with'),
                                  SizedBox(width: 4),
                                  Icon(Icons.expand_more_rounded, size: 22),
                                ],
                              ),
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
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                                if (_busyLabel.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _busyLabel,
                                    style: BrandType.body.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  String? _dimensionKey;

  Future<void> _loadDimensions(Document document) async {
    final key = document.thumbnailPath;
    if (key == null || key == _dimensionKey) return;
    _dimensionKey = key;
    if (kIsWeb) return;
    try {
      final bytes = await File(key).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted || decoded == null) return;
      setState(() => _dimensions = '${decoded.width} x ${decoded.height}');
    } catch (_) {
      if (mounted) setState(() => _dimensions = '—');
    }
  }

  String _folderName(Document document) {
    final folder = _store?.folderById(document.folderId);
    if (folder != null) return folder.name;
    for (final item in DocumentFolder.defaults) {
      if (item.id == document.folderId) return item.name;
    }
    return 'Invoices';
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    if (kIsWeb) {
      _toast('This action is available on a device.');
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(_readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToFiles(Document document) async {
    await _run('Saving PDF…', () async {
      final saved = await _exporter.savePdfToFiles(document);
      if (saved && mounted) _toast('PDF saved to Files');
    });
  }

  Future<void> _saveToGallery(Document document) async {
    await _run('Saving to Gallery…', () async {
      final saved = await _exporter.saveToPhotos(document);
      if (mounted) {
        _toast('Saved $saved page${saved == 1 ? '' : 's'} to Gallery');
      }
    });
  }

  Future<void> _openWith(Document document) async {
    await _run('Opening…', () => _exporter.sharePdf(document));
  }

  Future<void> _toggleFavorite(Document document) async {
    final store = _store;
    if (store == null) return;
    await store.setFavorited(document.id, !document.favorited);
    bumpLibrary(ref);
  }

  Future<void> _edit(Document document) async {
    if (document.pages.isEmpty) {
      _toast('This document has no pages to edit.');
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Opening editor…';
    });
    try {
      final drafts = <ScanResultPageDraft>[];
      for (final page in document.pages) {
        Uint8List bytes;
        try {
          bytes = await File(page.path).readAsBytes();
        } catch (_) {
          continue;
        }
        if (bytes.isEmpty) continue;
        final originalExists =
            page.originalPath != null &&
            File(page.originalPath!).existsSync();
        drafts.add(
          ScanResultPageDraft(
            originalPath: originalExists ? page.originalPath! : page.path,
            bytes: bytes,
            quad: originalExists ? page.quad : const Quad.fullFrame(),
            adjustments: originalExists
                ? page.adjustments
                : const ScanAdjustments(),
          ),
        );
      }
      if (!mounted) return;
      if (drafts.isEmpty) {
        _toast('Could not load this document.');
        return;
      }
      await context.push(
        '/scan-result',
        extra: ScanResultArgs(
          pages: drafts,
          existingDocumentId: document.id,
        ),
      );
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
      case 'delete':
        await _delete(document);
    }
  }

  Future<void> _move(Document document) async {
    final folders = (_store?.cachedFolders?.isNotEmpty ?? false)
        ? _store!.cachedFolders!
        : DocumentFolder.defaults;
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
                    leading: const Icon(
                      Icons.folder_outlined,
                      color: Brand.blue,
                    ),
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
    await _run('Duplicating…', () async {
      final copy = await store.duplicateDocument(document.id);
      bumpLibrary(ref);
      if (mounted && copy != null) _toast('Duplicated as ${copy.title}');
    });
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
    if (!mounted) return;
    context.go('/library', extra: const LibraryLaunch(tab: 1));
  }

  void _fullscreen(Document document, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenViewer(
          document: document,
          initialIndex: index,
        ),
      ),
    );
  }

  String _readable(Object error) {
    final text = error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  void _toast(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onEdit});

  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, color: Brand.blue),
              iconSize: 32,
            ),
            const Expanded(
              child: Text(
                'Document Details',
                textAlign: TextAlign.center,
                style: BrandType.title,
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: Text(
                'Edit',
                style: BrandType.link.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.document,
    required this.folderName,
    required this.dayLabel,
    required this.onRename,
    required this.onFavorite,
  });

  final Document document;
  final String folderName;
  final String dayLabel;
  final VoidCallback onRename;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final pages = document.pageCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FileGlyph(label: document.typeLabel),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onRename,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        document.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandType.title,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Brand.greyLight,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.folder_rounded,
                    size: 14,
                    color: Brand.imageGreen,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandType.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$dayLabel  •  $pages Page${pages == 1 ? '' : 's'}  •  '
                '${document.formattedSize}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandType.caption,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: document.favorited
              ? 'Remove from favorites'
              : 'Favorite',
          onPressed: onFavorite,
          icon: Icon(
            document.favorited ? Icons.star_rounded : Icons.star_border_rounded,
            color: document.favorited
                ? const Color(0xFFF5B301)
                : Brand.grey,
          ),
        ),
      ],
    );
  }
}

class _FileGlyph extends StatelessWidget {
  const _FileGlyph({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final pdf = label == 'PDF';
    return Container(
      width: 44,
      height: 52,
      decoration: BoxDecoration(
        color: (pdf ? Brand.pdfRed : Brand.docBlue).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_rounded,
            color: pdf ? Brand.pdfRed : Brand.docBlue,
            size: 22,
          ),
          Text(
            label,
            style: TextStyle(
              color: pdf ? Brand.pdfRed : Brand.docBlue,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({
    required this.document,
    required this.pageIndex,
    required this.controller,
    required this.onPage,
    required this.onFullscreen,
  });

  final Document document;
  final int pageIndex;
  final PageController controller;
  final ValueChanged<int> onPage;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final count = document.pageCount;
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.outline),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: count,
            onPageChanged: onPage,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: _PageImage(
                  path: document.pages[index].path,
                  seed: document.id + index,
                ),
              );
            },
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EDF5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${pageIndex + 1} of $count',
                style: BrandType.caption.copyWith(
                  color: Brand.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: 'Fullscreen',
              onPressed: onFullscreen,
              icon: const Icon(
                Icons.open_in_full_rounded,
                color: Brand.grey,
                size: 20,
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == pageIndex
                            ? Brand.blue
                            : Brand.outline,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.path, required this.seed});

  final String path;
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return PageThumbnail(path: path, seed: seed, fit: BoxFit.contain);
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) =>
          PageThumbnail(path: path, seed: seed, fit: BoxFit.contain),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.document,
    required this.dimensions,
    required this.created,
    required this.modified,
  });

  final Document document;
  final String dimensions;
  final String created;
  final String modified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Document Information', style: BrandType.title),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InfoCell(
                  label: 'File Type',
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 16,
                        color: document.typeLabel == 'PDF'
                            ? Brand.pdfRed
                            : Brand.docBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(document.typeLabel, style: BrandType.body),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _InfoCell(
                  label: 'Pages',
                  value: '${document.pageCount}',
                ),
              ),
              Expanded(
                child: _InfoCell(label: 'Dimensions', value: dimensions),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InfoCell(
                  label: 'File Size',
                  value: document.formattedSize,
                ),
              ),
              Expanded(child: _InfoCell(label: 'Created', value: created)),
              Expanded(child: _InfoCell(label: 'Modified', value: modified)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: BrandType.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 4),
          child ??
              Text(
                value ?? '—',
                style: BrandType.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onShare,
    required this.onSaveToFiles,
    required this.onSaveToGallery,
    required this.onPrint,
    required this.onMore,
  });

  final VoidCallback onShare;
  final VoidCallback onSaveToFiles;
  final VoidCallback onSaveToGallery;
  final VoidCallback onPrint;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionTile(
          icon: Icons.ios_share_rounded,
          color: Brand.blue,
          label: 'Share',
          onTap: onShare,
        ),
        _ActionTile(
          icon: Icons.folder_rounded,
          color: Brand.imageGreen,
          label: 'Save to Files',
          onTap: onSaveToFiles,
        ),
        _ActionTile(
          icon: Icons.photo_outlined,
          color: const Color(0xFFEA4C89),
          label: 'Save to Gallery',
          onTap: onSaveToGallery,
        ),
        _ActionTile(
          icon: Icons.print_outlined,
          color: const Color(0xFF7C3AED),
          label: 'Print',
          onTap: onPrint,
        ),
        _ActionTile(
          icon: Icons.more_horiz_rounded,
          color: Brand.blue,
          label: 'More',
          onTap: onMore,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: Brand.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Brand.outline),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 86,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Brand.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenViewer extends StatefulWidget {
  const _FullscreenViewer({
    required this.document,
    required this.initialIndex,
  });

  final Document document;
  final int initialIndex;

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: document.pageCount,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: _PageImage(
                      path: document.pages[index].path,
                      seed: document.id + index,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 8,
              top: 4,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: Text(
                '${_index + 1} of ${document.pageCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
