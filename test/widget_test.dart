import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/main.dart';

void main() {
  testWidgets('app boots to a Material app', (tester) async {
    await tester.pumpWidget(const Scan2Root());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
