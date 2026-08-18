import 'package:flutter/material.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Draws the live document quad over the camera preview.
///
/// Must share a coordinate space with the preview (be a child of the same
/// fitted box) so normalized corners land on the real document pixels.
class QuadOverlay extends StatelessWidget {
  const QuadOverlay({
    super.key,
    required this.quad,
    required this.color,
    required this.locked,
    this.progress = 0,
  });

  final Quad quad;
  final Color color;

  /// True once the page is recognised, which switches the overlay from a
  /// dashed hint to a solid outline.
  final bool locked;

  /// 0–1 progress toward an automatic capture.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _QuadPainter(
          quad: quad,
          color: color,
          locked: locked,
          progress: progress,
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
  });

  final Quad quad;
  final Color color;
  final bool locked;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad.corners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();
    final path = Path()..addPolygon(points, true);

    // Dim everything outside the page so the edges read at a glance.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: locked ? 0.45 : 0.3),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: locked ? 0.14 : 0.06)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = locked ? 3 : 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Corner brackets, which read as "tracking" far better than dots do.
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = locked ? 5 : 3.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 4; i++) {
      final corner = points[i];
      final previous = points[(i + 3) % 4];
      final next = points[(i + 1) % 4];
      _drawBracketArm(canvas, corner, next, bracket);
      _drawBracketArm(canvas, corner, previous, bracket);
    }

    if (progress > 0.01) {
      _drawProgressRing(canvas, points, size);
    }
  }

  /// A short stroke from [corner] toward [towards], length-capped so it stays
  /// a bracket rather than tracing the whole edge.
  void _drawBracketArm(
    Canvas canvas,
    Offset corner,
    Offset towards,
    Paint paint,
  ) {
    final delta = towards - corner;
    final length = delta.distance;
    if (length < 1) return;
    final armLength = (length * 0.22).clamp(8.0, 34.0);
    canvas.drawLine(corner, corner + delta / length * armLength, paint);
  }

  /// Countdown ring at the centre of the page, so the shutter never fires
  /// without warning.
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
      -1.5707963, // start at 12 o'clock
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
      old.progress != progress;
}
