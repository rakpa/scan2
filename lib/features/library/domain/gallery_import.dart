import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Imports one or more photos from the gallery as a new document.
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
    final doc = await ref
        .read(documentRepositoryProvider)
        .createDocumentFromScans(
          [for (final file in files) file.path],
          title: title,
          edgesAlreadyApplied: true,
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
