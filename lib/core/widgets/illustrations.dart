import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';

/// Hero illustrations for the welcome and onboarding screens.
///
/// These are flat vector stand-ins for the rendered artwork in the design.
/// They match the composition — a central device ringed by floating file
/// chips on a soft disc — so layout, spacing and balance are correct, and a
/// supplied PNG or SVG can replace the centre piece without moving anything
/// around it.
class HeroStage extends StatelessWidget {
  const HeroStage({
    super.key,
    required this.centre,
    required this.chips,
    this.discColor = const Color(0xFFEDF2FB),
    this.showDots = true,
  });

  /// The device or subject at the middle of the composition.
  final Widget centre;

  /// Floating file chips, positioned as fractions of the stage.
  final List<HeroChip> chips;

  final Color discColor;

  /// The scattered dot grids. Off when labels sit in the corners, where the
  /// dots would otherwise print straight through the text.
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Soft disc and dotted grid behind everything.
            Positioned(
              left: w * 0.10,
              top: h * 0.06,
              width: w * 0.80,
              height: h * 0.80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: discColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            if (showDots) ...[
              Positioned(
                right: 0,
                top: h * 0.02,
                width: w * 0.26,
                height: h * 0.18,
                child: const _DotGrid(),
              ),
              Positioned(
                left: 0,
                bottom: h * 0.06,
                width: w * 0.22,
                height: h * 0.15,
                child: const _DotGrid(),
              ),
            ],
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.16),
                child: centre,
              ),
            ),
            for (final chip in chips)
              Positioned(
                left: chip.x * w - 34,
                top: chip.y * h - 34,
                child: _ChipCard(
                  icon: chip.icon,
                  color: chip.color,
                  label: chip.label,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A floating file chip in a [HeroStage], placed by fractional position.
class HeroChip {
  const HeroChip({
    required this.x,
    required this.y,
    required this.icon,
    required this.color,
    this.label,
  });

  final double x;
  final double y;
  final IconData icon;
  final Color color;
  final String? label;
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.icon, required this.color, this.label});

  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: label == null
          ? Icon(icon, size: 30, color: color)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 2),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DotGrid extends StatelessWidget {
  const _DotGrid();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotGridPainter(), child: const SizedBox.expand());
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Brand.blue.withValues(alpha: 0.16);
    const columns = 7;
    const rows = 5;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        canvas.drawCircle(
          Offset(
            size.width * (c + 0.5) / columns,
            size.height * (r + 0.5) / rows,
          ),
          2,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Centre pieces
// ---------------------------------------------------------------------------

/// An open flatbed scanner with a lit page on the glass.
class ScannerDevice extends StatelessWidget {
  const ScannerDevice({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: CustomPaint(painter: _ScannerDevicePainter()),
    );
  }
}

class _ScannerDevicePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Raised lid, kept shallower than the body so it reads as an open lid
    // rather than a slab standing behind the scanner.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.15, h * 0.06, w * 0.70, h * 0.32),
        Radius.circular(w * 0.045),
      ),
      Paint()..color = const Color(0xFF2A3E63),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.19, h * 0.10, w * 0.62, h * 0.24),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = const Color(0xFF1B2B49),
    );

    // Body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.04, h * 0.46, w * 0.92, h * 0.44),
      Radius.circular(w * 0.055),
    );
    canvas.drawRRect(
      body.shift(Offset(0, h * 0.03)),
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF1B2B49));

    // Glass bed.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.50, w * 0.76, h * 0.26),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = Brand.blue.withValues(alpha: 0.55),
    );

    // The page being scanned, with ruled lines.
    final page = Rect.fromLTWH(w * 0.20, h * 0.49, w * 0.55, h * 0.26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, Radius.circular(w * 0.012)),
      Paint()..color = Colors.white,
    );
    final line = Paint()..color = const Color(0xFFB9C4D8);
    for (var i = 0; i < 6; i++) {
      final y = page.top + page.height * (0.20 + i * 0.13);
      canvas.drawRect(
        Rect.fromLTWH(
          page.left + page.width * 0.10,
          y,
          page.width * (i.isEven ? 0.66 : 0.48),
          h * 0.010,
        ),
        line,
      );
    }

    // Scan light spilling out of the bed.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.12, h * 0.545, w * 0.76, h * 0.012),
      Paint()..color = Brand.blue,
    );

    // Front panel button.
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.845),
      w * 0.035,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.008,
    );
    canvas.drawCircle(
      Offset(w * 0.14, h * 0.845),
      w * 0.018,
      Paint()..color = const Color(0xFF35C759),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A phone with a document on screen and a scan line sweeping across it.
class ScanningPhone extends StatelessWidget {
  const ScanningPhone({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.62,
      child: CustomPaint(painter: _ScanningPhonePainter()),
    );
  }
}

class _ScanningPhonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.13),
    );

    canvas.drawRRect(
      frame.shift(Offset(0, h * 0.015)),
      Paint()
        ..color = Brand.blue.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF16264D));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.035, h * 0.018, w * 0.93, h * 0.964),
        Radius.circular(w * 0.11),
      ),
      Paint()..color = Colors.white,
    );

    // Document on screen: an image block then text lines.
    final doc = Rect.fromLTWH(w * 0.12, h * 0.09, w * 0.76, h * 0.82);
    canvas.drawRect(
      Rect.fromLTWH(doc.left, doc.top, doc.width, doc.height * 0.30),
      Paint()..color = const Color(0xFFDDE5F2),
    );
    canvas.drawCircle(
      Offset(doc.left + doc.width * 0.30, doc.top + doc.height * 0.11),
      w * 0.045,
      Paint()..color = Colors.white,
    );

    final line = Paint()..color = const Color(0xFFD3DBEA);
    for (var i = 0; i < 9; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          doc.left,
          doc.top + doc.height * (0.38 + i * 0.068),
          doc.width * (i.isEven ? 1.0 : 0.72),
          h * 0.012,
        ),
        line,
      );
    }

    // Corner brackets and the sweeping scan line.
    final bracket = Paint()..color = Brand.blue;
    for (final corner in [
      Offset(doc.left, doc.top),
      Offset(doc.right, doc.top),
      Offset(doc.left, doc.bottom),
      Offset(doc.right, doc.bottom),
    ]) {
      canvas.drawCircle(corner, w * 0.028, bracket);
    }
    canvas.drawRect(
      Rect.fromLTWH(w * 0.02, h * 0.50, w * 0.96, h * 0.008),
      bracket,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.02, h * 0.50 - h * 0.03, w * 0.96, h * 0.03),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Brand.blue.withValues(alpha: 0),
            Brand.blue.withValues(alpha: 0.28),
          ],
        ).createShader(Rect.fromLTWH(w * 0.02, h * 0.47, w * 0.96, h * 0.03)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A folder holding documents, with a padlock shield in front of it.
class SecureFolder extends StatelessWidget {
  const SecureFolder({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.05,
      child: CustomPaint(painter: _SecureFolderPainter()),
    );
  }
}

class _SecureFolderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sheets peeking out of the folder.
    for (var i = 0; i < 2; i++) {
      final inset = w * (0.20 + i * 0.05);
      canvas.save();
      canvas.translate(w * 0.5, h * 0.44);
      canvas.rotate((i == 0 ? -1 : 1) * 0.07);
      canvas.translate(-w * 0.5, -h * 0.44);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, h * 0.18, w - inset * 2, h * 0.46),
          Radius.circular(w * 0.02),
        ),
        Paint()..color = i == 0 ? const Color(0xFFE7EDF8) : Colors.white,
      );
      canvas.restore();
    }

    // Front sheet with a CONFIDENTIAL tag and ruled lines.
    final sheet = Rect.fromLTWH(w * 0.24, h * 0.20, w * 0.52, h * 0.44);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheet, Radius.circular(w * 0.02)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          sheet.left + w * 0.03,
          sheet.top + h * 0.04,
          w * 0.26,
          h * 0.055,
        ),
        Radius.circular(w * 0.012),
      ),
      Paint()..color = Brand.blue,
    );
    final line = Paint()..color = const Color(0xFFD3DBEA);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          sheet.left + w * 0.03,
          sheet.top + h * 0.14 + i * h * 0.055,
          w * (i.isEven ? 0.34 : 0.24),
          h * 0.016,
        ),
        line,
      );
    }

    // Folder body in front.
    final folder = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.10, h * 0.44, w * 0.80, h * 0.44),
      topLeft: Radius.circular(w * 0.04),
      topRight: Radius.circular(w * 0.04),
      bottomLeft: Radius.circular(w * 0.06),
      bottomRight: Radius.circular(w * 0.06),
    );
    canvas.drawRRect(
      folder.shift(Offset(0, h * 0.02)),
      Paint()
        ..color = Brand.blue.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(folder, Paint()..color = Brand.blue);

    // Shield with a padlock, overlapping the folder's lower right.
    final centre = Offset(w * 0.68, h * 0.80);
    final shield = Path()
      ..moveTo(centre.dx, centre.dy - h * 0.16)
      ..lineTo(centre.dx + w * 0.13, centre.dy - h * 0.09)
      ..lineTo(centre.dx + w * 0.13, centre.dy + h * 0.02)
      ..quadraticBezierTo(
        centre.dx + w * 0.13,
        centre.dy + h * 0.13,
        centre.dx,
        centre.dy + h * 0.17,
      )
      ..quadraticBezierTo(
        centre.dx - w * 0.13,
        centre.dy + h * 0.13,
        centre.dx - w * 0.13,
        centre.dy + h * 0.02,
      )
      ..lineTo(centre.dx - w * 0.13, centre.dy - h * 0.09)
      ..close();
    canvas.drawPath(
      shield,
      Paint()
        ..color = Brand.ink.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(shield, Paint()..color = Colors.white);

    final lockBody = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: centre.translate(0, h * 0.015),
        width: w * 0.115,
        height: h * 0.085,
      ),
      Radius.circular(w * 0.018),
    );
    canvas.drawRRect(lockBody, Paint()..color = Brand.blue);
    canvas.drawArc(
      Rect.fromCenter(
        center: centre.translate(0, -h * 0.035),
        width: w * 0.075,
        height: h * 0.075,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = Brand.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
