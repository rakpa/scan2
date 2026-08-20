import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/page_thumbnail.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Screen 11: confirmation after a scan is filed locally.
class DocumentSavedScreen extends ConsumerWidget {
  const DocumentSavedScreen({super.key, required this.documentId});

  final int documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentProvider(documentId)).valueOrNull;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          child: document == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _TopBar(onBack: () => context.go('/library')),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF22C55E),
                      size: 44,
                    ),
                    const SizedBox(height: 8),
                    Text('Document saved', style: BrandType.headline),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        document.fileName,
                        textAlign: TextAlign.center,
                        style: BrandType.body.copyWith(
                          color: Brand.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _PreviewCard(document: document),
                      ),
                    ),
                    _MetaStrip(document: document),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: () => context.go('/library'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brand.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: BrandType.button.copyWith(fontSize: 17),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
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
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Brand.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Brand.ink.withValues(alpha: 0.10),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: PageThumbnail(
                  path: document.thumbnailPath,
                  cacheWidth: 900,
                  seed: document.id,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final created = DateFormat.yMMMd().add_jm().format(document.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _Chip(
            icon: Icons.insert_drive_file_outlined,
            label: document.documentType,
          ),
          _Chip(
            icon: Icons.layers_outlined,
            label:
                '${document.pageCount} page${document.pageCount == 1 ? '' : 's'}',
          ),
          _Chip(icon: Icons.sd_storage_outlined, label: document.formattedSize),
          _Chip(icon: Icons.calendar_today_outlined, label: created),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Brand.blue),
          const SizedBox(width: 6),
          Text(
            label,
            style: BrandType.caption.copyWith(
              color: Brand.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
