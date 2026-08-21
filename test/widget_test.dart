import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots to a Material app', (tester) async {
    await tester.pumpWidget(const Scan2Root());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
