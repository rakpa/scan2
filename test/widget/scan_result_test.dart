import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';

Uint8List _tinyJpeg() {
  final image = img.Image(width: 24, height: 32);
  img.fill(image, color: img.ColorRgb8(248, 248, 252));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

ScanResultArgs _args() {
  return ScanResultArgs(
    pages: [
      ScanResultPageDraft(
        originalPath: '/tmp/scanella_missing_original.jpg',
        bytes: _tinyJpeg(),
        quad: const Quad.fullFrame(),
        adjustments: const ScanAdjustments(filter: ScanFilter.magic),
      ),
    ],
  );
}

Widget _app(ScanResultArgs args) {
  final router = GoRouter(
    initialLocation: '/scan-result',
    routes: [
      GoRoute(path: '/library', builder: (_, __) => const Text('library-home')),
      GoRoute(path: '/camera', builder: (_, __) => const Text('camera-home')),
      GoRoute(
        path: '/scan-result',
        builder: (_, __) => ScanResultScreen(args: args),
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

  testWidgets('scan result shows branding, presets and edit actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_args()));
    await tester.pump();

    expect(find.byType(ScanellaWordmark), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Auto-detect'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);

    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Auto Enhance'), findsOneWidget);
    expect(find.text('B&W'), findsOneWidget);
    expect(find.text('Magic Color'), findsOneWidget);
    expect(find.text('Grayscale'), findsOneWidget);

    expect(find.text('Crop'), findsWidgets);
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
  });

  testWidgets('back leaves without saving', (tester) async {
    await tester.pumpWidget(_app(_args()));
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('library-home'), findsOneWidget);
    expect(find.byType(ScanResultScreen), findsNothing);
  });

  testWidgets('retake returns to the camera without saving', (tester) async {
    await tester.pumpWidget(_app(_args()));
    await tester.pump();

    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();

    expect(find.text('camera-home'), findsOneWidget);
    expect(find.byType(ScanResultScreen), findsNothing);
  });

  testWidgets('rotate and filter actions stay on the review screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_args()));
    await tester.pump();

    await tester.tap(find.text('Rotate'));
    await tester.pump();
    expect(find.byType(ScanResultScreen), findsOneWidget);

    await tester.tap(find.text('Filter'));
    await tester.pump();
    expect(find.text('Auto Enhance'), findsOneWidget);

    await tester.tap(find.text('B&W'));
    await tester.pump();
    expect(find.text('B&W'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
