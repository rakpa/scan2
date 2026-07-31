import 'dart:async';
import 'dart:math' as math;

import 'package:scan2/features/camera/domain/quad_detector.dart';

enum DetectionPhase {
  looking('Looking for document...'),
  aligning('Align the document edges'),
  holdSteady('Hold steady'),
  capturing('Capturing...'),
  pageCaptured('Page captured');

  const DetectionPhase(this.message);
  final String message;
}

/// Tracks document stability from live frame analysis (Scanella-parity).
///
/// Live guides follow detections quickly. Auto-capture (when enabled) needs
/// sustained high confidence — not a single lucky frame.
class DocumentEdgeTracker {
  DocumentEdgeTracker({required this.onStable});

  static const _cooldown = Duration(milliseconds: 1500);
  static const _duplicateFrameThreshold = 0.022;

  /// Soft floor used by the analyzer to drop pure noise.
  static const minAcceptedConfidence = 0.42;

  final void Function() onStable;

  Quad _quad = const Quad.centered();
  final Quad _guide = const Quad.centered();
  DetectionPhase _phase = DetectionPhase.looking;
  double _confidence = 0;
  double _stability = 0;
  Timer? _timer;
  bool _autoCaptureEnabled = false;
  bool _capturing = false;
  var _hasFrameFeed = false;
  var _missedFrames = 0;

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
    _stability = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setAutoCapture(bool enabled) {
    _autoCaptureEnabled = enabled;
    if (!enabled) _stability = 0;
  }

  void updateFromFrame({
    required Quad? detected,
    required double frameConfidence,
  }) {
    _hasFrameFeed = true;

    if (detected != null && frameConfidence >= minAcceptedConfidence) {
      _missedFrames = 0;
      // Fast blend so the guide tracks the real page (Scanella uses ~0.45).
      _quad = _quad.lerp(detected, 0.45);
      _confidence = _confidence * 0.4 + frameConfidence * 0.6;
    } else {
      _missedFrames++;
      _confidence *= 0.72;
      if (_missedFrames >= 4) {
        _quad = _quad.lerp(_guide, 0.18);
        if (_missedFrames >= 12) {
          _confidence = 0;
          _stability = 0;
        }
      }
    }
  }

  void lockAfterCapture(Quad capturedAt) {
    _capturing = false;
    _stability = 0;
    _autoCaptureLocked = true;
    _lockCooldownUntil = DateTime.now().add(_cooldown);
    _lastAutoCaptureQuad = capturedAt;
    _lastAutoCaptureAt = DateTime.now();
    _phase = DetectionPhase.pageCaptured;
  }

  void prepareNextPage() {
    final until = _lockCooldownUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    _autoCaptureLocked = false;
    _lockCooldownUntil = null;
    _stability = 0;
    _phase = DetectionPhase.looking;
    _confidence = 0.2;
  }

  void releaseCaptureLock() {
    _capturing = false;
  }

  void _tick() {
    if (_capturing) return;

    if (_autoCaptureLocked) {
      _phase = DetectionPhase.pageCaptured;
      final until = _lockCooldownUntil;
      if (until != null && !DateTime.now().isBefore(until)) {
        // Unlock after cooldown so the next page can be detected.
        if (_confidence < 0.42 || _missedFrames >= 8) {
          prepareNextPage();
        }
      }
      return;
    }

    if (!_hasFrameFeed) {
      _phase = DetectionPhase.looking;
      return;
    }

    if (_confidence < 0.5) {
      _phase = DetectionPhase.looking;
      _stability = 0;
    } else if (_confidence < 0.78) {
      _phase = DetectionPhase.holdSteady;
      _stability = math.max(0, _stability - 0.08);
    } else {
      _phase = DetectionPhase.holdSteady;
      _stability += 0.06;
      if (_autoCaptureEnabled &&
          _stability >= 1.0 &&
          !_isDuplicateFrame(_quad)) {
        _capturing = true;
        _phase = DetectionPhase.capturing;
        onStable();
      }
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
