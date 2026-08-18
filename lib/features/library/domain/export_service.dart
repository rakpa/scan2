import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:scan2/features/library/domain/document.dart';
import 'package:share_plus/share_plus.dart';

/// Builds PDFs and hands documents to the share sheet.
///
/// A scanner that cannot produce a PDF is a camera, so this is part of the
/// core flow rather than an extra.
class ExportService {
  const ExportService();

  /// Renders [document] to a PDF, one page per scan, each sized to its own
  /// aspect ratio so nothing is letterboxed or stretched.
  Future<File> buildPdf(Document document) async {
    final images = <_SizedImage>[];
    for (final page in document.pages) {
      final file = File(page.path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final size = await compute(_measure, bytes);
      if (size == null) continue;
      images.add(_SizedImage(bytes: bytes, width: size.$1, height: size.$2));
    }

    if (images.isEmpty) {
      throw StateError('This document has no pages to export.');
    }

    final pdf = await compute(_buildPdfBytes, images);
    final directory = await getTemporaryDirectory();
    final file = File(
      path.join(directory.path, '${_safeFileName(document.title)}.pdf'),
    );
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  /// Shares [document] as a PDF.
  Future<void> sharePdf(Document document) async {
    final file = await buildPdf(document);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: document.title,
    );
  }

  /// Shares the page images themselves, for people who want the JPEGs.
  Future<void> shareImages(Document document) async {
    final files = [
      for (final page in document.pages)
        if (File(page.path).existsSync())
          XFile(page.path, mimeType: 'image/jpeg'),
    ];
    if (files.isEmpty) {
      throw StateError('This document has no pages to share.');
    }
    await Share.shareXFiles(files, subject: document.title);
  }

  static String _safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return cleaned.isEmpty ? 'scan' : cleaned;
  }
}

class _SizedImage {
  const _SizedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

(int, int)? _measure(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (decoded.width, decoded.height);
}

Future<Uint8List> _buildPdfBytes(List<_SizedImage> images) async {
  final document = pw.Document();
  for (final image in images) {
    document.addPage(
      pw.Page(
        pageFormat: _pageFormatFor(image),
        build: (context) => pw.Image(
          pw.MemoryImage(image.bytes),
          fit: pw.BoxFit.fill,
        ),
      ),
    );
  }
  return document.save();
}

/// A page with the scan's own proportions, scaled so its longest side matches
/// A4's.
///
/// Sizing the page in pixels instead would make a 12MP scan a 40-inch page,
/// and forcing everything to portrait A4 would letterbox receipts and
/// landscape pages with white margins.
PdfPageFormat _pageFormatFor(_SizedImage image) {
  final longestSide = PdfPageFormat.a4.height;
  final width = image.width.toDouble();
  final height = image.height.toDouble();
  if (width <= 0 || height <= 0) return PdfPageFormat.a4;

  final scale = longestSide / math.max(width, height);
  return PdfPageFormat(width * scale, height * scale);
}
