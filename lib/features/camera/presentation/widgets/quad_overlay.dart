import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Guide colour used by the live edge overlay.
///
/// White while searching, yellow once a page is tracked, green when a
/// capture is armed. This is the previous scanner behaviour — Screen 9
/// briefly hid the overlay until a lock, which looked like detection
/// had stopped.
Color liveScanOverlayColor(ScanState state) {
  if (state.phase == ScanPhase.capturing ||
      state.phase == ScanPhase.captured) {
    return const Color(0xFF4CAF50);
  }
  if (state.confidence >= DocumentEdgeTracker.autoCaptureConfidence) {
    return const Color(0xFF4CAF50);
  }
  if (state.confidence >= DocumentEdgeTracker.minTrackConfidence) {
    return const Color(0xFFFFC107);
  }
  return Colors.white70;
}

/// Draws the live document quad over the camera preview.
///
/// Must share a coordinate space with the preview (be a child of the same
/// fitted box) so normalized corners land on the real document pixels.
class QuadOverlay extends StatelessWidget {
  const QuadOverlay({
    super.key,
    required this.quad,
    this.color = Brand.blue,
    required this.locked,
    this.progress = 0,
    this.showCornerHandles = true,
    this.dimOutside = false,
  });

  final Quad quad;
  final Color color;

  /// True once the page is recognised.
  final bool locked;

  /// 0–1 progress toward an automatic capture.
  final double progress;

  /// Solid white circles on each corner, as on Screen 9.
  final bool showCornerHandles;

  /// Darken everything outside the page. Off on Screen 9 so the desk stays
  /// visible around the blue frame.
  final bool dimOutside;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _QuadPainter(
          quad: quad,
          color: color,
          locked: locked,
          progress: progress,
          showCornerHandles: showCornerHandles,
          dimOutside: dimOutside,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.quad,
    required this.color,
    required this.locked,
    required this.progress,
    required this.showCornerHandles,
    required this.dimOutside,
  });

  final Quad quad;
  final Color color;
  final bool locked;
  final double progress;
  final bool showCornerHandles;
  final bool dimOutside;

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad.corners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();
    final path = Path()..addPolygon(points, true);

    if (dimOutside) {
      final scrim = Path()
        ..addRect(Offset.zero & size)
        ..addPath(path, Offset.zero)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        scrim,
        Paint()..color = Colors.black.withValues(alpha: locked ? 0.45 : 0.3),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );

    if (showCornerHandles) {
      final fill = Paint()..color = Colors.white;
      final ring = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final corner in points) {
        canvas.drawCircle(corner, 7, fill);
        canvas.drawCircle(corner, 7, ring);
      }
    }

    if (progress > 0.01) {
      _drawProgressRing(canvas, points, size);
    }
  }

  void _drawProgressRing(Canvas canvas, List<Offset> points, Size size) {
    final centre = points.reduce((a, b) => a + b) / 4;
    final radius = size.shortestSide * 0.055;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -1.5707963,
      6.2831853 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) =>
      old.quad != quad ||
      old.color != color ||
      old.locked != locked ||
      old.progress != progress ||
      old.showCornerHandles != showCornerHandles ||
      old.dimOutside != dimOutside;
}
