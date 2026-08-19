import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/auth/presentation/create_account_screen.dart';
import 'package:scan2/features/auth/presentation/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
  }

  testWidgets('login screen has a Skip control at the top right', (tester) async {
    await pumpScreen(tester, const LoginScreen());

    expect(find.byKey(const Key('auth-skip')), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Welcome Back!'), findsOneWidget);

    final skip = tester.getTopLeft(find.byKey(const Key('auth-skip')));
    final back = tester.getTopLeft(find.byIcon(Icons.chevron_left_rounded));
    expect(skip.dx, greaterThan(back.dx));
  });

  testWidgets('create account screen has a Skip control at the top right',
      (tester) async {
    await pumpScreen(tester, const CreateAccountScreen());

    expect(find.byKey(const Key('auth-skip')), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Join Scanella to scan, save and access\nyour documents anywhere.'), findsOneWidget);

    final skip = tester.getTopLeft(find.byKey(const Key('auth-skip')));
    final back = tester.getTopLeft(find.byIcon(Icons.chevron_left_rounded));
    expect(skip.dx, greaterThan(back.dx));
  });
}
