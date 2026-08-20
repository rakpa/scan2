import 'package:flutter/foundation.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';

/// One page of a document.
///
/// [path] is the finished image — cropped, enhanced, and what the library,
/// PDF export and sharing all use. [originalPath] is the untouched capture it
/// was derived from.
///
/// Keeping both is what makes editing non-destructive. Re-cropping an already
/// cropped and sharpened JPEG compounds the losses of every previous pass and
/// cannot widen a crop that was taken too tight; re-deriving from the original
/// each time always produces the same quality, and lets the crop screen
/// reopen with the exact edges and filter that were last applied.
@immutable
class ScanPage {
  const ScanPage({
    required this.path,
    this.originalPath,
    this.quad,
    this.adjustments = const ScanAdjustments(),
  });

  final String path;
  final String? originalPath;

  /// Crop applied to [originalPath], in normalized coordinates. Null when the
  /// page was never cropped (an import, or a native scan already cropped by
  /// VisionKit).
  final Quad? quad;

  final ScanAdjustments adjustments;

  /// The image edits should be re-derived from.
  String get editSource => originalPath ?? path;

  /// Whether the original is still available to re-edit from.
  bool get canReedit => originalPath != null;

  ScanPage copyWith({
    String? path,
    String? originalPath,
    Quad? quad,
    ScanAdjustments? adjustments,
  }) {
    return ScanPage(
      path: path ?? this.path,
      originalPath: originalPath ?? this.originalPath,
      quad: quad ?? this.quad,
      adjustments: adjustments ?? this.adjustments,
    );
  }
}

@immutable
class Document {
  const Document({
    required this.id,
    required this.title,
    required this.createdAt,
    this.pages = const [],
    this.folderId,
    this.edgesAlreadyApplied = false,
    this.pdfPath,
    this.fileSizeBytes,
    this.documentType = 'Image',
    this.favorited = false,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final List<ScanPage> pages;
  final int? folderId;

  /// True when pages came from the native auto-edge scanner and are already
  /// perspective-cropped.
  final bool edgesAlreadyApplied;

  /// Local PDF written beside the page images, when one has been generated.
  final String? pdfPath;

  /// Combined size of the stored images (and PDF, if any).
  final int? fileSizeBytes;

  /// `PDF` or `Image`.
  final String documentType;

  final bool favorited;

  int get pageCount => pages.length;

  List<String> get pagePaths => [for (final page in pages) page.path];

  String get fileName => pdfPath != null ? '$title.pdf' : title;

  String? get thumbnailPath => pages.isEmpty ? null : pages.first.path;

  /// Badge shown on the library thumbnail: PDF when a PDF was filed.
  String get typeLabel {
    if (pdfPath != null || documentType.toUpperCase() == 'PDF') return 'PDF';
    return 'JPG';
  }

  String get formattedSize {
    final bytes = fileSizeBytes;
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${_pretty(bytes / 1024)} KB';
    }
    return '${_pretty(bytes / (1024 * 1024))} MB';
  }

  static String _pretty(double value) {
    return value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(1);
  }

  ScanPage? pageAt(String path) {
    for (final page in pages) {
      if (page.path == path) return page;
    }
    return null;
  }

  Document copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    List<ScanPage>? pages,
    int? folderId,
    bool? edgesAlreadyApplied,
    String? pdfPath,
    int? fileSizeBytes,
    String? documentType,
    bool? favorited,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      pages: pages ?? this.pages,
      folderId: folderId ?? this.folderId,
      edgesAlreadyApplied: edgesAlreadyApplied ?? this.edgesAlreadyApplied,
      pdfPath: pdfPath ?? this.pdfPath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      documentType: documentType ?? this.documentType,
      favorited: favorited ?? this.favorited,
    );
  }
}
