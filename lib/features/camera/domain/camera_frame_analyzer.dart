import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'package:scan2/features/camera/domain/document_quad_detector.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Result of analyzing a single camera frame for a document boundary.
class FrameDetectionResult {
  const FrameDetectionResult({
    required this.quad,
    required this.confidence,
  });

  final Quad? quad;
  final double confidence;
}

/// Detects a document quad from live camera frames (YUV or BGRA).
class CameraFrameAnalyzer {
  CameraFrameAnalyzer();

  static const _minInterval = Duration(milliseconds: 100);
  static const _analysisWidth = 160;

  final _detector = const QuadDetector();
  DateTime? _lastProcessed;

  /// Returns null when throttled — callers should keep the previous quad.
  FrameDetectionResult? analyzeThrottled(
    CameraImage image,
    CameraDescription camera,
  ) {
    final now = DateTime.now();
    if (_lastProcessed != null &&
        now.difference(_lastProcessed!) < _minInterval) {
      return null;
    }
    _lastProcessed = now;
    return analyze(image, camera);
  }

  @visibleForTesting
  FrameDetectionResult analyze(CameraImage image, CameraDescription camera) {
    final grid = _luminanceGrid(image);
    if (grid == null) {
      return const FrameDetectionResult(quad: null, confidence: 0);
    }

    final detection =
        _detector.detectFromLuminance(grid.bytes, grid.width, grid.height);
    if (detection == null) {
      return const FrameDetectionResult(quad: null, confidence: 0);
    }

    final quad = _toPreviewQuad(detection.corners, camera.sensorOrientation);
    return FrameDetectionResult(quad: quad, confidence: detection.confidence);
  }

  Quad _toPreviewQuad(List<Offset> bufferCorners, int sensorOrientation) {
    Offset rotate(Offset p) => switch (sensorOrientation % 360) {
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

  _LumGrid? _luminanceGrid(CameraImage image) {
    if (image.planes.isEmpty) return null;

    final srcW = image.width;
    final srcH = image.height;
    if (srcW < 16 || srcH < 16) return null;

    const targetW = _analysisWidth;
    final targetH = (targetW * srcH / srcW).round().clamp(48, 220);
    final grid = Uint8List(targetW * targetH);

    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        _fillLumFromBgra(
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
        _fillLumFromYPlane(
          image.planes.first,
          srcW: srcW,
          srcH: srcH,
          targetW: targetW,
          targetH: targetH,
          grid: grid,
        );
    }

    return _LumGrid(bytes: grid, width: targetW, height: targetH);
  }

  void _fillLumFromYPlane(
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
        if (index < bytes.length) {
          grid[dstBase + x] = bytes[index];
        }
      }
    }
  }

  void _fillLumFromBgra(
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

class _LumGrid {
  const _LumGrid({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;
  final int width;
  final int height;
}
