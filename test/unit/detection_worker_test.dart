import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/camera/domain/detection_worker.dart';

import '../support/scene_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DetectionWorker', () {
    late DetectionWorker worker;

    setUp(() async {
      worker = await DetectionWorker.spawn();
    });

    tearDown(() => worker.dispose());

    test('detects a page on the background isolate', () async {
      final scene = buildScene(
        corners: const [
          Offset(40, 28),
          Offset(200, 26),
          Offset(202, 152),
          Offset(38, 155),
        ],
      );

      final result = await worker.analyze(
        scene.luma,
        scene.width,
        scene.height,
      );
      expect(result, isNotNull);
      expect(result!.corners, hasLength(4));
      expect(result.confidence, greaterThan(0.5));
    });

    test('drops frames while one is already in flight', () async {
      final scene = buildScene(
        corners: const [
          Offset(40, 28),
          Offset(200, 26),
          Offset(202, 152),
          Offset(38, 155),
        ],
      );

      // Detection is slower than frame delivery, so the second call must be
      // refused rather than queued — a queued frame shows edges from the past.
      final first = worker.analyze(scene.luma, scene.width, scene.height);
      expect(worker.isBusy, isTrue);
      final second = await worker.analyze(
        scene.luma,
        scene.width,
        scene.height,
      );
      expect(second, isNull, reason: 'in-flight frame should not queue');

      await first;
      expect(worker.isBusy, isFalse);
    });

    test('reports nothing for a blank frame', () async {
      final scene = buildScene(
        corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        text: false,
        noise: 1,
        lightingFalloff: 0,
      );
      final result = await worker.analyze(
        scene.luma,
        scene.width,
        scene.height,
      );
      expect(result, isNull);
    });

    test('analyze after dispose returns null instead of throwing', () async {
      final scene = buildScene(
        corners: const [
          Offset(40, 28),
          Offset(200, 26),
          Offset(202, 152),
          Offset(38, 155),
        ],
      );
      worker.dispose();
      expect(
        await worker.analyze(scene.luma, scene.width, scene.height),
        isNull,
      );
    });
  });
}
