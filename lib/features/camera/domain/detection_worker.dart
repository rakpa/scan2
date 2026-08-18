import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:scan2/features/camera/domain/document_quad_detector.dart';

/// A detection result in buffer coordinates, before preview rotation.
class WorkerDetection {
  const WorkerDetection({required this.corners, required this.confidence});

  final List<Offset> corners;
  final double confidence;
}

/// Runs document detection on a long-lived background isolate.
///
/// Detection costs roughly 8ms per frame. On the UI isolate that is a dropped
/// frame every time it runs, which is exactly the stutter that makes a
/// scanner feel cheap — and it competes with the camera preview for the same
/// thread. A persistent isolate is used rather than `compute` so that frames
/// do not each pay isolate spawn cost.
class DetectionWorker {
  DetectionWorker._(
    this._isolate,
    this._requests,
    this._responses,
    Stream<dynamic> incoming,
  ) {
    _subscription = incoming.listen(_onResponse);
  }

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  late final StreamSubscription<dynamic> _subscription;

  Completer<WorkerDetection?>? _pending;
  var _disposed = false;

  static Future<DetectionWorker> spawn() async {
    final responses = ReceivePort();
    final incoming = responses.asBroadcastStream();
    final isolate = await Isolate.spawn(
      _detectionIsolateMain,
      responses.sendPort,
      debugName: 'scan2-detection',
    );

    // The isolate's first message is the port to send frames to. Bounded, so
    // a failed spawn surfaces as an error instead of hanging camera startup.
    try {
      final requests =
          await incoming
                  .firstWhere((m) => m is SendPort)
                  .timeout(const Duration(seconds: 5))
              as SendPort;
      return DetectionWorker._(isolate, requests, responses, incoming);
    } catch (e) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      rethrow;
    }
  }

  /// True when a frame is already being analysed. Callers should skip the
  /// current frame rather than queue it — a stale detection is worse than a
  /// slightly lower analysis rate.
  bool get isBusy => _pending != null;

  /// Analyses one luminance grid. Returns null if a request is already in
  /// flight or the worker has been disposed.
  Future<WorkerDetection?> analyze(Uint8List luma, int width, int height) {
    if (_disposed || _pending != null) return Future.value(null);
    final completer = Completer<WorkerDetection?>();
    _pending = completer;
    _requests.send(_DetectionRequest(luma, width, height));
    return completer.future;
  }

  void _onResponse(dynamic message) {
    if (message is! _DetectionResponse) return;
    final completer = _pending;
    _pending = null;
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      message.corners == null
          ? null
          : WorkerDetection(
              corners: message.corners!,
              confidence: message.confidence,
            ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    _subscription.cancel();
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _DetectionRequest {
  const _DetectionRequest(this.luma, this.width, this.height);

  final Uint8List luma;
  final int width;
  final int height;
}

class _DetectionResponse {
  const _DetectionResponse(this.corners, this.confidence);

  final List<Offset>? corners;
  final double confidence;
}

void _detectionIsolateMain(SendPort responses) {
  final requests = ReceivePort();
  responses.send(requests.sendPort);

  const detector = DocumentQuadDetector();
  requests.listen((message) {
    if (message is! _DetectionRequest) return;
    QuadDetection? result;
    try {
      result = detector.detect(message.luma, message.width, message.height);
    } catch (_) {
      result = null;
    }
    responses.send(
      _DetectionResponse(result?.corners, result?.confidence ?? 0),
    );
  });
}
