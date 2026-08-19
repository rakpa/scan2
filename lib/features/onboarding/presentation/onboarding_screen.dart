import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/core/widgets/illustrations.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';

/// Screens 2–3 — the three-page introduction.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(onboardingCompletedProvider.notifier).complete();
    context.go('/signup');
  }

  void _next() {
    if (_page >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 20, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip', style: BrandType.link),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) =>
                    _OnboardingPage(page: _pages[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 10 : 9,
                    height: i == _page ? 10 : 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? Brand.blue : Brand.outline,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: BrandButton(
                label: _page == _pages.length - 1 ? 'Get Started' : 'Next',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page});

  final _PageData page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Brand.ink.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(page.badge, size: 36, color: Brand.blue),
          ),
          const SizedBox(height: 22),
          _SplitHeadline(lead: page.headlineLead, accent: page.headlineAccent),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: BrandType.subtitle,
          ),
          const SizedBox(height: 10),
          if (page.features.isEmpty)
            SizedBox(height: 330, child: page.illustration)
          else
            // Labels ring the illustration, as in the design. Stacking them
            // underneath instead pushed the last row behind the page dots.
            SizedBox(
              height: 372,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: page.illustration,
                  ),
                  Positioned(
                    left: 0,
                    top: 34,
                    child: _FeatureLabel(
                      icon: page.features[0].$1,
                      label: page.features[0].$2,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 34,
                    child: _FeatureLabel(
                      icon: page.features[1].$1,
                      label: page.features[1].$2,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 6,
                    child: _FeatureLabel(
                      icon: page.features[2].$1,
                      label: page.features[2].$2,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 6,
                    child: _FeatureLabel(
                      icon: page.features[3].$1,
                      label: page.features[3].$2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Headline where the last word or two carries the blue accent.
class _SplitHeadline extends StatelessWidget {
  const _SplitHeadline({required this.lead, required this.accent});

  final String lead;
  final String accent;

  @override
  Widget build(BuildContext context) {
    final style = BrandType.display;
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style.copyWith(color: Brand.ink),
        children: [
          TextSpan(text: lead),
          TextSpan(
            text: accent,
            style: style.copyWith(color: Brand.blue),
          ),
        ],
      ),
    );
  }
}

class _FeatureLabel extends StatelessWidget {
  const _FeatureLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Brand.ink.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, size: 22, color: Brand.blue),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: BrandType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: Brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageData {
  const _PageData({
    required this.badge,
    required this.headlineLead,
    required this.headlineAccent,
    required this.body,
    required this.illustration,
    this.features = const [],
  });

  final IconData badge;
  final String headlineLead;
  final String headlineAccent;
  final String body;
  final Widget illustration;
  final List<(IconData, String)> features;
}

final _pages = <_PageData>[
  const _PageData(
    badge: Icons.document_scanner_rounded,
    headlineLead: 'Scan Anything\nin a ',
    headlineAccent: 'Snap',
    body:
        'Turn your phone into a powerful scanner.\n'
        'Fast, clear and easy.',
    illustration: HeroStage(
      centre: ScanningPhone(),
      chips: [
        HeroChip(
          x: 0.10,
          y: 0.36,
          icon: Icons.description_rounded,
          color: Brand.docBlue,
        ),
        HeroChip(
          x: 0.90,
          y: 0.32,
          icon: Icons.picture_as_pdf_rounded,
          color: Brand.pdfRed,
          label: 'PDF',
        ),
        HeroChip(
          x: 0.10,
          y: 0.72,
          icon: Icons.qr_code_2_rounded,
          color: Brand.imageGreen,
          label: 'OCR',
        ),
        HeroChip(
          x: 0.90,
          y: 0.64,
          icon: Icons.cloud_upload_rounded,
          color: Brand.cloudBlue,
        ),
      ],
    ),
  ),
  // Middle page: the design pack did not include this one, so it covers the
  // step between capturing and privacy — what the app does with a scan.
  const _PageData(
    badge: Icons.auto_fix_high_rounded,
    headlineLead: 'Clean Pages,\n',
    headlineAccent: 'Every Time',
    body:
        'Edges are straightened and pages enhanced\n'
        'automatically. Export as PDF or images.',
    illustration: HeroStage(
      centre: ScannerDevice(),
      chips: [
        HeroChip(
          x: 0.10,
          y: 0.32,
          icon: Icons.crop_rounded,
          color: Brand.docBlue,
        ),
        HeroChip(x: 0.90, y: 0.36, icon: Icons.tune_rounded, color: Brand.blue),
        HeroChip(
          x: 0.11,
          y: 0.70,
          icon: Icons.picture_as_pdf_rounded,
          color: Brand.pdfRed,
          label: 'PDF',
        ),
        HeroChip(
          x: 0.89,
          y: 0.72,
          icon: Icons.ios_share_rounded,
          color: Brand.imageGreen,
        ),
      ],
    ),
  ),
  const _PageData(
    badge: Icons.shield_rounded,
    headlineLead: 'Privacy You\nCan ',
    headlineAccent: 'Trust',
    body:
        'Your documents are secure and\n'
        'never shared without your permission.',
    illustration: HeroStage(centre: SecureFolder(), chips: [], showDots: false),
    features: [
      (Icons.lock_rounded, 'Secure\nStorage'),
      (Icons.verified_user_rounded, 'Encrypted\nFiles'),
      (Icons.visibility_off_rounded, 'Private &\nConfidential'),
      (Icons.delete_outline_rounded, "You're in\nControl"),
    ],
  ),
];
