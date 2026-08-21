import 'dart:typed_data';

import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';

/// One captured page waiting for review on the scan-result screen.
class ScanResultPageDraft {
  const ScanResultPageDraft({
    required this.originalPath,
    required this.bytes,
    this.quad,
    this.adjustments = const ScanAdjustments(),
    this.rotationQuarterTurns = 0,
  });

  /// Untouched capture, so filters and crop re-derive rather than stacking
  /// on an already-enhanced JPEG.
  final String originalPath;

  /// Bytes shown on first paint — already auto-cropped and enhanced.
  final Uint8List bytes;

  final Quad? quad;
  final ScanAdjustments adjustments;
  final int rotationQuarterTurns;
}

class ScanResultArgs {
  const ScanResultArgs({
    required this.pages,
    this.existingDocumentId,
    this.allowRetake = true,
  }) : assert(pages.length > 0);

  final List<ScanResultPageDraft> pages;

  /// When set, Save updates this library entry instead of creating another.
  final int? existingDocumentId;

  /// Camera captures can retake. Gallery and Files imports cannot.
  final bool allowRetake;
}
