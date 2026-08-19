import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';

/// "or continue with" divider plus the three provider buttons.
///
/// The providers are not wired up: each needs its own SDK, an app
/// registration and (for Apple) an entitlement, none of which exist yet. They
/// are shown because the design calls for them, and they say so plainly when
/// tapped rather than failing silently.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({super.key, required this.onUnavailable});

  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: Brand.outline)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'or continue with',
                style: TextStyle(color: Brand.grey, fontSize: 14),
              ),
            ),
            const Expanded(child: Divider(color: Brand.outline)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _ProviderButton(
                label: 'Google',
                mark: _GoogleMark(),
                onTap: () => onUnavailable('Google'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProviderButton(
                label: 'Apple',
                mark: const Icon(Icons.apple, size: 22, color: Brand.ink),
                onTap: () => onUnavailable('Apple'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProviderButton(
                label: 'Facebook',
                mark: const Icon(
                  Icons.facebook,
                  size: 22,
                  color: Color(0xFF1877F2),
                ),
                onTap: () => onUnavailable('Facebook'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.mark,
    required this.onTap,
  });

  final String label;
  final Widget mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusField),
        side: const BorderSide(color: Brand.outline),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              mark,
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Brand.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Google "G" in its four brand colours, drawn rather than bundled so the
/// screen needs no image asset.
class _GoogleMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 21, height: 21, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.26;
    final arc = Rect.fromCircle(
      center: rect.center,
      radius: size.width / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four quadrants in Google's palette.
    canvas.drawArc(
      arc,
      -0.35,
      1.35,
      false,
      paint..color = const Color(0xFF4285F4),
    );
    canvas.drawArc(
      arc,
      1.05,
      1.25,
      false,
      paint..color = const Color(0xFF34A853),
    );
    canvas.drawArc(
      arc,
      2.30,
      1.30,
      false,
      paint..color = const Color(0xFFFBBC05),
    );
    canvas.drawArc(
      arc,
      3.60,
      1.45,
      false,
      paint..color = const Color(0xFFEA4335),
    );

    // The bar of the G.
    canvas.drawRect(
      Rect.fromLTWH(
        rect.center.dx,
        rect.center.dy - stroke / 2,
        size.width / 2 - stroke * 0.15,
        stroke,
      ),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
