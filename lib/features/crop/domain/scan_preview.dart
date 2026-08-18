import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';

/// Longest edge of the raster the crop screen previews on.
///
/// Interactive preview is the whole reason this exists: filtering a 12MP
/// camera frame takes many seconds per tap, which is indistinguishable from
/// the filter being broken. Every preview runs on this downscaled copy and
/// only the final save touches full resolution.
const int kPreviewMaxEdge = 1000;

/// A decoded, orientation-corrected, downscaled copy of a page, reused for
/// every preview render so a filter change never re-decodes the JPEG.
@immutable
class PreviewSource {
  const PreviewSource({
    required this.raster,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final Raster raster;

  /// Dimensions of the full-resolution page this was derived from.
  final int sourceWidth;
  final int sourceHeight;

  double get sourceAspect => sourceHeight == 0 ? 1 : sourceWidth / sourceHeight;
}

/// Decodes [bytes] once into a preview-sized raster, off the UI isolate.
Future<PreviewSource?> loadPreviewSource(Uint8List bytes) {
  return compute(_loadPreviewIsolate, bytes);
}

PreviewSource? _loadPreviewIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final baked = img.bakeOrientation(decoded);
  final full = Raster.fromImage(baked);
  return PreviewSource(
    raster: full.downscaledTo(kPreviewMaxEdge),
    sourceWidth: baked.width,
    sourceHeight: baked.height,
  );
}

/// What a preview render should show.
@immutable
class PreviewRequest {
  const PreviewRequest({
    required this.source,
    required this.adjustments,
    this.quad,
  });

  final PreviewSource source;
  final ScanAdjustments adjustments;

  /// When set, the preview is perspective-corrected to this quad first.
  final Quad? quad;
}

/// Renders a preview raster: warp (if a quad is given), then filter.
Future<Raster> renderPreview(PreviewRequest request) {
  return compute(_renderPreviewIsolate, request);
}

Raster _renderPreviewIsolate(PreviewRequest request) {
  var raster = request.source.raster;

  final quad = request.quad;
  if (quad != null && !PerspectiveTransformer.isFullFrame(quad)) {
    raster = warpRaster(raster, quad) ?? raster;
  }

  return applyAdjustments(raster, request.adjustments);
}
