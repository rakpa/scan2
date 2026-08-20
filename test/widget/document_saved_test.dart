import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/library_launch.dart';
import 'package:scan2/features/scan/presentation/document_saved_screen.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved screen matches Screen 11 chrome and actions', (
    tester,
  ) async {
    final doc = Document(
      id: 7,
      title: 'Invoice_2024-05-18',
      createdAt: DateTime(2024, 5, 18, 9, 30),
      pages: const [ScanPage(path: '/tmp/missing-page.jpg')],
      pdfPath: '/tmp/invoice_2024-05-18.pdf',
      fileSizeBytes: 245 * 1024,
      documentType: 'PDF',
      folderId: 1,
    );

    final router = GoRouter(
      initialLocation: '/saved/7',
      routes: [
        GoRoute(
          path: '/library',
          builder: (_, state) {
            final extra = state.extra;
            if (extra is LibraryLaunch && extra.tab == 1) {
              return Text('documents-home-${extra.highlightDocumentId}');
            }
            return const Text('library-home');
          },
        ),
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
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Document Saved!'), findsOneWidget);
    expect(
      find.text('Your document has been saved successfully.'),
      findsOneWidget,
    );
    expect(find.text('Invoice_2024-05-18'), findsOneWidget);
    expect(find.textContaining('May 18, 2024'), findsOneWidget);
    expect(find.textContaining('1 Page'), findsOneWidget);
    expect(find.textContaining('245 KB'), findsOneWidget);

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save to Files'), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);

    expect(find.text('Saved in:'), findsOneWidget);
    expect(find.text('My Documents > Invoices'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('View in Documents'), findsOneWidget);
  });

  testWidgets('Done returns to home', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('library-home'), findsOneWidget);
  });

  testWidgets('View in Documents highlights the new file', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('View in Documents'));
    await tester.pumpAndSettle();
    expect(find.text('documents-home-7'), findsOneWidget);
  });

  testWidgets('pencil opens rename and more lists extra actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Rename'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Change lists local folders', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Move to folder'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });
}

Widget _app() {
  final doc = Document(
    id: 7,
    title: 'Invoice_2024-05-18',
    createdAt: DateTime(2024, 5, 18, 9, 30),
    pages: const [ScanPage(path: '/tmp/missing-page.jpg')],
    pdfPath: '/tmp/invoice_2024-05-18.pdf',
    fileSizeBytes: 245 * 1024,
    documentType: 'PDF',
    folderId: 1,
  );

  final router = GoRouter(
    initialLocation: '/saved/7',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is LibraryLaunch && extra.tab == 1) {
            return Text('documents-home-${extra.highlightDocumentId}');
          }
          return const Text('library-home');
        },
      ),
      GoRoute(
        path: '/saved/:id',
        builder: (_, __) => const DocumentSavedScreen(documentId: 7),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      documentProvider(7).overrideWith((ref) async => doc),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}
