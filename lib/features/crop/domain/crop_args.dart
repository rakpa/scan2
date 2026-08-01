import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Route payload for [CropScreen].
class CropArgs {
  final String imagePath;
  final int? pageId;
  final Quad? initialQuad;

  /// True when the image was already edge-cropped (e.g. VisionKit / ML Kit).
  final bool edgesAlreadyApplied;

  const CropArgs({
    required this.imagePath,
    this.pageId,
    this.initialQuad,
    this.edgesAlreadyApplied = false,
  });
}
