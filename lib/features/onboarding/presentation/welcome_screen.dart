import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_art.dart';

/// First-install splash — blue stage, scanner mark, wordmark, tagline.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  static const hold = Duration(milliseconds: 1800);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _hold = Timer(WelcomeScreen.hold, _openOnboarding);
  }

  void _openOnboarding() {
    if (!mounted) return;
    context.go('/onboarding');
  }

  @override
  void dispose() {
    _hold?.cancel();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Brand.blue,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 5),
              const SplashScannerMark(size: 176),
              const SizedBox(height: 28),
              const Text(
                'Scanella',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Scan. Save. Simplify.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(flex: 4),
              _SplashDots(animation: _dots),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashDots extends StatelessWidget {
  const _SplashDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return CustomPaint(
            painter: _SplashDotsPainter(animation.value),
          );
        },
      ),
    );
  }
}

class _SplashDotsPainter extends CustomPainter {
  _SplashDotsPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 12;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;
    for (var i = 0; i < count; i++) {
      final phase = (t * count + i) % count;
      final alpha = 0.22 + 0.78 * (1 - (phase / count));
      final angle = -1.5708 + (i / count) * 6.2832;
      canvas.drawCircle(
        Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)),
        3.1,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashDotsPainter oldDelegate) =>
      oldDelegate.t != t;
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
