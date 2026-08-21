import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/native_document_scanner.dart';
import 'package:scan2/features/library/domain/gallery_import.dart';
import 'package:scan2/features/ocr/domain/ocr_args.dart';
import 'package:scan2/features/ocr/domain/on_device_ocr.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

/// Opens a full source sheet, then runs on-device OCR on the chosen pages.
Future<void> startOcrFlow(
  BuildContext context,
  WidgetRef ref, {
  OnDeviceOcr? ocr,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OCR is available on a device.')),
    );
    return;
  }

  final source = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Brand.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const OcrSourceSheet(),
  );
  if (source == null || !context.mounted) return;

  List<String> paths;
  var options = ImportPrepareOptions.photos;
  try {
    switch (source) {
      case 'scan':
        paths = await const NativeDocumentScanner().scan() ?? const [];
        options = ImportPrepareOptions.files;
      case 'photos':
        final files = await ImagePicker().pickMultiImage();
        paths = [for (final file in files) file.path];
        options = ImportPrepareOptions.photos;
      case 'files':
        paths = await _pickOcrFiles();
        options = ImportPrepareOptions.files;
      default:
        return;
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return;
  }

  if (!context.mounted) return;
  if (paths.isEmpty) return;

  await recognizeAndOpen(
    context,
    ref,
    paths: paths,
    options: options,
    ocr: ocr ?? OnDeviceOcr(),
  );
}

/// Prepares pages, reads text, and opens the OCR result screen.
Future<void> recognizeAndOpen(
  BuildContext context,
  WidgetRef ref, {
  required List<String> paths,
  required ImportPrepareOptions options,
  OnDeviceOcr? ocr,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final filter = ref.read(settingsProvider).defaultFilter;
    final processed = await prepareImportPages(
      paths: paths,
      filter: filter,
      options: options,
    );
    if (processed.isEmpty) {
      throw StateError('Nothing to read text from.');
    }

    final recognizer = ocr ?? OnDeviceOcr();
    final pages = <OcrPageResult>[];
    for (final page in processed) {
      final text = await recognizer.recognize(page.bytes);
      pages.add(OcrPageResult(page: page, text: text));
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    context.push('/ocr-result', extra: OcrArgs(pages: pages));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not read text: $e')));
  }
}

Future<List<String>> _pickOcrFiles() async {
  final picked = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'heic',
      'heif',
      'webp',
      'pdf',
    ],
    withData: true,
  );
  final files = picked?.files ?? const [];
  final paths = <String>[];
  for (final file in files) {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      paths.add(path);
      continue;
    }
    final bytes = file.bytes;
    if (bytes == null) continue;
    final temp = File(
      '${Directory.systemTemp.path}/scanella_ocr_'
      '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
    );
    await temp.writeAsBytes(bytes, flush: true);
    paths.add(temp.path);
  }
  return paths;
}

/// Source picker shown for OCR. Public so widget tests can pump it.
class OcrSourceSheet extends StatelessWidget {
  const OcrSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: double.infinity),
                  Text('OCR Text', style: BrandType.title),
                  SizedBox(height: 4),
                  Text(
                    'Scan a page or pick a photo. Text stays on this device.',
                    style: BrandType.caption,
                  ),
                ],
              ),
            ),
            _OcrSourceTile(
              icon: Icons.document_scanner_outlined,
              color: Brand.blue,
              title: 'Scan page',
              subtitle: 'Use the system scanner, then extract the text.',
              value: 'scan',
            ),
            _OcrSourceTile(
              icon: Icons.photo_outlined,
              color: Brand.imageGreen,
              title: 'Choose photos',
              subtitle: 'Pick pictures of a page from the gallery.',
              value: 'photos',
            ),
            _OcrSourceTile(
              icon: Icons.folder_open_outlined,
              color: const Color(0xFF7B61FF),
              title: 'Import files',
              subtitle: 'Images or PDFs from Files.',
              value: 'files',
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrSourceTile extends StatelessWidget {
  const _OcrSourceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: BrandType.title),
      subtitle: Text(subtitle, style: BrandType.caption),
      onTap: () => Navigator.pop(context, value),
    );
  }
}
