import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

/// Imports one or more photos from the gallery as a new document.
///
/// Photos of a page on a desk or in a book stand are cropped and enhanced
/// the same way a camera capture is. Saving the original JPEG left the
/// holder, the table and any other books in the frame.
Future<void> importGalleryAsDocument(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Imported files',
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Import is available on a device.')),
      );
    return;
  }

  final files = await ImagePicker().pickMultiImage();
  if (files.isEmpty || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final repository = ref.read(documentRepositoryProvider);
    if (repository is! DocumentStore) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      context.push('/library');
      return;
    }

    const processor = PageProcessor();
    final filter = ref.read(settingsProvider).defaultFilter;
    final processed = <ProcessedPage>[];
    for (final file in files) {
      final result = await processor.process(
        imagePath: file.path,
        adjustments: ScanAdjustments(filter: filter),
      );
      processed.add(
        ProcessedPage(
          originalPath: file.path,
          bytes: result.bytes,
          quad: result.quad ?? const Quad.fullFrame(),
          adjustments: result.adjustments,
        ),
      );
    }

    final doc = await repository.createProcessedDocument(
      pages: processed,
      title: title,
    );
    bumpLibrary(ref);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    context.push('/library/document/${doc.id}');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not import: $e')));
  }
}

/// Picks images (and PDFs) from the system Files UI and files them locally.
Future<void> importFilesAsDocument(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Imported files',
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Import is available on a device.')),
      );
    return;
  }

  final picked = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
  );
  final files = picked?.files ?? const [];
  if (files.isEmpty || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final repository = ref.read(documentRepositoryProvider);
    if (repository is! DocumentStore) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }

    const processor = PageProcessor();
    final filter = ref.read(settingsProvider).defaultFilter;
    final processed = <ProcessedPage>[];
    for (final file in files) {
      var path = file.path;
      if (path == null || path.isEmpty) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final temp = File(
          '${Directory.systemTemp.path}/scanella_import_${file.name}',
        );
        await temp.writeAsBytes(bytes, flush: true);
        path = temp.path;
      }
      if (path.toLowerCase().endsWith('.pdf')) continue;
      final result = await processor.process(
        imagePath: path,
        adjustments: ScanAdjustments(filter: filter),
      );
      processed.add(
        ProcessedPage(
          originalPath: path,
          bytes: result.bytes,
          quad: result.quad ?? const Quad.fullFrame(),
          adjustments: result.adjustments,
        ),
      );
    }

    if (processed.isEmpty) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images were selected.')),
      );
      return;
    }

    final doc = await repository.createProcessedDocument(
      pages: processed,
      title: title,
    );
    bumpLibrary(ref);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    context.push('/library/document/${doc.id}');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not import: $e')));
  }
}

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
