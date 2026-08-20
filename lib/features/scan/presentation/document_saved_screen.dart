import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/document_folder.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/library/domain/library_launch.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Screen 11: confirmation after a scan is filed locally.
class DocumentSavedScreen extends ConsumerStatefulWidget {
  const DocumentSavedScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentSavedScreen> createState() =>
      _DocumentSavedScreenState();
}

class _DocumentSavedScreenState extends ConsumerState<DocumentSavedScreen> {
  static const _exporter = ExportService();

  bool _busy = false;
  String _busyLabel = '';

  DocumentStore? get _store {
    final repo = ref.read(documentRepositoryProvider);
    return repo is DocumentStore ? repo : null;
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentProvider(widget.documentId)).valueOrNull;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.canvas,
        body: SafeArea(
          child: document == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    Column(
                      children: [
                        _TopBar(
                          onBack: _goHome,
                          onDone: _goHome,
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            children: [
                              const _SuccessCard(),
                              const SizedBox(height: 14),
                              _InfoCard(
                                document: document,
                                onRename: () => _rename(document),
                                onMore: () => _more(document),
                              ),
                              const SizedBox(height: 14),
                              _PreviewCard(document: document),
                              const SizedBox(height: 16),
                              _ActionRow(
                                onShare: () => _run(
                                  'Preparing PDF…',
                                  () => _exporter.sharePdf(document),
                                ),
                                onSaveToFiles: () => _saveToFiles(document),
                                onSaveToGallery: () => _saveToGallery(document),
                                onPrint: () => _run(
                                  'Preparing print…',
                                  () => _exporter.printPdf(document),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _LocationRow(
                                folderName: _folderName(document),
                                onChange: () => _changeFolder(document),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: () => _goDocuments(document.id),
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
                              child: const Text('View in Documents'),
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

  String _folderName(Document document) {
    final store = _store;
    final folder = store?.folderById(document.folderId);
    return folder?.name ?? 'Invoices';
  }

  void _goHome() {
    context.go('/library', extra: const LibraryLaunch());
  }

  void _goDocuments(int documentId) {
    context.go(
      '/library',
      extra: LibraryLaunch(tab: 1, highlightDocumentId: documentId),
    );
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

  Future<void> _rename(Document document) async {
    final name = await _promptName(
      title: 'Rename',
      initial: document.title,
      confirm: 'Save',
    );
    if (name == null || name == document.title || !mounted) return;
    await ref.read(documentRepositoryProvider).renameDocument(
      document.id,
      name,
    );
    bumpLibrary(ref);
  }

  Future<void> _changeFolder(Document document) async {
    final store = _store;
    List<DocumentFolder> folders = DocumentFolder.defaults;
    try {
      final loaded = store == null ? null : await store.getFolders();
      if (loaded != null && loaded.isNotEmpty) folders = loaded;
    } catch (_) {
      // Tests and web have no documents directory; the default categories still
      // let the user pick a destination.
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Brand.surface,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text('Move to folder', style: BrandType.title),
                ),
                for (final folder in folders)
                  ListTile(
                    leading: Icon(
                      folder.id ==
                              (document.folderId ?? DocumentFolder.invoicesId)
                          ? Icons.folder
                          : Icons.folder_outlined,
                      color: Brand.blue,
                    ),
                    title: Text(folder.name),
                    trailing:
                        folder.id ==
                            (document.folderId ?? DocumentFolder.invoicesId)
                        ? const Icon(Icons.check_rounded, color: Brand.blue)
                        : null,
                    onTap: () => Navigator.pop(ctx, folder),
                  ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New folder'),
                  onTap: () => Navigator.pop(ctx, 'new'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;

    if (chosen == 'new') {
      final name = await _promptName(
        title: 'New folder',
        initial: '',
        confirm: 'Create',
      );
      if (name == null || store == null || !mounted) return;
      final folder = await store.createFolder(name);
      await store.setDocumentFolder(document.id, folder.id);
      bumpLibrary(ref);
      return;
    }

    if (chosen is DocumentFolder) {
      if (store == null) return;
      await store.setDocumentFolder(document.id, chosen.id);
      bumpLibrary(ref);
    }
  }

  Future<void> _more(Document document) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
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
      case 'duplicate':
        await _duplicate(document);
      case 'delete':
        await _delete(document);
    }
  }

  Future<void> _duplicate(Document document) async {
    final store = _store;
    if (store == null) {
      _toast('Duplicate is available on device.');
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Duplicating…';
    });
    try {
      final copy = await store.duplicateDocument(document.id);
      bumpLibrary(ref);
      if (mounted && copy != null) {
        _toast('Duplicated as ${copy.title}');
      }
    } catch (e) {
      if (mounted) _toast(_readable(e));
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
    if (mounted) _goHome();
  }

  Future<String?> _promptName({
    required String title,
    required String initial,
    required String confirm,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
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
            child: Text(confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  void _toast(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _readable(Object error) {
    final text = error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onDone});

  final VoidCallback onBack;
  final VoidCallback onDone;

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
              icon: const Icon(Icons.chevron_left_rounded, size: 32),
              color: Brand.blue,
            ),
            const Expanded(
              child: Center(
                child: ScanellaWordmark(fontSize: 22, color: Brand.blue),
              ),
            ),
            TextButton(
              onPressed: onDone,
              child: Text(
                'Done',
                style: BrandType.button.copyWith(
                  color: Brand.blue,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
      child: const Row(
        children: [
          _GreenCheck(),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Document Saved!', style: BrandType.title),
                SizedBox(height: 4),
                Text(
                  'Your document has been saved successfully.',
                  style: BrandType.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GreenCheck extends StatelessWidget {
  const _GreenCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.document,
    required this.onRename,
    required this.onMore,
  });

  final Document document;
  final VoidCallback onRename;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final pages = document.pageCount;
    final meta =
        '${DateFormat.yMMMd().format(document.createdAt)}  ·  '
        '$pages Page${pages == 1 ? '' : 's'}  ·  ${document.formattedSize}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.outline),
      ),
      child: Row(
        children: [
          const _PdfBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandType.title,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rename',
                      onPressed: onRename,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Brand.blue,
                      ),
                    ),
                  ],
                ),
                Text(meta, style: BrandType.caption),
              ],
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded, color: Brand.ink),
          ),
        ],
      ),
    );
  }
}

class _PdfBadge extends StatelessWidget {
  const _PdfBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 46,
            decoration: BoxDecoration(
              color: Brand.canvas,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Brand.outline),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 20,
              color: Brand.grey,
            ),
          ),
          Positioned(
            left: 10,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Brand.pdfRed,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.outline),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: PageThumbnail(
          path: document.thumbnailPath,
          cacheWidth: 900,
          seed: document.id,
          fit: BoxFit.contain,
        ),
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
  });

  final VoidCallback onShare;
  final VoidCallback onSaveToFiles;
  final VoidCallback onSaveToGallery;
  final VoidCallback onPrint;

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
          icon: Icons.download_rounded,
          color: Brand.imageGreen,
          label: 'Save to Files',
          onTap: onSaveToFiles,
        ),
        _ActionTile(
          icon: Icons.photo_outlined,
          color: const Color(0xFF7C3AED),
          label: 'Save to Gallery',
          onTap: onSaveToGallery,
        ),
        _ActionTile(
          icon: Icons.print_outlined,
          color: Brand.grey,
          label: 'Print',
          onTap: onPrint,
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
        padding: const EdgeInsets.symmetric(horizontal: 4),
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
              height: 78,
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
                      fontSize: 11,
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

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.folderName, required this.onChange});

  final String folderName;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: Brand.blue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved in:',
                  style: BrandType.caption.copyWith(fontSize: 12),
                ),
                Text(
                  'My Documents > $folderName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandType.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(
              'Change',
              style: BrandType.link.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
