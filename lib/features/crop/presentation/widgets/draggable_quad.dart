import 'package:flutter/material.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

typedef QuadChanged = void Function(Quad quad);

class DraggableQuad extends StatefulWidget {
  final Quad initialQuad;
  final QuadChanged onChanged;
  final Size size;

  const DraggableQuad({
    super.key,
    required this.initialQuad,
    required this.onChanged,
    required this.size,
  });

  @override
  State<DraggableQuad> createState() => _DraggableQuadState();
}

class _DraggableQuadState extends State<DraggableQuad> {
  late Quad _quad;

  @override
  void initState() {
    super.initState();
    _quad = widget.initialQuad;
  }

  @override
  void didUpdateWidget(covariant DraggableQuad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuad != widget.initialQuad) {
      _quad = widget.initialQuad;
    }
  }

  Offset _toLocal(Offset normalized) => Offset(
        normalized.dx * widget.size.width,
        normalized.dy * widget.size.height,
      );

  Offset _toNormalized(Offset local) => Offset(
        (local.dx / widget.size.width).clamp(0.0, 1.0),
        (local.dy / widget.size.height).clamp(0.0, 1.0),
      );

  void _moveCorner(int index, Offset local) {
    setState(() {
      _quad = _quad.withCorner(index, _toNormalized(local));
    });
    widget.onChanged(_quad);
  }

  @override
  Widget build(BuildContext context) {
    final points = _quad.corners.map(_toLocal).toList();

    return Stack(
      children: [
        CustomPaint(
          size: widget.size,
          painter: _CropFramePainter(points: points),
        ),
        for (var i = 0; i < points.length; i++)
          Positioned(
            left: points[i].dx - 18,
            top: points[i].dy - 18,
            child: GestureDetector(
              onPanUpdate: (d) {
                _moveCorner(
                  i,
                  Offset(points[i].dx + d.delta.dx, points[i].dy + d.delta.dy),
                );
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CropFramePainter extends CustomPainter {
  final List<Offset> points;

  _CropFramePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final fill = Paint()
      ..color = Colors.blue.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter oldDelegate) =>
      oldDelegate.points != points;
}
