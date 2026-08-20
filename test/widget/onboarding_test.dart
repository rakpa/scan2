import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_screen.dart';
import 'package:scan2/features/onboarding/presentation/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({required String location, required Widget screen}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/welcome', builder: (_, __) => screen),
      GoRoute(path: '/onboarding', builder: (_, __) => screen),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const Text('signup-home'),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('splash matches the Scanella welcome snip', (tester) async {
    await tester.pumpWidget(
      _app(location: '/welcome', screen: const WelcomeScreen()),
    );
    await tester.pump();

    expect(find.text('Scanella'), findsOneWidget);
    expect(find.text('Scan. Save. Simplify.'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('splash opens onboarding after the hold', (tester) async {
    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const Text('onboarding-home'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(WelcomeScreen.hold);
    await tester.pump();

    expect(find.text('onboarding-home'), findsOneWidget);
  });

  testWidgets('onboarding shows the three snip screens', (tester) async {
    await tester.pumpWidget(
      _app(location: '/onboarding', screen: const OnboardingScreen()),
    );
    await tester.pump();

    expect(find.text('Skip'), findsWidgets);
    expect(find.textContaining('Scan Anything'), findsOneWidget);
    expect(
      find.text('Scan documents, receipts, notes and more with ease.'),
      findsOneWidget,
    );
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save & Organize'), findsOneWidget);
    expect(
      find.text('Keep everything organized and easy to find.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save to Files & Gallery'), findsOneWidget);
    expect(
      find.text('Save your scans to Files or Gallery for easy access anytime.'),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('skip leaves onboarding without requiring Get Started', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(location: '/onboarding', screen: const OnboardingScreen()),
    );
    await tester.pump();

    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();

    expect(find.text('signup-home'), findsOneWidget);
  });
}
