import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_art.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';

/// The three first-run pages from the Scanella snip.
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
    final last = _page == _pages.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: Brand.ink,
                      textStyle: BrandType.link.copyWith(color: Brand.ink),
                    ),
                    child: const Text('Skip'),
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
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? Brand.blue
                            : Brand.ink.withValues(alpha: 0.16),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: Brand.ink,
                        textStyle: BrandType.button.copyWith(
                          color: Brand.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Skip'),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.blue,
                          foregroundColor: Colors.white,
                          minimumSize: Size(last ? 168 : 108, 52),
                          padding: EdgeInsets.symmetric(
                            horizontal: last ? 26 : 28,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: BrandType.button.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        child: Text(last ? 'Get Started' : 'Next'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: Column(
        children: [
          _SplitHeadline(lead: page.headlineLead, accent: page.headlineAccent),
          const SizedBox(height: 10),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: BrandType.body.copyWith(
              color: Brand.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: page.illustration,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitHeadline extends StatelessWidget {
  const _SplitHeadline({required this.lead, required this.accent});

  final String lead;
  final String accent;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.2,
    );
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

class _PageData {
  const _PageData({
    required this.headlineLead,
    required this.headlineAccent,
    required this.body,
    required this.illustration,
  });

  final String headlineLead;
  final String headlineAccent;
  final String body;
  final Widget illustration;
}

const _pages = <_PageData>[
  _PageData(
    headlineLead: 'Scan ',
    headlineAccent: 'Anything',
    body: 'Scan documents, receipts, notes and more with ease.',
    illustration: ScanAnythingArt(),
  ),
  _PageData(
    headlineLead: 'Save & ',
    headlineAccent: 'Organize',
    body: 'Keep everything organized and easy to find.',
    illustration: SaveOrganizeArt(),
  ),
  _PageData(
    headlineLead: 'Save to ',
    headlineAccent: 'Files & Gallery',
    body: 'Save your scans to Files or Gallery for easy access anytime.',
    illustration: SaveToFilesArt(),
  ),
];
