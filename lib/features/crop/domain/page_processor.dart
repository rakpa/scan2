import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/camera/domain/document_quad_detector.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';

/// The finished bytes for a page plus the settings that produced them.
@immutable
class ProcessedCapture {
  const ProcessedCapture({
    required this.bytes,
    required this.quad,
    required this.adjustments,
  });

  final Uint8List bytes;

  /// The crop that was applied, or null if the page was left uncropped.
  final Quad? quad;

  final ScanAdjustments adjustments;
}

/// Turns a raw capture into a finished page: detect edges, perspective-correct,
/// enhance, encode.
///
/// This runs once at capture time so a scan is already a proper scan by the
/// time it reaches the library, rather than a photo the user must remember to
/// go and crop. Everything happens in a single background pass over one decode.
class PageProcessor {
  const PageProcessor();

  /// [quad] forces a crop; leave it null to detect one.
  ///
  /// [fallbackQuad] is used only when detection on the still image finds
  /// nothing — normally the edges the live preview was tracking at the moment
  /// of capture. Without it, a still that fails to detect saves the whole
  /// frame uncropped, even though the user was looking at a locked-on outline
  /// a fraction of a second earlier.
  Future<ProcessedCapture> process({
    required String imagePath,
    Quad? quad,
    Quad? fallbackQuad,
    ScanAdjustments adjustments = const ScanAdjustments(),
    bool detectEdges = true,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    return compute(
      _processIsolate,
      _ProcessRequest(
        bytes: bytes,
        quad: quad == null ? null : _FlatQuad.from(quad),
        fallbackQuad: fallbackQuad == null
            ? null
            : _FlatQuad.from(fallbackQuad),
        adjustments: adjustments,
        detectEdges: detectEdges,
      ),
    );
  }

  /// Re-derives a page from its original using explicit settings, for saves
  /// out of the crop screen.
  Future<Uint8List> render({
    required Uint8List sourceBytes,
    Quad? quad,
    required ScanAdjustments adjustments,
  }) {
    return compute(
      _renderIsolate,
      _ProcessRequest(
        bytes: sourceBytes,
        quad: quad == null ? null : _FlatQuad.from(quad),
        fallbackQuad: null,
        adjustments: adjustments,
        detectEdges: false,
      ),
    );
  }
}

class _FlatQuad {
  const _FlatQuad(this.values);

  factory _FlatQuad.from(Quad q) => _FlatQuad([
    q.topLeft.dx,
    q.topLeft.dy,
    q.topRight.dx,
    q.topRight.dy,
    q.bottomRight.dx,
    q.bottomRight.dy,
    q.bottomLeft.dx,
    q.bottomLeft.dy,
  ]);

  final List<double> values;

  Quad toQuad() => Quad(
    topLeft: Offset(values[0], values[1]),
    topRight: Offset(values[2], values[3]),
    bottomRight: Offset(values[4], values[5]),
    bottomLeft: Offset(values[6], values[7]),
  );
}

class _ProcessRequest {
  const _ProcessRequest({
    required this.bytes,
    required this.quad,
    required this.fallbackQuad,
    required this.adjustments,
    required this.detectEdges,
  });

  final Uint8List bytes;
  final _FlatQuad? quad;
  final _FlatQuad? fallbackQuad;
  final ScanAdjustments adjustments;
  final bool detectEdges;
}

ProcessedCapture _processIsolate(_ProcessRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    return ProcessedCapture(
      bytes: request.bytes,
      quad: null,
      adjustments: request.adjustments,
    );
  }

  final source = Raster.fromImage(img.bakeOrientation(decoded));

  var quad = request.quad?.toQuad();
  if (quad == null && request.detectEdges) {
    quad = detectQuadInRaster(source) ?? request.fallbackQuad?.toQuad();
  }

  return ProcessedCapture(
    bytes: _renderRaster(source, quad, request.adjustments),
    quad: quad,
    adjustments: request.adjustments,
  );
}

Uint8List _renderIsolate(_ProcessRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;
  final source = Raster.fromImage(img.bakeOrientation(decoded));
  return _renderRaster(source, request.quad?.toQuad(), request.adjustments);
}

Uint8List _renderRaster(
  Raster source,
  Quad? quad,
  ScanAdjustments adjustments,
) {
  var raster = source;
  if (quad != null && !PerspectiveTransformer.isFullFrame(quad)) {
    raster = warpRaster(raster, quad) ?? raster;
  }
  final out = applyAdjustments(raster, adjustments);
  return Uint8List.fromList(img.encodeJpg(out.toImage(), quality: 92));
}

/// How far inside the detected border to crop, as a fraction of page size.
const _borderInset = 0.006;

/// Runs edge detection over a full-resolution raster by analysing a
/// downscaled luminance copy, matching the live preview's analysis size so a
/// still capture agrees with the guides the user just saw.
Quad? detectQuadInRaster(Raster source) {
  // Matches the live preview's analysis scale, so a still capture agrees
  // with the guides the user was just looking at.
  const analysisEdge = 320;
  final small = source.downscaledTo(analysisEdge);

  final detection = const DocumentQuadDetector().detect(
    small.toLuma(),
    small.width,
    small.height,
  );
  if (detection == null) return null;

  // Crop just inside the detected border so the page does not come out with
  // a dark rim of desk along its edges.
  return Quad.fromCorners(detection.corners).shrink(_borderInset);
}
