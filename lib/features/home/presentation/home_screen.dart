import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/haptics/app_haptics.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/theme/tactile.dart';
import 'package:scan2/core/widgets/illustrations.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/core/widgets/pressable_scale.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/ocr/presentation/ocr_flow.dart';
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
                onOcr: () => startOcrFlow(context, ref),
                onImport: () => importFilesAsDocument(
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
              SliverToBoxAdapter(
                child: _EmptyRecent(
                  onScanFirstPage: () => context.push('/camera'),
                ),
              )
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
          TactileIconButton(
            tooltip: 'Menu',
            onPressed: onOpenMenu,
            icon: Icons.menu_rounded,
            color: Brand.ink,
            size: 26,
          ),
          const Expanded(
            child: ScanellaWordmark(fontSize: BrandType.wordmarkCompact),
          ),
          TactileIconButton(
            tooltip: 'Scanella Pro',
            onPressed: () => _pro(context),
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFFE0A100),
          ),
          TactileIconButton(
            tooltip: 'Notifications',
            onPressed: () => _notifications(context),
            icon: Icons.notifications_none_rounded,
            color: Brand.ink,
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ActionCard(
                    title: 'Scan Document',
                    subtitle: 'Auto-edge any page with the camera.',
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
                    subtitle: 'Turn gallery photos into clean scans.',
                    icon: Icons.image_outlined,
                    background: const Color(0xFFE6F7ED),
                    accent: Brand.imageGreen,
                    onTap: onScanPhotos,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ActionCard(
                    title: 'OCR Text',
                    subtitle: 'Copy text from a photo or PDF.',
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
                    subtitle: 'Bring in images or PDFs from Files.',
                    icon: Icons.cloud_upload_outlined,
                    background: const Color(0xFFF3EBFF),
                    accent: const Color(0xFF7B61FF),
                    onTap: onImport,
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
    final radius = BorderRadius.circular(20);
    return PressableScale(
      onPressed: onTap,
      haptic: AppHaptic.impactLight,
      scale: Tactile.pressScaleCard,
      borderRadius: radius,
      child: Material(
        color: background,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandType.title,
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: BrandType.caption),
              const Spacer(),
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
            TactileTextButton(
              onPressed: onViewAll,
              style: BrandType.link,
              label: 'View All >',
            ),
        ],
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onScanFirstPage});

  final VoidCallback onScanFirstPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nothing scanned yet.', style: BrandType.subtitle),
          const SizedBox(height: 4),
          PressableScale(
            onPressed: onScanFirstPage,
            haptic: AppHaptic.impactLight,
            scale: Tactile.pressScaleCard,
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Scan first page', style: BrandType.link),
            ),
          ),
        ],
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

    final open = () => context.push('/library/document/${document.id}');
    final radius = BorderRadius.circular(16);
    return PressableScale(
      onPressed: open,
      haptic: AppHaptic.selection,
      scale: Tactile.pressScaleCard,
      hapticOnDown: false,
      borderRadius: radius,
      child: Material(
        color: Brand.surface,
        borderRadius: radius,
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
              TactileIconButton(
                tooltip: 'Open',
                onPressed: open,
                icon: Icons.more_vert_rounded,
                color: Brand.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
