import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

void main() {
  test('auto-capture does not fire immediately on a single strong frame', () {
    var captures = 0;
    final tracker = DocumentEdgeTracker(onStable: () => captures++);
    tracker.start();

    const strong = Quad(
      topLeft: Offset(0.15, 0.20),
      topRight: Offset(0.85, 0.20),
      bottomRight: Offset(0.85, 0.80),
      bottomLeft: Offset(0.15, 0.80),
    );

    // One strong reading must not trigger capture.
    tracker.updateFromFrame(detected: strong, frameConfidence: 0.95);
    expect(captures, 0);
    expect(tracker.phase, isNot(DetectionPhase.capturing));

    tracker.dispose();
  });

  test('weak detections are ignored for confidence lock', () {
    final tracker = DocumentEdgeTracker(onStable: () {});
    tracker.start();

    const noisy = Quad.centered();
    tracker.updateFromFrame(detected: noisy, frameConfidence: 0.40);
    expect(tracker.confidence, lessThan(0.2));
    expect(tracker.phase, DetectionPhase.looking);

    tracker.dispose();
  });
}
