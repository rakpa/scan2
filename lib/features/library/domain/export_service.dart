import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
    final prepared = await Future.wait([
      for (final page in document.pages) _preparePage(page.path),
    ]);
    final images = [for (final image in prepared) if (image != null) image];

    if (images.isEmpty) {
      throw StateError('This document has no pages to export.');
    }
    return compute(_buildPdfBytes, images);
  }

  Future<_SizedImage?> _preparePage(String pagePath) async {
    final file = File(pagePath);
    if (!await file.exists()) return null;
    return compute(_prepareForPdf, await file.readAsBytes());
  }

  /// Renders [document] to a PDF in the temp directory.
  Future<File> buildPdf(Document document) async {
    final pdf = await pdfBytesFor(document);
    final directory = await getTemporaryDirectory();
    final file = File(
      path.join(directory.path, '${fileNameFor(document)}.pdf'),
    );
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  /// Bytes for the filed PDF, generating one only when it is not already stored.
  Future<Uint8List> pdfBytesFor(Document document) async {
    final stored = document.pdfPath;
    if (stored != null) {
      try {
        final file = File(stored);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } on FileSystemException catch (e) {
        debugPrint('Stored PDF unreadable, rebuilding: $e');
      }
    }
    return buildPdfBytes(document);
  }

  /// Filesystem-safe base name for [document].
  static String fileNameFor(Document document) => _safeFileName(document.title);

  /// Anchor for the iOS/iPad share and print popover.
  ///
  /// share_plus throws PathAccessException-style PlatformException when this
  /// is missing or empty: `sharePositionOrigin must be set and non-zero`.
  static Rect originOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final size = box.size;
      if (size.width >= 1 && size.height >= 1) {
        return box.localToGlobal(Offset.zero) & size;
      }
    }
    return originOnScreen(MediaQuery.sizeOf(context));
  }

  /// A small rect guaranteed to sit inside [size].
  static Rect originOnScreen(Size size) {
    if (size.width < 2 || size.height < 2) {
      return const Rect.fromLTWH(64, 64, 48, 48);
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.72),
      width: 48,
      height: 48,
    );
  }

  /// Shares [document] as a PDF through the system share sheet.
  Future<void> sharePdf(Document document, {Rect? shareOrigin}) async {
    final file = await buildPdf(document);
    await _shareFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: document.title,
      origin: shareOrigin,
    );
  }

  /// Lets the user pick a destination and writes the PDF there.
  ///
  /// On iOS the system document picker exports a copy we already wrote into
  /// the app sandbox. The path it returns is often iCloud Drive, which this
  /// process cannot open again (PathAccessException, errno 1). The picker
  /// has already saved — do not write to, or even `exists()`-check, that path.
  Future<bool> savePdfToFiles(
    Document document, {
    Rect? shareOrigin,
  }) async {
    final bytes = await pdfBytesFor(document);
    final name = '${fileNameFor(document)}.pdf';
    try {
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save PDF',
        fileName: name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (savedPath == null || savedPath.isEmpty) return false;
      return true;
    } catch (e) {
      debugPrint('Save to Files: $e');
      // Native export already copied into Files / iCloud. Opening that URL
      // is forbidden; treating it as failure would toast the raw exception.
      if (_pickerAlreadyExported(e)) return true;
      await sharePdf(document, shareOrigin: shareOrigin);
      return true;
    }
  }

  /// True when the exception is the iCloud / Files destination we must not open.
  static bool pickerAlreadyExported(Object error) =>
      _pickerAlreadyExported(error);

  /// Opens the native print preview with the generated PDF.
  /// Opens the native print preview with the generated PDF.
  ///
  /// iOS deadlocks if [Printing.layoutPdf] uses the default dynamic layout:
  /// the plugin blocks the main thread waiting for PDF bytes that Dart cannot
  /// deliver. `dynamicLayout: false` sends the bytes once, then presents.
  Future<void> printPdf(Document document, {Rect? shareOrigin}) async {
    final bytes = await pdfBytesFor(document);
    try {
      final info = await Printing.info();
      if (info.canPrint) {
        await Printing.layoutPdf(
          name: fileNameFor(document),
          format: PdfPageFormat.a4,
          dynamicLayout: false,
          onLayout: (_) async => bytes,
        );
        return;
      }
    } catch (e) {
      debugPrint('Print UI failed, offering share sheet: $e');
    }
    await sharePdf(document, shareOrigin: shareOrigin);
  }

  /// Saves every page image into the system photo library.
  ///
  /// Throws [GalException] when access is refused, which the caller surfaces —
  /// silently doing nothing is the worst possible outcome for a save action.
  Future<int> saveToPhotos(Document document) async {
    final allowed =
        await Gal.hasAccess(toAlbum: true) ||
        await Gal.requestAccess(toAlbum: true);
    if (!allowed) {
      throw StateError('Photo library access was not granted.');
    }
    var saved = 0;
    for (final page in document.pages) {
      if (!File(page.path).existsSync()) continue;
      await Gal.putImage(page.path, album: 'Scanella');
      saved++;
    }
    if (saved == 0) {
      throw StateError('This document has no pages to save.');
    }
    return saved;
  }

  /// Shares the page images themselves, for people who want the JPEGs.
  Future<void> shareImages(Document document, {Rect? shareOrigin}) async {
    final files = [
      for (final page in document.pages)
        if (File(page.path).existsSync())
          XFile(
            page.path,
            mimeType: page.path.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
          ),
    ];
    if (files.isEmpty) {
      throw StateError('This document has no pages to share.');
    }
    await _shareFiles(files, subject: document.title, origin: shareOrigin);
  }

  Future<void> _shareFiles(
    List<XFile> files, {
    required String subject,
    Rect? origin,
  }) {
    return Share.shareXFiles(
      files,
      subject: subject,
      sharePositionOrigin: _nonEmptyOrigin(origin),
    );
  }

  static Rect _nonEmptyOrigin(Rect? origin) {
    if (origin != null && origin.width >= 1 && origin.height >= 1) {
      return origin;
    }
    return const Rect.fromLTWH(80, 120, 48, 48);
  }

  static String _safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return cleaned.isEmpty ? 'scan' : cleaned;
  }
}

bool _pickerAlreadyExported(Object error) {
  final text = error.toString();
  if (text.contains('PathAccessException') ||
      text.contains('CloudDocs') ||
      text.contains('Mobile Documents')) {
    return true;
  }
  return error is FileSystemException &&
      (error.osError?.errorCode == 1 ||
          text.contains('Operation not permitted'));
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
const _pdfMaxEdge = 2560;

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
    bytes: Uint8List.fromList(img.encodeJpg(scaled.toImage(), quality: 95)),
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
