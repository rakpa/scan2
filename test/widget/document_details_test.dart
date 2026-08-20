import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/library_launch.dart';
import 'package:scan2/features/library/presentation/document_detail_screen.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('document details matches Screen 13 chrome', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Document Details'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Invoice_2024-05-18.pdf'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.textContaining('May 18, 2024'), findsWidgets);
    expect(find.textContaining('1 Page'), findsOneWidget);
    expect(find.textContaining('245 KB'), findsWidgets);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.text('Document Information'), findsOneWidget);
    expect(find.text('File Type'), findsOneWidget);
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('Dimensions'), findsOneWidget);
    expect(find.text('File Size'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Modified'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save to Files'), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Open with'), findsOneWidget);
  });

  testWidgets('more menu lists library actions', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and returns to documents', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this document?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Document Details'), findsOneWidget);
  });

  testWidgets('back returns to the documents list', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('library-home'), findsOneWidget);
  });

  testWidgets('pencil opens rename', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Rename'), findsOneWidget);
  });

  testWidgets('fullscreen opens the saved page viewer', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Document Details'), findsOneWidget);
  });
}

Document _invoice() => Document(
  id: 7,
  title: 'Invoice_2024-05-18',
  createdAt: DateTime(2024, 5, 18, 10, 30),
  pages: const [ScanPage(path: '/tmp/missing-page.jpg')],
  pdfPath: '/tmp/invoice.pdf',
  fileSizeBytes: 245 * 1024,
  documentType: 'PDF',
  folderId: 1,
);

Widget _app() {
  final router = GoRouter(
    initialLocation: '/library/document/7',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is LibraryLaunch && extra.tab == 1) {
            return const Text('documents-home');
          }
          return const Text('library-home');
        },
        routes: [
          GoRoute(
            path: 'document/:id',
            builder: (_, __) => const DocumentDetailScreen(documentId: 7),
          ),
        ],
      ),
      GoRoute(
        path: '/scan-result',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is ScanResultArgs) {
            return ScanResultScreen(args: extra);
          }
          return const Text('scan-result-missing');
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      documentProvider(7).overrideWith((ref) async => _invoice()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}
