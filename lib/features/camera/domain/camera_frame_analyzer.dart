import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:scan2/features/camera/domain/detection_worker.dart';
import 'package:scan2/features/camera/domain/document_quad_detector.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Result of analyzing a single camera frame for a document boundary.
class FrameDetectionResult {
  const FrameDetectionResult({required this.quad, required this.confidence});

  final Quad? quad;
  final double confidence;

  static const none = FrameDetectionResult(quad: null, confidence: 0);
}

/// A downscaled grayscale view of one camera frame.
class LuminanceGrid {
  const LuminanceGrid({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Extracts luminance from camera frames and forwards them to a
/// [DetectionWorker].
///
/// The downsample runs here on the UI isolate because it is only ~40k reads
/// and the camera's plane buffers are not safe to hold past the callback.
/// Everything after that — the expensive part — happens on the worker.
class CameraFrameAnalyzer {
  CameraFrameAnalyzer({DetectionWorker? worker}) : _worker = worker;

  /// Analysis resolution. Large enough for edges to survive the downsample,
  /// small enough to stay well inside a frame budget.
  static const analysisWidth = 240;

  DetectionWorker? _worker;
  var _ownsWorker = false;

  Future<void> ensureStarted() async {
    if (_worker != null) return;
    _worker = await DetectionWorker.spawn();
    _ownsWorker = true;
  }

  bool get isBusy => _worker?.isBusy ?? false;

  /// Analyses [image]. Returns null when the worker is busy — the caller
  /// should keep showing the previous quad rather than clearing it.
  Future<FrameDetectionResult?> analyze(
    CameraImage image,
    CameraDescription camera,
    int deviceOrientationDegrees,
  ) async {
    final worker = _worker;
    if (worker == null || worker.isBusy) return null;

    final grid = luminanceGrid(image);
    if (grid == null) return null;

    final detection = await worker.analyze(grid.bytes, grid.width, grid.height);
    if (detection == null) return FrameDetectionResult.none;

    final rotation = _previewRotation(camera, deviceOrientationDegrees);
    return FrameDetectionResult(
      quad: _toPreviewQuad(detection.corners, rotation),
      confidence: detection.confidence,
    );
  }

  void dispose() {
    if (_ownsWorker) _worker?.dispose();
    _worker = null;
  }

  /// Rotation, in degrees, from sensor buffer space to what the preview shows.
  int _previewRotation(CameraDescription camera, int deviceOrientation) {
    if (camera.lensDirection == CameraLensDirection.front) {
      return (camera.sensorOrientation + deviceOrientation) % 360;
    }
    return (camera.sensorOrientation - deviceOrientation + 360) % 360;
  }

  @visibleForTesting
  static Quad toPreviewQuad(List<Offset> bufferCorners, int rotation) =>
      _toPreviewQuadImpl(bufferCorners, rotation);

  Quad _toPreviewQuad(List<Offset> bufferCorners, int rotation) =>
      _toPreviewQuadImpl(bufferCorners, rotation);

  /// Converts a downscaled grayscale view of [image], or null if the format
  /// cannot be read.
  @visibleForTesting
  LuminanceGrid? luminanceGrid(CameraImage image) {
    if (image.planes.isEmpty) return null;

    final srcW = image.width;
    final srcH = image.height;
    if (srcW < 16 || srcH < 16) return null;

    const targetW = analysisWidth;
    final targetH = (targetW * srcH / srcW).round().clamp(48, 320);
    final grid = Uint8List(targetW * targetH);

    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        _fillFromBgra(
          image.planes.first,
          srcW: srcW,
          srcH: srcH,
          targetW: targetW,
          targetH: targetH,
          grid: grid,
        );
      case ImageFormatGroup.yuv420:
      case ImageFormatGroup.nv21:
      default:
        _fillFromYPlane(
          image.planes.first,
          srcW: srcW,
          srcH: srcH,
          targetW: targetW,
          targetH: targetH,
          grid: grid,
        );
    }

    return LuminanceGrid(bytes: grid, width: targetW, height: targetH);
  }

  void _fillFromYPlane(
    Plane plane, {
    required int srcW,
    required int srcH,
    required int targetW,
    required int targetH,
    required Uint8List grid,
  }) {
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;

    for (var y = 0; y < targetH; y++) {
      final srcY = (y * srcH / targetH).floor().clamp(0, srcH - 1);
      final rowBase = srcY * rowStride;
      final dstBase = y * targetW;
      for (var x = 0; x < targetW; x++) {
        final srcX = (x * srcW / targetW).floor().clamp(0, srcW - 1);
        final index = rowBase + srcX * pixelStride;
        if (index < bytes.length) grid[dstBase + x] = bytes[index];
      }
    }
  }

  void _fillFromBgra(
    Plane plane, {
    required int srcW,
    required int srcH,
    required int targetW,
    required int targetH,
    required Uint8List grid,
  }) {
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    const bpp = 4;

    for (var y = 0; y < targetH; y++) {
      final srcY = (y * srcH / targetH).floor().clamp(0, srcH - 1);
      final rowBase = srcY * rowStride;
      final dstBase = y * targetW;
      for (var x = 0; x < targetW; x++) {
        final srcX = (x * srcW / targetW).floor().clamp(0, srcW - 1);
        final index = rowBase + srcX * bpp;
        if (index + 2 < bytes.length) {
          final b = bytes[index];
          final g = bytes[index + 1];
          final r = bytes[index + 2];
          grid[dstBase + x] = (r * 77 + g * 150 + b * 29) >> 8;
        }
      }
    }
  }
}

Quad _toPreviewQuadImpl(List<Offset> bufferCorners, int rotation) {
  // Normalized coordinates, so a rotation is just an axis swap and flip.
  Offset rotate(Offset p) => switch (rotation % 360) {
    90 => Offset(1 - p.dy, p.dx),
    180 => Offset(1 - p.dx, 1 - p.dy),
    270 => Offset(p.dy, 1 - p.dx),
    _ => p,
  };

  final rotated = DocumentQuadDetector.orderCorners(
    bufferCorners.map(rotate).toList(growable: false),
  );
  return Quad(
    topLeft: rotated[0],
    topRight: rotated[1],
    bottomRight: rotated[2],
    bottomLeft: rotated[3],
  );
}
