import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/camera/presentation/widgets/quad_overlay.dart';

void main() {
  test('searching guide stays white before a lock', () {
    expect(liveScanOverlayColor(ScanState.idle), Colors.white70);
  });

  test('tracked pages turn yellow, then green when capture is armed', () {
    const tracked = ScanState(
      quad: Quad.centered(),
      phase: ScanPhase.positioning,
      confidence: 0.55,
      holdProgress: 0,
      hasDocument: true,
    );
    const armed = ScanState(
      quad: Quad.centered(),
      phase: ScanPhase.holdSteady,
      confidence: 0.90,
      holdProgress: 0.4,
      hasDocument: true,
    );

    expect(liveScanOverlayColor(tracked), const Color(0xFFFFC107));
    expect(liveScanOverlayColor(armed), const Color(0xFF4CAF50));
  });

  testWidgets('idle overlay still paints a live guide', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 240,
          height: 360,
          child: QuadOverlay(
            quad: Quad.centered(),
            color: Colors.white70,
            locked: false,
            progress: 0,
          ),
        ),
      ),
    );

    expect(find.byType(QuadOverlay), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
