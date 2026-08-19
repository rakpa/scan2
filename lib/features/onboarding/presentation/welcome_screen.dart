import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/illustrations.dart';

/// Screen 1 — the first thing a new install shows.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      const ScanellaAppMark(size: 112),
                      const SizedBox(height: 20),
                      const ScanellaWordmark(fontSize: 46),
                      const SizedBox(height: 6),
                      const Text(
                        'Document Scanner',
                        style: TextStyle(
                          fontSize: 18,
                          color: Brand.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _Rule(),
                      const SizedBox(height: 18),
                      const Text(
                        'Scan anything. Save everything.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Brand.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Simple. Fast. Secure.',
                        style: TextStyle(fontSize: 16, color: Brand.grey),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 312,
                        child: HeroStage(
                          centre: const ScannerDevice(),
                          chips: const [
                            HeroChip(
                              x: 0.13,
                              y: 0.30,
                              icon: Icons.picture_as_pdf_rounded,
                              color: Brand.pdfRed,
                              label: 'PDF',
                            ),
                            HeroChip(
                              x: 0.88,
                              y: 0.38,
                              icon: Icons.description_rounded,
                              color: Brand.docBlue,
                            ),
                            HeroChip(
                              x: 0.09,
                              y: 0.60,
                              icon: Icons.image_rounded,
                              color: Brand.imageGreen,
                            ),
                            HeroChip(
                              x: 0.87,
                              y: 0.70,
                              icon: Icons.cloud_rounded,
                              color: Brand.cloudBlue,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 12),
                      BrandButton(
                        label: 'Get Started',
                        onPressed: () => context.go('/onboarding'),
                      ),
                      const SizedBox(height: 14),
                      _FooterPrompt(
                        prompt: 'Already have an account?',
                        action: 'Login',
                        onTap: () => context.go('/login'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 46, height: 2, color: Brand.outline),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Brand.blue,
            shape: BoxShape.circle,
          ),
        ),
        Container(width: 46, height: 2, color: Brand.outline),
      ],
    );
  }
}

/// "Already have an account? Login" — the split-colour prompt used on the
/// welcome, sign-up and login screens.
class _FooterPrompt extends StatelessWidget {
  const _FooterPrompt({
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
        Text(prompt, style: const TextStyle(color: Brand.grey, fontSize: 15)),
        const SizedBox(width: 5),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: Brand.blue,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared by the auth screens so the prompt style stays identical.
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
  Widget build(BuildContext context) =>
      _FooterPrompt(prompt: prompt, action: action, onTap: onTap);
}
