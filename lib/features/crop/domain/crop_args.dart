import 'package:flutter/foundation.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';

/// Route payload for the crop screen.
@immutable
class CropArgs {
  const CropArgs({
    required this.imagePath,
    this.initialQuad,
    this.adjustments = const ScanAdjustments(),
    this.edgesAlreadyApplied = false,
  });

  /// The page to edit. The screen re-derives from the page's stored original
  /// when one exists, so this may be either.
  final String imagePath;

  final Quad? initialQuad;
  final ScanAdjustments adjustments;

  /// True when the image was already edge-cropped (VisionKit / ML Kit), so
  /// the crop opens on the full frame instead of hunting for borders.
  final bool edgesAlreadyApplied;
}
