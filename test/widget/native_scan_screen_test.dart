import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/permissions/camera_permission.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/camera/domain/native_document_scanner.dart';
import 'package:scan2/features/camera/presentation/native_scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first-open permission clash is a retry, not a stack dump', (
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
                builder: (_, __) =>
                    NativeScanScreen(scanner: _ThrowingScanner()),
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
    await tester.pump();

    expect(
      find.text('The camera is still asking for permission. Tap Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('ERROR_ALREADY_REQUESTING'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
  });
}

class _ThrowingScanner extends NativeDocumentScanner {
  @override
  Future<List<String>?> scan({int maxPages = 24}) async {
    throw PlatformException(
      code: CameraPermission.alreadyRequestingCode,
      message:
          'A request for permissions is already running, please wait for it '
          'to finish before doing another request',
    );
  }
}
