import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/camera/presentation/camera_screen.dart';
import 'package:scan2/features/camera/presentation/native_scan_screen.dart';
import 'package:scan2/features/settings/presentation/settings_screen.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('settings keep system auto-edge as the default scan path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Use the in-app camera'), findsOneWidget);
    expect(find.text('System document scanner'), findsNothing);

    final toggle = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Use the in-app camera'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('Scan opens the system scanner unless in-app camera is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: GoRouter(
            initialLocation: '/camera',
            routes: [
              GoRoute(
                path: '/camera',
                builder: (context, state) {
                  // Mirrors app_router.dart: platform scanner is default.
                  final container = ProviderScope.containerOf(context);
                  final inApp = container.read(settingsProvider).useInAppCamera;
                  return inApp
                      ? const CameraScreen()
                      : const NativeScanScreen();
                },
              ),
              GoRoute(
                path: '/library',
                builder: (_, __) => const Text('library-home'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NativeScanScreen), findsOneWidget);
    expect(find.byType(CameraScreen), findsNothing);
  });
}
