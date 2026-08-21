import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/home/presentation/home_screen.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/ocr/domain/ocr_args.dart';
import 'package:scan2/features/ocr/presentation/ocr_flow.dart';
import 'package:scan2/features/ocr/presentation/ocr_result_screen.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _tinyJpeg() {
  final image = img.Image(width: 24, height: 32);
  img.fill(image, color: img.ColorRgb8(248, 248, 252));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('OCR on home opens a full source sheet, not a crop dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HomeScreen(
            onOpenMenu: () {},
            onViewAllDocuments: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OCR Text'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Scan Photos'), findsOneWidget);

    await tester.tap(find.text('OCR Text'));
    await tester.pumpAndSettle();

    expect(find.byType(OcrSourceSheet), findsOneWidget);
    expect(find.text('Scan page'), findsOneWidget);
    expect(find.text('Choose photos'), findsOneWidget);
    expect(find.text('Import files'), findsOneWidget);
    expect(find.text('Adjust edges'), findsNothing);
  });

  testWidgets('home shortcut cards keep their subtitles on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HomeScreen(
            onOpenMenu: () {},
            onViewAllDocuments: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final ocr = tester.getRect(find.text('OCR Text'));
    final import = tester.getRect(find.text('Import Files'));
    expect(ocr.top, closeTo(import.top, 1));
    expect(
      tester.getRect(find.text('Copy text from a photo or PDF.')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('OCR Text')).bottom + 80),
    );
  });

  testWidgets('OCR result shows the extracted text instead of crop tools', (
    tester,
  ) async {
    final bytes = _tinyJpeg();
    final args = OcrArgs(
      pages: [
        OcrPageResult(
          page: ProcessedPage(
            originalPath: '/tmp/missing.jpg',
            bytes: bytes,
            quad: const Quad.fullFrame(),
            adjustments: const ScanAdjustments(),
          ),
          text: 'Total due 12.50',
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/ocr-result',
      routes: [
        GoRoute(path: '/library', builder: (_, __) => const Text('library-home')),
        GoRoute(
          path: '/ocr-result',
          builder: (_, __) => OcrResultScreen(args: args),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OCR Text'), findsOneWidget);
    expect(find.text('Total due 12.50'), findsOneWidget);
    expect(find.text('Share text'), findsOneWidget);
    expect(find.text('Crop'), findsNothing);
    expect(find.text('Adjust edges'), findsNothing);
  });

  testWidgets('imported scans hide Retake so the crop bar is not cramped', (
    tester,
  ) async {
    final args = ScanResultArgs(
      allowRetake: false,
      pages: [
        ScanResultPageDraft(
          originalPath: '/tmp/scanella_missing_original.jpg',
          bytes: _tinyJpeg(),
          quad: const Quad.fullFrame(),
          adjustments: const ScanAdjustments(filter: ScanFilter.magic),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/scan-result',
      routes: [
        GoRoute(path: '/library', builder: (_, __) => const Text('library-home')),
        GoRoute(
          path: '/scan-result',
          builder: (_, __) => ScanResultScreen(args: args),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Crop'), findsWidgets);
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.text('Retake'), findsNothing);
  });
}
