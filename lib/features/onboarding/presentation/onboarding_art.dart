import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';

/// Document inside blue scanner brackets, as on the white splash snip.
class SplashScannerMark extends StatelessWidget {
  const SplashScannerMark({super.key, this.size = 168});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SplashScannerPainter()),
    );
  }
}

class _SplashScannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()
      ..color = Brand.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.034
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void bracket(Offset origin, double dx, double dy) {
      final arm = size.width * 0.18;
      canvas.drawLine(origin, origin + Offset(dx * arm, 0), blue);
      canvas.drawLine(origin, origin + Offset(0, dy * arm), blue);
    }

    final inset = size.width * 0.06;
    bracket(Offset(inset, inset), 1, 1);
    bracket(Offset(size.width - inset, inset), -1, 1);
    bracket(Offset(inset, size.height - inset), 1, -1);
    bracket(Offset(size.width - inset, size.height - inset), -1, -1);

    final page = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.46,
        height: size.height * 0.58,
      ),
      Radius.circular(size.width * 0.045),
    );
    canvas.drawRRect(
      page,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFDCE8FF)],
        ).createShader(page.outerRect),
    );
    canvas.drawRRect(
      page,
      Paint()
        ..color = const Color(0xFFB7C8EA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.012,
    );

    final rule = Paint()
      ..color = const Color(0xFFB7C8EA)
      ..strokeWidth = size.width * 0.016
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(size.width * 0.36, size.height * (0.36 + i * 0.07)),
        Offset(
          size.width * (i == 1 ? 0.58 : 0.64),
          size.height * (0.36 + i * 0.07),
        ),
        rule,
      );
    }

    final scanY = size.height * 0.52;
    canvas.drawLine(
      Offset(size.width * 0.22, scanY),
      Offset(size.width * 0.78, scanY),
      Paint()
        ..color = Brand.blue
        ..strokeWidth = size.width * 0.028
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Page 1 — phone hovering over a stack of pages on a scanner base.
class ScanAnythingArt extends StatelessWidget {
  const ScanAnythingArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _ScanAnythingPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _ScanAnythingPainter extends CustomPainter {
  const _ScanAnythingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Scanner base.
    final base = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.82),
        width: w * 0.72,
        height: h * 0.16,
      ),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(
      base.shift(Offset(0, h * 0.012)),
      Paint()
        ..color = Brand.blue.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(base, Paint()..color = Brand.blue);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.795),
          width: w * 0.58,
          height: h * 0.045,
        ),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = const Color(0xFF4D7DFF),
    );

    void sheet(Rect rect, double angle, Color fill) {
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(angle);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w * 0.02)),
        Paint()
          ..color = Brand.ink.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w * 0.02)),
        Paint()..color = fill,
      );
      canvas.restore();
    }

    sheet(
      Rect.fromCenter(center: Offset(w * 0.46, h * 0.64), width: w * 0.42, height: h * 0.22),
      -0.12,
      const Color(0xFFE8EEF8),
    );
    sheet(
      Rect.fromCenter(center: Offset(w * 0.54, h * 0.62), width: w * 0.42, height: h * 0.22),
      0.10,
      Colors.white,
    );
    final page = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.60),
      width: w * 0.40,
      height: h * 0.22,
    );
    sheet(page, 0.02, Colors.white);
    final rule = Paint()..color = const Color(0xFFD3DBEA);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          page.left + w * 0.04,
          page.top + h * 0.05 + i * h * 0.035,
          w * (i.isEven ? 0.28 : 0.20),
          h * 0.012,
        ),
        rule,
      );
    }

    // Phone, slightly tilted.
    canvas.save();
    canvas.translate(w * 0.50, h * 0.34);
    canvas.rotate(-0.08);
    canvas.translate(-w * 0.50, -h * 0.34);
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.34),
        width: w * 0.34,
        height: h * 0.52,
      ),
      Radius.circular(w * 0.07),
    );
    canvas.drawRRect(
      phone.shift(Offset(w * 0.012, h * 0.012)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(phone, Paint()..color = const Color(0xFF0F1C3A));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.34),
          width: w * 0.30,
          height: h * 0.48,
        ),
        Radius.circular(w * 0.055),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, h * 0.14, w * 0.20, h * 0.16),
        Radius.circular(w * 0.012),
      ),
      Paint()..color = const Color(0xFFDDE5F2),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          w * 0.40,
          h * 0.34 + i * h * 0.028,
          w * (i.isEven ? 0.20 : 0.14),
          h * 0.010,
        ),
        rule,
      );
    }
    canvas.restore();

    _chip(canvas, Offset(w * 0.16, h * 0.30), Brand.docBlue, Icons.description_rounded, w);
    _chip(canvas, Offset(w * 0.86, h * 0.24), const Color(0xFFF5C542), Icons.insert_drive_file_rounded, w);
    _chip(canvas, Offset(w * 0.84, h * 0.52), Brand.imageGreen, Icons.image_rounded, w);
  }

  void _chip(Canvas canvas, Offset c, Color color, IconData icon, double w) {
    final r = w * 0.075;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCircle(center: c, radius: r),
      Radius.circular(r * 0.42),
    );
    canvas.drawRRect(
      rect.shift(const Offset(0, 4)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: r * 0.95,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Page 2 — blue folder packed with documents and a PDF badge.
class SaveOrganizeArt extends StatelessWidget {
  const SaveOrganizeArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _SaveOrganizePainter(),
      child: SizedBox.expand(),
    );
  }
}

class _SaveOrganizePainter extends CustomPainter {
  const _SaveOrganizePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void paper(Rect rect, double angle, Color fill) {
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(angle);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w * 0.02)),
        Paint()..color = fill,
      );
      canvas.restore();
    }

    paper(
      Rect.fromCenter(center: Offset(w * 0.42, h * 0.34), width: w * 0.42, height: h * 0.36),
      -0.18,
      const Color(0xFFE7EDF8),
    );
    paper(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.32), width: w * 0.42, height: h * 0.36),
      0.16,
      Colors.white,
    );

    final front = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.34),
      width: w * 0.40,
      height: h * 0.36,
    );
    paper(front, 0.04, Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(front.left + w * 0.04, front.top + h * 0.04, w * 0.16, h * 0.055),
        Radius.circular(w * 0.012),
      ),
      Paint()..color = Brand.pdfRed,
    );
    final pdf = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      )
      ..layout();
    pdf.paint(canvas, Offset(front.left + w * 0.055, front.top + h * 0.048));

    final rule = Paint()..color = const Color(0xFFD3DBEA);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          front.left + w * 0.04,
          front.top + h * 0.13 + i * h * 0.04,
          w * (i.isEven ? 0.26 : 0.18),
          h * 0.012,
        ),
        rule,
      );
    }

    final folder = Path()
      ..moveTo(w * 0.16, h * 0.48)
      ..lineTo(w * 0.34, h * 0.48)
      ..lineTo(w * 0.40, h * 0.54)
      ..lineTo(w * 0.84, h * 0.54)
      ..lineTo(w * 0.84, h * 0.86)
      ..lineTo(w * 0.16, h * 0.86)
      ..close();
    canvas.drawPath(
      folder.shift(Offset(0, h * 0.012)),
      Paint()
        ..color = Brand.blue.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawPath(folder, Paint()..color = Brand.blue);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.16, h * 0.58)
        ..lineTo(w * 0.84, h * 0.58)
        ..lineTo(w * 0.84, h * 0.86)
        ..lineTo(w * 0.16, h * 0.86)
        ..close(),
      Paint()..color = const Color(0xFF3D72FF),
    );

    final mini = Offset(w * 0.74, h * 0.80);
    canvas.drawCircle(
      mini,
      w * 0.10,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(mini, w * 0.10, Paint()..color = Colors.white);
    final miniFolder = Path()
      ..moveTo(mini.dx - w * 0.055, mini.dy - h * 0.01)
      ..lineTo(mini.dx - w * 0.018, mini.dy - h * 0.01)
      ..lineTo(mini.dx - w * 0.004, mini.dy + h * 0.008)
      ..lineTo(mini.dx + w * 0.055, mini.dy + h * 0.008)
      ..lineTo(mini.dx + w * 0.055, mini.dy + h * 0.045)
      ..lineTo(mini.dx - w * 0.055, mini.dy + h * 0.045)
      ..close();
    canvas.drawPath(miniFolder, Paint()..color = Brand.blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Page 3 — a finished scan pointing at Files and Gallery.
class SaveToFilesArt extends StatelessWidget {
  const SaveToFilesArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _SaveToFilesPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _SaveToFilesPainter extends CustomPainter {
  const _SaveToFilesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final doc = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.28),
        width: w * 0.36,
        height: h * 0.34,
      ),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(
      doc.shift(const Offset(0, 6)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(doc, Paint()..color = Colors.white);
    canvas.drawRRect(
      doc,
      Paint()
        ..color = Brand.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final rule = Paint()..color = const Color(0xFFD3DBEA);
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          w * 0.38,
          h * 0.18 + i * h * 0.032,
          w * (i.isEven ? 0.24 : 0.16),
          h * 0.012,
        ),
        rule,
      );
    }

    final checkAt = Offset(w * 0.62, h * 0.40);
    canvas.drawCircle(checkAt, w * 0.055, Paint()..color = Brand.imageGreen);
    final check = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(checkAt.dx - w * 0.022, checkAt.dy)
        ..lineTo(checkAt.dx - w * 0.004, checkAt.dy + h * 0.016)
        ..lineTo(checkAt.dx + w * 0.024, checkAt.dy - h * 0.014),
      check,
    );

    final files = Offset(w * 0.24, h * 0.78);
    final gallery = Offset(w * 0.76, h * 0.78);
    final start = Offset(w * 0.42, h * 0.46);
    final startRight = Offset(w * 0.58, h * 0.46);
    _dashCurve(canvas, start, files.translate(0, -h * 0.12));
    _dashCurve(canvas, startRight, gallery.translate(0, -h * 0.12));

    _filesBadge(canvas, files, w, h);
    _galleryBadge(canvas, gallery, w);
  }

  void _dashCurve(Canvas canvas, Offset from, Offset to) {
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2,
        (from.dy + to.dy) / 2 + 12,
        to.dx,
        to.dy,
      );
    final paint = Paint()
      ..color = Brand.greyLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      const dash = 6.0;
      const gap = 5.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  void _filesBadge(Canvas canvas, Offset c, double w, double h) {
    final box = RRect.fromRectAndRadius(
      Rect.fromCircle(center: c, radius: w * 0.13),
      Radius.circular(w * 0.045),
    );
    canvas.drawRRect(
      box.shift(const Offset(0, 4)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xFFE8F0FF));
    final folder = Path()
      ..moveTo(c.dx - w * 0.07, c.dy - h * 0.008)
      ..lineTo(c.dx - w * 0.02, c.dy - h * 0.008)
      ..lineTo(c.dx + w * 0.00, c.dy + h * 0.012)
      ..lineTo(c.dx + w * 0.07, c.dy + h * 0.012)
      ..lineTo(c.dx + w * 0.07, c.dy + h * 0.055)
      ..lineTo(c.dx - w * 0.07, c.dy + h * 0.055)
      ..close();
    canvas.drawPath(folder, Paint()..color = Brand.blue);
  }

  void _galleryBadge(Canvas canvas, Offset c, double w) {
    final box = RRect.fromRectAndRadius(
      Rect.fromCircle(center: c, radius: w * 0.13),
      Radius.circular(w * 0.045),
    );
    canvas.drawRRect(
      box.shift(const Offset(0, 4)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(box, Paint()..color = Colors.white);
    canvas.drawRRect(
      box,
      Paint()
        ..color = Brand.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    const petals = [
      Color(0xFFFF5A7A),
      Color(0xFFFF8A3D),
      Color(0xFFFFD43B),
      Color(0xFF3DDC84),
      Color(0xFF4DC3FF),
      Color(0xFF7A8BFF),
      Color(0xFFC77DFF),
      Color(0xFFFF6AD5),
    ];
    final petalR = w * 0.028;
    for (var i = 0; i < petals.length; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      canvas.drawCircle(
        Offset(c.dx + math.cos(a) * w * 0.055, c.dy + math.sin(a) * w * 0.055),
        petalR,
        Paint()..color = petals[i],
      );
    }
    canvas.drawCircle(c, w * 0.018, Paint()..color = const Color(0xFFFFF4C2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
