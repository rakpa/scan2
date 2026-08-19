import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/export_service.dart';

/// What the user picked in the export sheet.
enum ExportAction { savePdfToFiles, saveToPhotos, sharePdf, shareImages }

/// Bottom sheet listing the ways a document can leave the app.
///
/// Previously export was two unlabelled icons in the app bar that dropped
/// straight into the system share sheet, which gave no indication that saving
/// a PDF or writing to Photos was possible at all.
class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key, required this.document});

  final Document document;

  static Future<ExportAction?> show(BuildContext context, Document document) {
    return showModalBottomSheet<ExportAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ExportSheet(document: document),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = document.pageCount;
    final pageLabel = '$pageCount page${pageCount == 1 ? '' : 's'}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(document.title, style: BrandType.title),
                  const SizedBox(height: 2),
                  Text(pageLabel, style: BrandType.caption),
                ],
              ),
            ),
            _ExportTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Save PDF to Files',
              subtitle: '$pageLabel in one document',
              action: ExportAction.savePdfToFiles,
              highlighted: true,
            ),
            _ExportTile(
              icon: Icons.photo_library_outlined,
              title: 'Save to Photos',
              subtitle: 'Adds the pages to a Scan2 album',
              action: ExportAction.saveToPhotos,
            ),
            const Divider(indent: 16, endIndent: 16),
            _ExportTile(
              icon: Icons.ios_share,
              title: 'Share PDF',
              subtitle: 'Mail, Messages, or another app',
              action: ExportAction.sharePdf,
            ),
            _ExportTile(
              icon: Icons.image_outlined,
              title: 'Share page images',
              subtitle: 'JPEG per page',
              action: ExportAction.shareImages,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ExportAction action;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: highlighted ? Brand.blue : Brand.canvas,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 21,
          color: highlighted ? Colors.white : Brand.grey,
        ),
      ),
      title: Text(title, style: BrandType.title),
      subtitle: Text(subtitle, style: BrandType.caption),
      onTap: () => Navigator.pop(context, action),
    );
  }
}

/// Runs [action] for [document], returning a message to show the user.
///
/// Errors are returned rather than swallowed: an export that quietly does
/// nothing is indistinguishable from a broken button.
Future<String> runExportAction(
  ExportAction action,
  Document document,
  ExportService exporter,
) async {
  switch (action) {
    case ExportAction.savePdfToFiles:
      await exporter.savePdfToFiles(document);
      return 'Choose a location to save the PDF';
    case ExportAction.saveToPhotos:
      final saved = await exporter.saveToPhotos(document);
      return 'Saved $saved page${saved == 1 ? '' : 's'} to Photos';
    case ExportAction.sharePdf:
      await exporter.sharePdf(document);
      return '';
    case ExportAction.shareImages:
      await exporter.shareImages(document);
      return '';
  }
}
