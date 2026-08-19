import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/illustrations.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Scanella home: welcome banner, scan shortcuts, recent documents.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMenu,
    required this.onViewAllDocuments,
  });

  final VoidCallback onOpenMenu;
  final VoidCallback onViewAllDocuments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider).valueOrNull ?? const [];
    final recent = documents.take(3).toList();

    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TopBar(onOpenMenu: onOpenMenu)),
            const SliverToBoxAdapter(child: _WelcomeBanner()),
            SliverToBoxAdapter(
              child: _ActionGrid(
                onScanDocument: () => context.push('/camera'),
                onScanPhotos: () => importGalleryAsDocument(
                  context,
                  ref,
                  title: 'Photo scan',
                ),
                onOcr: () => _openOcr(context),
                onImport: () => importGalleryAsDocument(
                  context,
                  ref,
                  title: 'Imported files',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _RecentHeader(
                empty: recent.isEmpty,
                onViewAll: onViewAllDocuments,
              ),
            ),
            if (recent.isEmpty)
              const SliverToBoxAdapter(child: _EmptyRecent())
            else
              SliverList.separated(
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RecentRow(document: recent[index]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }

  void _openOcr(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OCR Text'),
        content: const Text(
          'Text extraction is not connected yet. You can still scan the page '
          'and keep the image.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/camera');
            },
            child: const Text('Scan anyway'),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpenMenu});

  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menu',
            onPressed: onOpenMenu,
            icon: const Icon(Icons.menu_rounded, color: Brand.ink, size: 26),
          ),
          const Expanded(
            child: ScanellaWordmark(fontSize: BrandType.wordmarkCompact),
          ),
          IconButton(
            tooltip: 'Scanella Pro',
            onPressed: () => _pro(context),
            icon: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFFE0A100),
              size: 24,
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _notifications(context),
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Brand.ink,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  void _pro(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scanella Pro'),
        content: const Text(
          'Pro extras are not for sale yet. Everything on this device is '
          'already included.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _notifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 36, color: Brand.grey),
            SizedBox(height: 12),
            Text("You're all caught up", style: BrandType.title),
            SizedBox(height: 6),
            Text(
              'Scanella keeps your documents on this device. There is nothing '
              'waiting for you.',
              textAlign: TextAlign.center,
              style: BrandType.subtitle,
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back!', style: BrandType.link),
                SizedBox(height: 6),
                Text(
                  "Let's scan something awesome today.",
                  style: BrandType.headline,
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 96,
            height: 88,
            child: ScannerDevice(),
          ),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onScanDocument,
    required this.onScanPhotos,
    required this.onOcr,
    required this.onImport,
  });

  final VoidCallback onScanDocument;
  final VoidCallback onScanPhotos;
  final VoidCallback onOcr;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  title: 'Scan Document',
                  subtitle: 'Scan any document to get started.',
                  icon: Icons.document_scanner_outlined,
                  background: const Color(0xFFE8F1FF),
                  accent: Brand.blue,
                  onTap: onScanDocument,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  title: 'Scan Photos',
                  subtitle: 'Scan photos in high quality.',
                  icon: Icons.image_outlined,
                  background: const Color(0xFFE6F7ED),
                  accent: Brand.imageGreen,
                  onTap: onScanPhotos,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  title: 'OCR Text',
                  subtitle: 'Extract text from images and documents.',
                  icon: Icons.text_fields_rounded,
                  background: const Color(0xFFFFF6E0),
                  accent: const Color(0xFFE8920A),
                  onTap: onOcr,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  title: 'Import Files',
                  subtitle: 'Import from gallery, files or cloud.',
                  icon: Icons.cloud_upload_outlined,
                  background: const Color(0xFFF3EBFF),
                  accent: const Color(0xFF7B61FF),
                  onTap: onImport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 14),
              Text(title, style: BrandType.title),
              const SizedBox(height: 4),
              Text(subtitle, style: BrandType.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.empty, required this.onViewAll});

  final bool empty;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Row(
        children: [
          const Text('Recent Documents', style: BrandType.title),
          const Spacer(),
          if (!empty)
            TextButton(
              onPressed: onViewAll,
              child: const Text('View All >', style: BrandType.link),
            ),
        ],
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        'Nothing scanned yet. Tap Scan Document to capture your first page.',
        style: BrandType.subtitle,
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(document.createdAt);
    final size = documentSizeLabel(document.pagePaths, document.pageCount);

    return Material(
      color: Brand.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/library/document/${document.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 48,
                  height: 58,
                  child: PageThumbnail(
                    path: document.pages.isEmpty
                        ? null
                        : document.pages.first.path,
                    cacheWidth: 144,
                    seed: document.id,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                      '$date  |  $size',
                      style: BrandType.caption,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open',
                onPressed: () =>
                    context.push('/library/document/${document.id}'),
                icon: const Icon(Icons.more_vert_rounded, color: Brand.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
