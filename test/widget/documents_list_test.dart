import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/presentation/documents_view.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('documents list matches Screen 12 chrome', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(ScanellaWordmark), findsOneWidget);
    expect(find.text('My Documents'), findsOneWidget);
    expect(find.text('1 Document'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Invoices'), findsWidgets);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('ID Cards'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.textContaining('Sort by:'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Invoice_2024-05-18'), findsOneWidget);
    expect(find.textContaining('May 18, 2024'), findsOneWidget);
    expect(find.textContaining('1 Page'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('search filters local metadata', (tester) async {
    await tester.pumpWidget(_app(extra: _receipt()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pumpAndSettle();

    expect(find.text('Receipt_Coffee_Shop'), findsOneWidget);
    expect(find.text('Invoice_2024-05-18'), findsNothing);
  });

  testWidgets('category chip filters the list', (tester) async {
    await tester.pumpWidget(_app(extra: _receipt()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('category-Receipts')));
    await tester.pumpAndSettle();
    expect(find.text('Receipt_Coffee_Shop'), findsOneWidget);
    expect(find.text('Invoice_2024-05-18'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('category-All')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice_2024-05-18'), findsOneWidget);
  });

  testWidgets('tapping a document opens details', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invoice_2024-05-18'));
    await tester.pumpAndSettle();
    expect(find.text('document-7'), findsOneWidget);
  });

  testWidgets('add sheet offers scan and import', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(find.text('Import from Files'), findsOneWidget);
  });

  testWidgets('more menu lists library actions', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save to Files'), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('sort menu lists every Screen 12 option', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Sort by:'));
    await tester.pumpAndSettle();
    expect(find.text('Date (Newest)'), findsWidgets);
    expect(find.text('Date (Oldest)'), findsOneWidget);
    expect(find.text('Name A-Z'), findsOneWidget);
    expect(find.text('Name Z-A'), findsOneWidget);
    expect(find.text('File size'), findsOneWidget);
  });

  testWidgets('filter sheet covers type, category, date and favorite', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('File type'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Favorites only'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('grid toggle switches layout', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show as grid'), findsOneWidget);
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show as list'), findsOneWidget);
    expect(find.text('Invoice_2024-05-18'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this document?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice_2024-05-18'), findsOneWidget);
  });
}

Document _invoice() => Document(
  id: 7,
  title: 'Invoice_2024-05-18',
  createdAt: DateTime(2024, 5, 18, 9, 30),
  pages: const [ScanPage(path: '/tmp/missing-page.jpg')],
  pdfPath: '/tmp/invoice.pdf',
  fileSizeBytes: 245 * 1024,
  documentType: 'PDF',
  folderId: 1,
);

Document _receipt() => Document(
  id: 8,
  title: 'Receipt_Coffee_Shop',
  createdAt: DateTime(2024, 5, 17),
  pages: const [ScanPage(path: '/tmp/missing-receipt.jpg')],
  pdfPath: '/tmp/receipt.pdf',
  fileSizeBytes: 128 * 1024,
  documentType: 'PDF',
  folderId: 2,
);

Widget _app({Document? extra}) {
  final docs = extra == null ? [_invoice()] : [_invoice(), extra];
  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, __) => const DocumentsView(),
        routes: [
          GoRoute(
            path: 'document/:id',
            builder: (_, state) => Text('document-${state.pathParameters['id']}'),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      documentsProvider.overrideWith((ref) async => docs),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}
