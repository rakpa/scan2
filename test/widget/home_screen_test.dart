import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/home/presentation/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home dashboard shows the Scanella shortcuts', (tester) async {
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

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Scan Photos'), findsOneWidget);
    expect(find.text('OCR Text'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Recent Documents'), findsOneWidget);
  });
}
