import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// A confidently detected page, roughly filling the frame.
const _page = Quad(
  topLeft: Offset(0.12, 0.16),
  topRight: Offset(0.88, 0.16),
  bottomRight: Offset(0.88, 0.84),
  bottomLeft: Offset(0.12, 0.84),
);

/// The same page, nudged far enough to count as camera movement.
Quad _moved(double by) => Quad(
  topLeft: _page.topLeft + Offset(by, 0),
  topRight: _page.topRight + Offset(by, 0),
  bottomRight: _page.bottomRight + Offset(by, 0),
  bottomLeft: _page.bottomLeft + Offset(by, 0),
);

void main() {
  group('DocumentEdgeTracker', () {
    late int captures;
    late DocumentEdgeTracker tracker;

    setUp(() {
      captures = 0;
      tracker = DocumentEdgeTracker(
        onAutoCapture: () => captures++,
        holdDuration: const Duration(milliseconds: 300),
      );
    });

    tearDown(() => tracker.dispose());

    test('one strong frame does not fire the shutter', () {
      tracker.start();
      tracker.updateFromFrame(detected: _page, confidence: 0.95);
      expect(captures, 0);
      expect(tracker.value.phase, isNot(ScanPhase.capturing));
    });

    test('a steady page fires auto-capture after the hold', () async {
      tracker.start();
      // Feed the same detection repeatedly, as a still camera would.
      for (var i = 0; i < 3; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(tracker.value.phase, ScanPhase.holdSteady);
      expect(tracker.value.holdProgress, greaterThan(0));

      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(captures, 1, reason: 'shutter should have released by now');
    });

    test('a moving page never reaches the hold', () async {
      tracker.start();
      // Sweeping the camera: every frame lands somewhere new.
      for (var i = 0; i < 12; i++) {
        tracker.updateFromFrame(detected: _moved(i * 0.05), confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(
        captures,
        0,
        reason: 'capturing mid-sweep would save a blurred page',
      );
    });

    test('weak detections are ignored', () async {
      tracker.start();
      for (var i = 0; i < 6; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.30);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(tracker.value.phase, ScanPhase.searching);
      expect(tracker.value.hasDocument, isFalse);
      expect(captures, 0);
    });

    test('auto-capture off still tracks edges but never fires', () async {
      tracker.setAutoCapture(false);
      tracker.start();
      for (var i = 0; i < 8; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(captures, 0);
      expect(
        tracker.value.hasDocument,
        isTrue,
        reason: 'guides stay live even with auto-capture disabled',
      );
      expect(tracker.value.holdProgress, 0);
    });

    test('the same page is not captured twice in a row', () async {
      tracker.start();
      for (var i = 0; i < 3; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(captures, 1);

      // The phone is still pointing at the page just captured.
      tracker.lockAfterCapture(_page);
      for (var i = 0; i < 12; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(captures, 1, reason: 'the same sheet must not rescan itself');
    });

    test('a different page after a capture does scan', () async {
      tracker.start();
      tracker.lockAfterCapture(_page);

      // Wait out the cooldown, then present a clearly different page.
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      for (var i = 0; i < 4; i++) {
        tracker.updateFromFrame(detected: _moved(0.20), confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(captures, 1, reason: 'the next page should scan');
    });

    test(
      'a document too small to scan well is not captured automatically',
      () async {
        // A key card at arm's length: detected confidently, but only ~4% of the
        // frame. Capturing there wastes almost the whole sensor.
        const tiny = Quad(
          topLeft: Offset(0.44, 0.46),
          topRight: Offset(0.56, 0.46),
          bottomRight: Offset(0.56, 0.80),
          bottomLeft: Offset(0.44, 0.80),
        );
        expect(
          tiny.areaRatio,
          lessThan(DocumentEdgeTracker.minAutoCaptureArea),
        );

        tracker.start();
        for (var i = 0; i < 6; i++) {
          tracker.updateFromFrame(detected: tiny, confidence: 0.95);
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(captures, 0, reason: 'would produce an unreadable scan');
        expect(tracker.value.phase, ScanPhase.tooFar);
        // The guides must still track it, so the user can see it is recognised
        // and reach for the shutter if they want it anyway.
        expect(tracker.value.hasDocument, isTrue);
      },
    );

    test('moving closer lets the same document capture', () async {
      tracker.start();
      for (var i = 0; i < 4; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(
        _page.areaRatio,
        greaterThan(DocumentEdgeTracker.minAutoCaptureArea),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(captures, 1);
    });

    test('losing the page resets progress and the guide relaxes', () async {
      tracker.start();
      for (var i = 0; i < 3; i++) {
        tracker.updateFromFrame(detected: _page, confidence: 0.95);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(tracker.value.hasDocument, isTrue);

      for (var i = 0; i < 8; i++) {
        tracker.updateFromFrame(detected: null, confidence: 0);
      }
      expect(tracker.value.hasDocument, isFalse);
      expect(tracker.value.holdProgress, 0);
      expect(tracker.value.phase, ScanPhase.searching);
    });
  });
}
