import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_art.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';

/// First splash — white stage from the Scanella snip.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  static const hold = Duration(milliseconds: 1800);

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _hold = Timer(WelcomeScreen.hold, () => unawaited(_continue()));
  }

  Future<void> _continue() async {
    await Future.wait([
      ref.read(onboardingCompletedProvider.notifier).ready,
      ref.read(authProvider.notifier).ready,
    ]);
    if (!mounted) return;
    final seenIntro = ref.read(onboardingCompletedProvider);
    if (!seenIntro) {
      context.go('/onboarding');
      return;
    }
    final signedIn = ref.read(authProvider).signedIn;
    context.go(signedIn ? '/library' : '/signup');
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const SplashIconPattern(),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 5),
                  const SplashScannerMark(size: 168),
                  const SizedBox(height: 28),
                  const ScanellaWordmark(fontSize: 40),
                  const SizedBox(height: 10),
                  Text(
                    'Scan Anything, Save Everything.',
                    textAlign: TextAlign.center,
                    style: BrandType.subtitle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(flex: 4),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      color: Brand.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading...',
                    style: BrandType.caption.copyWith(color: Brand.greyLight),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Already have an account? Login" — used on sign-up and login.
class AuthFooterPrompt extends StatelessWidget {
  const AuthFooterPrompt({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: BrandType.subtitle),
        const SizedBox(width: 5),
        GestureDetector(
          onTap: onTap,
          child: Text(action, style: BrandType.link),
        ),
      ],
    );
  }
}

/// Faint document / photo / ID glyphs behind the splash branding.
class SplashIconPattern extends StatelessWidget {
  const SplashIconPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _SplashPatternPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _SplashPatternPainter extends CustomPainter {
  const _SplashPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Brand.blue.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    void document(Offset c, double s, double angle) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: s * 0.72, height: s),
        Radius.circular(s * 0.08),
      );
      canvas.drawRRect(r, paint);
      canvas.drawLine(
        Offset(-s * 0.18, -s * 0.22),
        Offset(s * 0.18, -s * 0.22),
        paint,
      );
      canvas.drawLine(
        Offset(-s * 0.18, -s * 0.06),
        Offset(s * 0.10, -s * 0.06),
        paint,
      );
      canvas.restore();
    }

    void photo(Offset c, double s) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: s, height: s * 0.78),
        Radius.circular(s * 0.12),
      );
      canvas.drawRRect(r, paint);
      canvas.drawCircle(c + Offset(-s * 0.18, -s * 0.08), s * 0.08, paint);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * 0.32, c.dy + s * 0.22)
          ..lineTo(c.dx - s * 0.05, c.dy - s * 0.02)
          ..lineTo(c.dx + s * 0.12, c.dy + s * 0.12)
          ..lineTo(c.dx + s * 0.32, c.dy - s * 0.06),
        paint,
      );
    }

    void idCard(Offset c, double s) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: s * 1.15, height: s * 0.72),
        Radius.circular(s * 0.10),
      );
      canvas.drawRRect(r, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: c + Offset(-s * 0.28, 0),
            width: s * 0.28,
            height: s * 0.36,
          ),
          Radius.circular(s * 0.06),
        ),
        paint,
      );
      canvas.drawLine(
        c + Offset(-s * 0.02, -s * 0.10),
        c + Offset(s * 0.38, -s * 0.10),
        paint,
      );
      canvas.drawLine(
        c + Offset(-s * 0.02, s * 0.08),
        c + Offset(s * 0.28, s * 0.08),
        paint,
      );
    }

    final w = size.width;
    final h = size.height;
    document(Offset(w * 0.14, h * 0.16), 42, -0.18);
    photo(Offset(w * 0.86, h * 0.14), 40);
    idCard(Offset(w * 0.18, h * 0.42), 36);
    document(Offset(w * 0.90, h * 0.38), 38, 0.22);
    photo(Offset(w * 0.12, h * 0.72), 36);
    document(Offset(w * 0.88, h * 0.70), 44, -0.12);
    idCard(Offset(w * 0.78, h * 0.88), 34);
    document(Offset(w * 0.28, h * 0.90), 40, 0.16);
    photo(Offset(w * 0.52, h * 0.12), 28);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
