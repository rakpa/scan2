import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';
import 'package:scan2/features/auth/presentation/create_account_screen.dart';
import 'package:scan2/features/auth/presentation/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The auth screens are the only thing standing between a first launch and
/// the app, so Skip has to actually unlock it — not just navigate away and
/// leave the router's gate bouncing the user back.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpAuth(WidgetTester tester, String start) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/signup',
          builder: (_, _) => const CreateAccountScreen(),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/library',
          builder: (_, _) => const Scaffold(body: Text('LIBRARY')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final route in const ['/signup', '/login']) {
    testWidgets('Skip on $route enters the app without an account', (
      tester,
    ) async {
      final container = await pumpAuth(tester, route);
      expect(container.read(authProvider).signedIn, isFalse);

      final skip = find.widgetWithText(TextButton, 'Skip');
      expect(skip, findsOneWidget);

      // Top right: above the form, right of centre.
      final box = tester.getRect(skip);
      expect(
        box.center.dx,
        greaterThan(tester.getSize(find.byType(MaterialApp)).width / 2),
      );
      expect(box.top, lessThan(140));

      await tester.tap(skip);
      await tester.pumpAndSettle();

      expect(container.read(authProvider).signedIn, isTrue);
      expect(find.text('LIBRARY'), findsOneWidget);
    });
  }
}
