import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gal/gal.dart';
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:share_plus/share_plus.dart';

/// Builds PDFs and hands documents to the share sheet.
///
/// A scanner that cannot produce a PDF is a camera, so this is part of the
/// core flow rather than an extra.
class ExportService {
  const ExportService();

  /// Renders [document] to PDF bytes, one page per scan, each sized to its
  /// own aspect ratio so nothing is letterboxed or stretched.
  ///
  /// Separate from [buildPdf] so it can be exercised without a platform
  /// temp directory.
  Future<Uint8List> buildPdfBytes(Document document) async {
    final images = <_SizedImage>[];
    for (final page in document.pages) {
      final file = File(page.path);
      if (!await file.exists()) continue;
      final prepared = await compute(_prepareForPdf, await file.readAsBytes());
      if (prepared == null) continue;
      images.add(prepared);
    }

    if (images.isEmpty) {
      throw StateError('This document has no pages to export.');
    }
    return compute(_buildPdfBytes, images);
  }

  /// Renders [document] to a PDF in the temp directory.
  Future<File> buildPdf(Document document) async {
    final pdf = await buildPdfBytes(document);
    final directory = await getTemporaryDirectory();
    final file = File(
      path.join(directory.path, '\${fileNameFor(document)}.pdf'),
    );
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  /// Filesystem-safe base name for [document].
  static String fileNameFor(Document document) => _safeFileName(document.title);

  /// Shares [document] as a PDF.
  Future<void> sharePdf(Document document) async {
    final file = await buildPdf(document);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/pdf'),
    ], subject: document.title);
  }

  /// Opens the system sheet with the PDF, where "Save to Files" writes it to
  /// iCloud Drive or On My iPhone.
  ///
  /// iOS has no public API to present the document picker for saving without
  /// going through the share sheet, so this is the supported route rather
  /// than a shortcut.
  Future<void> savePdfToFiles(Document document) => sharePdf(document);

  /// Saves every page image into the system photo library.
  ///
  /// Throws [GalException] when access is refused, which the caller surfaces —
  /// silently doing nothing is the worst possible outcome for a save action.
  Future<int> saveToPhotos(Document document) async {
    var saved = 0;
    for (final page in document.pages) {
      if (!File(page.path).existsSync()) continue;
      await Gal.putImage(page.path, album: 'Scan2');
      saved++;
    }
    if (saved == 0) {
      throw StateError('This document has no pages to save.');
    }
    return saved;
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

/// Longest edge of a page embedded in a PDF.
///
/// Well above what any screen or printer resolves for a document, and far
/// below the ~12MP of the original: embedding those verbatim produces PDFs
/// tens of megabytes large that are slow to open and awkward to email.
const _pdfMaxEdge = 2400;

_SizedImage? _prepareForPdf(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  if (math.max(decoded.width, decoded.height) <= _pdfMaxEdge) {
    return _SizedImage(
      bytes: bytes,
      width: decoded.width,
      height: decoded.height,
    );
  }

  final scaled = Raster.fromImage(decoded).downscaledTo(_pdfMaxEdge);
  return _SizedImage(
    bytes: Uint8List.fromList(img.encodeJpg(scaled.toImage(), quality: 88)),
    width: scaled.width,
    height: scaled.height,
  );
}

Future<Uint8List> _buildPdfBytes(List<_SizedImage> images) async {
  final document = pw.Document();
  for (final image in images) {
    document.addPage(
      pw.Page(
        pageFormat: _pageFormatFor(image),
        build: (context) =>
            pw.Image(pw.MemoryImage(image.bytes), fit: pw.BoxFit.fill),
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
