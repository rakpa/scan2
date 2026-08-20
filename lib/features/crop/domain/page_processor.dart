import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/camera/domain/document_quad_detector.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';
import 'package:scan2/features/crop/domain/spread_snip.dart';

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
  ///
  /// [onlyIfUncropped] is for pages the platform scanner already returned:
  /// crop again only when a desk, holder or second book is still in the
  /// frame. Tight paper borders are left alone so we do not crop into text.
  Future<ProcessedCapture> process({
    required String imagePath,
    Quad? quad,
    Quad? fallbackQuad,
    ScanAdjustments adjustments = const ScanAdjustments(),
    bool detectEdges = true,
    bool onlyIfUncropped = false,
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
        onlyIfUncropped: onlyIfUncropped,
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
        onlyIfUncropped: false,
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
    required this.onlyIfUncropped,
  });

  final Uint8List bytes;
  final _FlatQuad? quad;
  final _FlatQuad? fallbackQuad;
  final ScanAdjustments adjustments;
  final bool detectEdges;
  final bool onlyIfUncropped;
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
    final shouldDetect =
        !request.onlyIfUncropped || looksUncropped(source);
    if (shouldDetect) {
      quad = detectQuadInRaster(source) ?? request.fallbackQuad?.toQuad();
    }
  }

  // An open book is one document to VisionKit. If the user framed a single
  // page ("snip"), keep that page and drop the other side of the gutter.
  final probe = source.downscaledTo(320);
  var probeRaster = probe;
  if (quad != null && !PerspectiveTransformer.isFullFrame(quad)) {
    probeRaster = warpRaster(probe, quad) ?? probe;
  }
  final snip = detectSpreadSnip(probeRaster);
  if (snip != null) {
    quad = splitQuadAtGutter(
      quad ?? const Quad.fullFrame(),
      snip.gutterX,
      keepRight: snip.keepRight,
    );
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

/// True when the capture still includes a non-page rim — a desk, a book
/// holder, another book — so a second crop is worth running.
///
/// A page the platform scanner already cropped tightly to paper is light
/// (or evenly toned) out at the edges. A photo of a book on a stand is not.
bool looksUncropped(Raster source) {
  final small = source.downscaledTo(160);
  final w = small.width;
  final h = small.height;
  if (w < 12 || h < 12) return false;

  final luma = small.toLuma();
  int at(int x, int y) => luma[y * w + x];

  var interiorSum = 0;
  var interiorN = 0;
  final ix0 = (w * 0.25).round();
  final ix1 = (w * 0.75).round();
  final iy0 = (h * 0.25).round();
  final iy1 = (h * 0.75).round();
  for (var y = iy0; y < iy1; y += 2) {
    for (var x = ix0; x < ix1; x += 2) {
      interiorSum += at(x, y);
      interiorN++;
    }
  }
  if (interiorN == 0) return false;
  final interior = interiorSum / interiorN;

  final bx = math.max(1, (w * 0.04).round());
  final by = math.max(1, (h * 0.04).round());
  var dark = 0;
  var borderN = 0;
  void sample(int x, int y) {
    borderN++;
    if (interior - at(x, y) > 28) dark++;
  }

  for (var x = 0; x < w; x += 2) {
    for (var y = 0; y < by; y += 1) {
      sample(x, y);
      sample(x, h - 1 - y);
    }
  }
  for (var y = by; y < h - by; y += 2) {
    for (var x = 0; x < bx; x += 1) {
      sample(x, y);
      sample(w - 1 - x, y);
    }
  }
  if (borderN == 0) return false;
  return dark / borderN > 0.32;
}
