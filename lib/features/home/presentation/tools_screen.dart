import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/haptics/app_haptics.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/theme/tactile.dart';
import 'package:scan2/core/widgets/pressable_scale.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/ocr/presentation/ocr_flow.dart';

/// Shortcuts that do not live on the home grid.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
          children: [
            const Text('Tools', style: BrandType.headline),
            const SizedBox(height: 6),
            const Text(
              'Extra ways to capture and bring files in.',
              style: BrandType.subtitle,
            ),
            const SizedBox(height: 22),
            _ToolTile(
              icon: Icons.document_scanner_outlined,
              color: Brand.blue,
              title: 'Scan Document',
              subtitle: 'System auto-edge scan — the default capture path.',
              onTap: () => context.push('/camera'),
            ),
            _ToolTile(
              icon: Icons.photo_library_outlined,
              color: Brand.imageGreen,
              title: 'Scan Photos',
              subtitle: 'Turn gallery photos into clean scans.',
              onTap: () => importGalleryAsDocument(
                context,
                ref,
                title: 'Photo scan',
              ),
            ),
            _ToolTile(
              icon: Icons.text_fields_rounded,
              color: const Color(0xFFE8920A),
              title: 'OCR Text',
              subtitle: 'Copy text from a photo, scan, or PDF.',
              onTap: () => startOcrFlow(context, ref),
            ),
            _ToolTile(
              icon: Icons.folder_open_outlined,
              color: const Color(0xFF7B61FF),
              title: 'Import Files',
              subtitle: 'Bring in images or PDFs from Files.',
              onTap: () => importFilesAsDocument(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onPressed: onTap,
        haptic: AppHaptic.impactLight,
        scale: Tactile.pressScaleCard,
        borderRadius: radius,
        child: Material(
          color: Brand.surface,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: BrandType.title),
                      const SizedBox(height: 2),
                      Text(subtitle, style: BrandType.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Brand.greyLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
