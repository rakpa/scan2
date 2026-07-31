import 'dart:async';
import 'dart:math' as math;

import 'package:scan2/features/camera/domain/quad_detector.dart';

enum DetectionPhase {
  looking('Looking for document...'),
  aligning('Align the document edges'),
  holdSteady('Hold steady — locking edges...'),
  capturing('Capturing...'),
  pageCaptured('Page captured');

  const DetectionPhase(this.message);
  final String message;
}

/// Tracks document stability from live frame analysis and triggers auto-capture.
///
/// Deliberately slow and strict: weak / jittery detections never reach capture.
/// Auto-capture needs high confidence, consecutive good frames, geometric
/// stillness, and a minimum dwell time (not a 1-second rush).
class DocumentEdgeTracker {
  DocumentEdgeTracker({required this.onStable});

  /// Ignore the first moments after the camera opens — focus / exposure settle.
  static const _warmup = Duration(seconds: 2);

  /// Soft detection (show guide movement) vs hard lock (may auto-capture).
  static const _softConfidence = 0.62;
  static const _lockConfidence = 0.88;

  /// At 50ms ticks, 0.012 / tick ≈ 4.2s of continuous lock before capture.
  static const _stabilityStep = 0.012;
  static const _stabilityDecay = 0.10;
  static const _stabilityNeeded = 1.0;

  /// Need this many consecutive strong frames before stability can climb.
  static const _minConsecutiveHits = 18;

  /// If corners jump more than this between ticks, treat as unstable.
  static const _maxJitter = 0.018;

  /// Analyzer / detector scores below this are treated as "no document".
  static const minAcceptedConfidence = 0.58;

  static const _cooldown = Duration(milliseconds: 2000);
  static const _duplicateFrameThreshold = 0.022;

  final void Function() onStable;

  Quad _quad = const Quad.centered();
  final Quad _guide = const Quad.centered();
  Quad? _previousQuad;
  DetectionPhase _phase = DetectionPhase.looking;
  double _confidence = 0;
  double _stability = 0;
  Timer? _timer;
  bool _autoCaptureEnabled = true;
  bool _capturing = false;
  var _hasFrameFeed = false;
  var _missedFrames = 0;
  var _consecutiveHits = 0;
  DateTime? _startedAt;

  bool _autoCaptureLocked = false;
  DateTime? _lockCooldownUntil;
  Quad? _lastAutoCaptureQuad;
  DateTime? _lastAutoCaptureAt;

  Quad get quad => _quad;
  DetectionPhase get phase => _phase;
  double get confidence => _confidence;
  double get stability => _stability;

  void start() {
    _timer?.cancel();
    _startedAt = DateTime.now();
    _stability = 0;
    _consecutiveHits = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setAutoCapture(bool enabled) {
    _autoCaptureEnabled = enabled;
    if (!enabled) {
      _stability = 0;
      _consecutiveHits = 0;
    }
  }

  void updateFromFrame({
    required Quad? detected,
    required double frameConfidence,
  }) {
    _hasFrameFeed = true;

    // Drop weak / noisy detections so the overlay does not thrash.
    final accepted = detected != null &&
        frameConfidence >= minAcceptedConfidence;

    if (accepted) {
      _missedFrames = 0;
      _consecutiveHits++;
      // Slow blend — overlay should ease onto real edges, not snap.
      _quad = _quad.lerp(detected!, 0.22);
      _confidence = _confidence * 0.55 + frameConfidence * 0.45;
    } else {
      _missedFrames++;
      _consecutiveHits = 0;
      _confidence *= 0.82;
      if (_missedFrames >= 3) {
        _quad = _quad.lerp(_guide, 0.12);
        if (_missedFrames >= 10) {
          _confidence = 0;
          _stability = 0;
        }
      }
    }
  }

  void lockAfterCapture(Quad capturedAt) {
    _capturing = false;
    _stability = 0;
    _consecutiveHits = 0;
    _autoCaptureLocked = true;
    _lockCooldownUntil = DateTime.now().add(_cooldown);
    _lastAutoCaptureQuad = capturedAt;
    _lastAutoCaptureAt = DateTime.now();
    _phase = DetectionPhase.pageCaptured;
  }

  void prepareNextPage() {
    if (!_autoCaptureLocked) return;
    final until = _lockCooldownUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    _autoCaptureLocked = false;
    _lockCooldownUntil = null;
    _stability = 0;
    _consecutiveHits = 0;
    _phase = DetectionPhase.looking;
    _confidence = 0.15;
  }

  void releaseCaptureLock() {
    _capturing = false;
  }

  bool get _warmupDone {
    final start = _startedAt;
    if (start == null) return false;
    return DateTime.now().difference(start) >= _warmup;
  }

  bool get _geometryStable {
    final prev = _previousQuad;
    if (prev == null) return false;
    return _quad.averageCornerDistance(prev) <= _maxJitter;
  }

  void _tick() {
    if (_capturing) return;

    if (!_hasFrameFeed) {
      _phase = DetectionPhase.looking;
      return;
    }

    if (_autoCaptureLocked) {
      final until = _lockCooldownUntil;
      if (until == null || !DateTime.now().isBefore(until)) {
        final last = _lastAutoCaptureQuad;
        final moved =
            last == null || _quad.averageCornerDistance(last) >= 0.05;
        if (moved || _confidence < 0.45) {
          prepareNextPage();
        }
      }
      _phase = DetectionPhase.pageCaptured;
      _previousQuad = _quad;
      return;
    }

    final geometricallySteady = _geometryStable;
    _previousQuad = _quad;

    if (_confidence < _softConfidence || _consecutiveHits < 4) {
      _phase = DetectionPhase.looking;
      _stability = 0;
      return;
    }

    if (_confidence < _lockConfidence ||
        _consecutiveHits < _minConsecutiveHits ||
        !geometricallySteady) {
      _phase = DetectionPhase.aligning;
      _stability = math.max(0, _stability - _stabilityDecay);
      return;
    }

    // Strong lock: edges are consistent and still.
    _phase = DetectionPhase.holdSteady;
    if (!_warmupDone) {
      // Keep showing "hold steady" but do not capture during warmup.
      return;
    }

    _stability += _stabilityStep;
    if (_autoCaptureEnabled &&
        _stability >= _stabilityNeeded &&
        !_isDuplicateFrame(_quad)) {
      _capturing = true;
      _phase = DetectionPhase.capturing;
      onStable();
    }
  }

  bool _isDuplicateFrame(Quad current) {
    final reference = _lastAutoCaptureQuad;
    final capturedAt = _lastAutoCaptureAt;
    if (reference == null || capturedAt == null) return false;
    if (DateTime.now().difference(capturedAt) > const Duration(seconds: 8)) {
      return false;
    }
    return current.averageCornerDistance(reference) < _duplicateFrameThreshold;
  }

  void dispose() => stop();
}
