import 'package:flutter/material.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

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
    return Positioned.fill(
      child: CustomPaint(
        painter: _QuadPainter(quad: quad, color: color),
      ),
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

    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

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
