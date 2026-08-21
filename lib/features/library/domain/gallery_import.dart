import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

/// How an imported image should be prepared before review.
class ImportPrepareOptions {
  const ImportPrepareOptions({
    this.detectEdges = true,
    this.applySpreadSnip = true,
  });

  /// Photos of a page on a desk still need a crop. Files that are already
  /// scans or PDFs must not be cropped a second time into the content.
  final bool detectEdges;
  final bool applySpreadSnip;

  static const photos = ImportPrepareOptions(
    detectEdges: true,
    applySpreadSnip: true,
  );

  static const files = ImportPrepareOptions(
    detectEdges: false,
    applySpreadSnip: false,
  );
}

/// Picks photos, prepares them as scans, then opens the review editor.
///
/// Previously this saved a cropped JPEG straight into the library, so Scan
/// Photos never had its own flow — it dumped the user onto a finished crop.
Future<void> importGalleryAsDocument(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Photo scan',
}) async {
  if (!_importAvailable(context)) return;

  final files = await ImagePicker().pickMultiImage();
  if (files.isEmpty || !context.mounted) return;

  await _prepareAndReview(
    context,
    ref,
    paths: [for (final file in files) file.path],
    options: ImportPrepareOptions.photos,
    emptyMessage: 'No photos were selected.',
  );
}

/// Picks images or PDFs from Files, keeps them uncropped, then opens review.
Future<void> importFilesAsDocument(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Imported files',
}) async {
  if (!_importAvailable(context)) return;

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
  if (files.isEmpty || !context.mounted) return;

  final paths = <String>[];
  for (final file in files) {
    final resolved = await _materializePickedFile(file);
    if (resolved != null) paths.add(resolved);
  }

  await _prepareAndReview(
    context,
    ref,
    paths: paths,
    options: ImportPrepareOptions.files,
    emptyMessage: 'No images or PDFs were selected.',
  );
}

/// Turns image/PDF paths into processed pages using [options].
Future<List<ProcessedPage>> prepareImportPages({
  required List<String> paths,
  required ScanFilter filter,
  ImportPrepareOptions options = ImportPrepareOptions.photos,
  Future<List<String>> Function(String pdfPath)? rasterizePdf,
}) async {
  const processor = PageProcessor();
  final rasterize = rasterizePdf ?? rasterizePdfToPngs;
  final processed = <ProcessedPage>[];

  for (final path in paths) {
    final imagePaths = isPdfPath(path) ? await rasterize(path) : [path];
    for (final imagePath in imagePaths) {
      final result = await processor.process(
        imagePath: imagePath,
        detectEdges: options.detectEdges,
        applySpreadSnip: options.applySpreadSnip,
        adjustments: ScanAdjustments(filter: filter),
      );
      processed.add(
        ProcessedPage(
          originalPath: imagePath,
          bytes: result.bytes,
          quad: result.quad ?? const Quad.fullFrame(),
          adjustments: result.adjustments,
        ),
      );
    }
  }
  return processed;
}

/// Renders each PDF page to a PNG the scan pipeline can open.
Future<List<String>> rasterizePdfToPngs(String pdfPath) async {
  final bytes = await File(pdfPath).readAsBytes();
  final out = <String>[];
  var index = 0;
  await for (final page in Printing.raster(bytes, dpi: 140)) {
    final png = await page.toPng();
    final file = File(
      '${Directory.systemTemp.path}/scanella_pdf_'
      '${DateTime.now().microsecondsSinceEpoch}_$index.png',
    );
    await file.writeAsBytes(png, flush: true);
    out.add(file.path);
    index++;
    if (index >= 24) break;
  }
  return out;
}

bool isPdfPath(String path) => path.toLowerCase().endsWith('.pdf');

/// Human-readable size for a saved document. Falls back to page count when
/// the files are missing (the browser demo, or a deleted page).
String documentSizeLabel(Iterable<String> pagePaths, int pageCount) {
  if (kIsWeb) {
    return '$pageCount page${pageCount == 1 ? '' : 's'}';
  }
  var bytes = 0;
  for (final path in pagePaths) {
    try {
      bytes += File(path).lengthSync();
    } catch (_) {}
  }
  if (bytes <= 0) {
    return '$pageCount page${pageCount == 1 ? '' : 's'}';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).round()} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

bool _importAvailable(BuildContext context) {
  if (!kIsWeb) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Import is available on a device.')),
    );
  return false;
}

Future<void> _prepareAndReview(
  BuildContext context,
  WidgetRef ref, {
  required List<String> paths,
  required ImportPrepareOptions options,
  required String emptyMessage,
}) async {
  if (paths.isEmpty || !context.mounted) return;

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
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (processed.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(emptyMessage)));
      return;
    }

    goToScanResult(context, processed, allowRetake: false);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not import: $e')));
  }
}

Future<String?> _materializePickedFile(PlatformFile file) async {
  final path = file.path;
  if (path != null && path.isNotEmpty) return path;
  final bytes = file.bytes;
  if (bytes == null) return null;
  final name = file.name.isEmpty ? 'import.bin' : file.name;
  final temp = File(
    '${Directory.systemTemp.path}/scanella_import_'
    '${DateTime.now().microsecondsSinceEpoch}_$name',
  );
  await temp.writeAsBytes(bytes, flush: true);
  return temp.path;
}
