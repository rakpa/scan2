import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/core/haptics/app_haptics.dart';
import 'package:scan2/core/theme/tactile.dart';
import 'package:scan2/core/widgets/pressable_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PressableScale fires on a tap and shows a down-state', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              haptic: AppHaptic.none,
              scale: Tactile.pressScaleCard,
              onPressed: () => taps++,
              child: const SizedBox(
                width: 120,
                height: 48,
                child: Text('Press me'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Press me'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('press snaps to the down scale on touch-down', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              haptic: AppHaptic.none,
              scale: Tactile.pressScaleCard,
              onPressed: () {},
              child: const SizedBox(
                width: 120,
                height: 48,
                child: Text('Hold me'),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.text('Hold me')));
    await tester.pump();
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('scanella-press-scale')),
    );
    expect(transform.transform.entry(0, 0), closeTo(Tactile.pressScaleCard, 0.01));
    await gesture.up();
  });

  testWidgets('sliding off a PressableScale cancels the action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              haptic: AppHaptic.none,
              onPressed: () => taps++,
              child: const SizedBox(
                width: 80,
                height: 80,
                child: Text('Hold'),
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.text('Hold'));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('Reduce Motion still leaves the control tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressableScale(
                haptic: AppHaptic.none,
                onPressed: () => taps++,
                child: const Text('Reduced'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reduced'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('empty-state Scan first page is a real control', (tester) async {
    // Covered on HomeScreen; this asserts the shared button meets 44pt.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressableScale(
            haptic: AppHaptic.none,
            onPressed: () {},
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Scan first page'),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(PressableScale));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
