import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/scan/presentation/document_saved_screen.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved screen shows filename, metadata and done', (tester) async {
    final doc = Document(
      id: 7,
      title: 'Scan_2024-05-18',
      createdAt: DateTime(2024, 5, 18, 9, 30),
      pages: const [ScanPage(path: '/tmp/missing-page.jpg')],
      pdfPath: '/tmp/scan_2024-05-18.pdf',
      fileSizeBytes: 2048,
      documentType: 'PDF',
    );

    final router = GoRouter(
      initialLocation: '/saved/7',
      routes: [
        GoRoute(path: '/library', builder: (_, __) => const Text('library-home')),
        GoRoute(
          path: '/saved/:id',
          builder: (_, __) => const DocumentSavedScreen(documentId: 7),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentProvider(7).overrideWith((ref) async => doc),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ScanellaWordmark), findsOneWidget);
    expect(find.text('Document saved'), findsOneWidget);
    expect(find.text('Scan_2024-05-18.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('1 page'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('library-home'), findsOneWidget);
  });
}
