import 'package:flutter/material.dart';

/// Design tokens taken from the Scanella mockups.
///
/// Values are named after their role rather than their hue so screens read as
/// intent ("brand", "ink") and a palette change lands in one place.
class Brand {
  const Brand._();

  /// The blue used for primary buttons, links and the accent half of the
  /// wordmark.
  static const blue = Color(0xFF1F5FFF);
  static const blueDark = Color(0xFF1246CC);

  /// Near-black navy used for headings and the first half of the wordmark.
  static const ink = Color(0xFF0B1B3F);
  static const inkSoft = Color(0xFF16264D);

  /// Body copy and secondary labels.
  static const grey = Color(0xFF6B7385);
  static const greyLight = Color(0xFF9AA1B1);

  /// Page and card surfaces.
  static const surface = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF7F9FC);

  /// Input and card outlines.
  static const outline = Color(0xFFE3E8F0);

  /// Accents used by the file chips in the hero illustrations.
  static const pdfRed = Color(0xFFE8443A);
  static const docBlue = Color(0xFF2C7BE5);
  static const imageGreen = Color(0xFF16A75C);
  static const cloudBlue = Color(0xFF3A8DFF);

  static const radiusField = 14.0;
  static const radiusButton = 14.0;
  static const fieldHeight = 58.0;
  static const buttonHeight = 58.0;
}

/// The "Scanella" wordmark: navy "Scan", blue "ella".
class ScanellaWordmark extends StatelessWidget {
  const ScanellaWordmark({super.key, this.fontSize = 44});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.05,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style.copyWith(color: Brand.ink),
        children: [
          const TextSpan(text: 'Scan'),
          TextSpan(
            text: 'ella',
            style: style.copyWith(color: Brand.blue),
          ),
        ],
      ),
    );
  }
}

/// The rounded app mark: a blue tile holding a flatbed scanner.
class ScanellaAppMark extends StatelessWidget {
  const ScanellaAppMark({super.key, this.size = 116});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.235),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.blue, Brand.blueDark],
        ),
        boxShadow: [
          BoxShadow(
            color: Brand.blue.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.19),
        child: CustomPaint(painter: _ScannerMarkPainter()),
      ),
    );
  }
}

/// A flatbed scanner: a lid above, a body below, a sheet showing through.
class _ScannerMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final shade = Paint()..color = const Color(0xFFD9E2F2);
    final r = Radius.circular(size.width * 0.09);

    // Lid.
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.06,
        0,
        size.width * 0.88,
        size.height * 0.40,
      ),
      r,
    );
    canvas.drawRRect(lid, white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.14,
          size.height * 0.07,
          size.width * 0.72,
          size.height * 0.24,
        ),
        Radius.circular(size.width * 0.05),
      ),
      shade,
    );

    // Body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.46, size.width, size.height * 0.42),
      r,
    );
    canvas.drawRRect(body, white);

    // Glass with the page on it.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.10,
          size.height * 0.52,
          size.width * 0.80,
          size.height * 0.22,
        ),
        Radius.circular(size.width * 0.04),
      ),
      Paint()..color = const Color(0xFF12306B),
    );

    // Status lights.
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.81),
      size.width * 0.033,
      Paint()..color = const Color(0xFF35C759),
    );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.81),
      size.width * 0.033,
      Paint()..color = Brand.blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Primary full-width action button from the mockups: solid blue, bold label,
/// optional trailing arrow.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.showArrow = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool showArrow;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: Brand.buttonHeight,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Brand.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Brand.blue.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusButton),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showArrow) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 21),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Bordered text field matching the mockups: leading grey icon, hint text,
/// generous height.
class BrandField extends StatelessWidget {
  const BrandField({
    super.key,
    required this.hint,
    required this.icon,
    this.controller,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.trailing,
    this.validator,
    this.autofillHints,
  });

  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Widget? trailing;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      autofillHints: autofillHints,
      style: const TextStyle(fontSize: 16, color: Brand.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Brand.greyLight, fontSize: 16),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Icon(icon, size: 21, color: Brand.greyLight),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: trailing,
        filled: true,
        fillColor: Brand.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 19),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radiusField),
          borderSide: const BorderSide(color: Brand.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radiusField),
          borderSide: const BorderSide(color: Brand.blue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radiusField),
          borderSide: const BorderSide(color: Brand.pdfRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radiusField),
          borderSide: const BorderSide(color: Brand.pdfRed, width: 1.6),
        ),
      ),
    );
  }
}
