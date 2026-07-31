import 'package:flutter/material.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// Draws the live document quad. Must be a *child* of [CameraPreview] (or share
/// the same fitted box) so normalized corners map onto preview pixels.
class QuadOverlay extends StatelessWidget {
  final Quad quad;
  final Color color;

  const QuadOverlay({
    super.key,
    required this.quad,
    this.color = const Color(0xFF4CAF50),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _QuadPainter(quad: quad, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final Quad quad;
  final Color color;

  _QuadPainter({required this.quad, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad.corners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();

    final docPath = Path()..addPolygon(points, true);

    // Dim outside the document so edges read clearly.
    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addPath(docPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(docPath, fill);
    canvas.drawPath(docPath, stroke);

    final handle = Paint()..color = Colors.white;
    final handleBorder = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in points) {
      canvas.drawCircle(p, 8, handle);
      canvas.drawCircle(p, 8, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color;
}
