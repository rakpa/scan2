import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

typedef QuadChanged = void Function(Quad quad);

/// Draggable crop corners drawn over a `BoxFit.contain` image.
///
/// The corners are positioned against [imageRect], the rectangle the image
/// actually occupies — not the widget's own bounds. Those differ whenever the
/// image aspect ratio differs from the container's, which is essentially
/// always, and mapping normalized corners onto the container instead puts
/// every handle in the wrong place and crops the wrong region on save.
class DraggableQuad extends StatefulWidget {
  const DraggableQuad({
    super.key,
    required this.quad,
    required this.imageRect,
    required this.onChanged,
  });

  final Quad quad;

  /// Where the image is painted, in this widget's coordinate space.
  final Rect imageRect;

  final QuadChanged onChanged;

  @override
  State<DraggableQuad> createState() => _DraggableQuadState();
}

class _DraggableQuadState extends State<DraggableQuad> {
  static const _handleRadius = 22.0;

  int? _activeCorner;
  int? _activeEdge;

  Offset _toLocal(Offset normalized) => Offset(
    widget.imageRect.left + normalized.dx * widget.imageRect.width,
    widget.imageRect.top + normalized.dy * widget.imageRect.height,
  );

  Offset _toNormalized(Offset local) {
    final rect = widget.imageRect;
    if (rect.width <= 0 || rect.height <= 0) return Offset.zero;
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  List<Offset> get _points => widget.quad.corners.map(_toLocal).toList();

  void _onPanStart(DragStartDetails details) {
    final position = details.localPosition;
    final points = _points;

    // Corners win over edges when both are in reach.
    var nearest = -1;
    var nearestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (points[i] - position).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    if (nearestDistance <= _handleRadius * 1.8) {
      setState(() {
        _activeCorner = nearest;
        _activeEdge = null;
      });
      HapticFeedback.selectionClick();
      return;
    }

    for (var i = 0; i < 4; i++) {
      final midpoint = (points[i] + points[(i + 1) % 4]) / 2;
      if ((midpoint - position).distance <= _handleRadius * 1.6) {
        setState(() {
          _activeEdge = i;
          _activeCorner = null;
        });
        HapticFeedback.selectionClick();
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final corner = _activeCorner;
    final edge = _activeEdge;

    if (corner != null) {
      widget.onChanged(
        widget.quad.withCorner(corner, _toNormalized(details.localPosition)),
      );
      return;
    }
    if (edge == null) return;

    // Dragging an edge moves both of its corners together.
    final rect = widget.imageRect;
    if (rect.width <= 0 || rect.height <= 0) return;
    final delta = Offset(
      details.delta.dx / rect.width,
      details.delta.dy / rect.height,
    );

    final first = edge;
    final second = (edge + 1) % 4;
    final corners = widget.quad.corners;
    var updated = widget.quad;
    for (final index in [first, second]) {
      final moved = corners[index] + delta;
      updated = updated.withCorner(
        index,
        Offset(moved.dx.clamp(0.0, 1.0), moved.dy.clamp(0.0, 1.0)),
      );
    }
    widget.onChanged(updated);
  }

  void _onPanEnd() {
    if (_activeCorner != null || _activeEdge != null) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _activeCorner = null;
      _activeEdge = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) => _onPanEnd(),
      onPanCancel: _onPanEnd,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CropFramePainter(
          points: _points,
          activeCorner: _activeCorner,
          activeEdge: _activeEdge,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _CropFramePainter extends CustomPainter {
  _CropFramePainter({
    required this.points,
    required this.activeCorner,
    required this.activeEdge,
    required this.color,
  });

  final List<Offset> points;
  final int? activeCorner;
  final int? activeEdge;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final path = Path()..addPolygon(points, true);

    // Darken outside the crop so the selection reads clearly against the page.
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addPath(path, Offset.zero)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    _drawThirds(canvas, path);

    // Edge midpoint handles, for nudging one side without chasing a corner.
    for (var i = 0; i < 4; i++) {
      final midpoint = (points[i] + points[(i + 1) % 4]) / 2;
      _drawHandle(canvas, midpoint, active: activeEdge == i, radius: 7);
    }
    for (var i = 0; i < 4; i++) {
      _drawHandle(canvas, points[i], active: activeCorner == i, radius: 11);
    }
  }

  /// Rule-of-thirds guides inside the quad, which make it obvious when an
  /// edge is not parallel to the page.
  void _drawThirds(Canvas canvas, Path path) {
    canvas.save();
    canvas.clipPath(path);
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final t = i / 3;
      canvas.drawLine(
        Offset.lerp(points[0], points[3], t)!,
        Offset.lerp(points[1], points[2], t)!,
        guide,
      );
      canvas.drawLine(
        Offset.lerp(points[0], points[1], t)!,
        Offset.lerp(points[3], points[2], t)!,
        guide,
      );
    }
    canvas.restore();
  }

  void _drawHandle(
    Canvas canvas,
    Offset centre, {
    required bool active,
    required double radius,
  }) {
    final scale = active ? 1.35 : 1.0;
    canvas.drawCircle(
      centre,
      radius * scale + 2,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(centre, radius * scale, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      radius * scale,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, radius * 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _CropFramePainter old) =>
      !listEquals(old.points, points) ||
      old.activeCorner != activeCorner ||
      old.activeEdge != activeEdge ||
      old.color != color;
}
