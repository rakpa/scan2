import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// What the camera screen is currently telling the user.
enum ScanPhase {
  searching('Point the camera at a document'),
  positioning('Fit the whole page in view'),
  tooFar('Move closer to the document'),
  holdSteady('Hold steady…'),
  capturing('Capturing'),
  captured('Page captured');

  const ScanPhase(this.message);

  final String message;
}

/// Immutable snapshot the camera UI renders from.
@immutable
class ScanState {
  const ScanState({
    required this.quad,
    required this.phase,
    required this.confidence,
    required this.holdProgress,
    required this.hasDocument,
  });

  static const idle = ScanState(
    quad: Quad.centered(),
    phase: ScanPhase.searching,
    confidence: 0,
    holdProgress: 0,
    hasDocument: false,
  );

  final Quad quad;
  final ScanPhase phase;
  final double confidence;

  /// 0–1 progress toward an automatic capture, for the shutter ring.
  final double holdProgress;

  /// Whether the quad currently traces a real detection rather than the
  /// resting guide frame.
  final bool hasDocument;

  ScanState copyWith({
    Quad? quad,
    ScanPhase? phase,
    double? confidence,
    double? holdProgress,
    bool? hasDocument,
  }) {
    return ScanState(
      quad: quad ?? this.quad,
      phase: phase ?? this.phase,
      confidence: confidence ?? this.confidence,
      holdProgress: holdProgress ?? this.holdProgress,
      hasDocument: hasDocument ?? this.hasDocument,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanState &&
      other.quad == quad &&
      other.phase == phase &&
      other.confidence == confidence &&
      other.holdProgress == holdProgress &&
      other.hasDocument == hasDocument;

  @override
  int get hashCode =>
      Object.hash(quad, phase, confidence, holdProgress, hasDocument);
}

/// Turns a stream of per-frame detections into a stable on-screen quad and,
/// when enabled, an automatic shutter release.
///
/// Auto-capture keys off *motion*, not confidence alone. Confidence says the
/// detector found a page; it says nothing about whether the phone is still.
/// Firing on confidence produces the two failure modes people notice: a
/// shutter that never fires because a single threshold is never sustained,
/// and one that fires mid-sweep and saves a blurred page. Here the page must
/// be recognised *and* essentially motionless for [holdDuration], and the
/// progress toward that is published so the UI can show it coming.
class DocumentEdgeTracker {
  DocumentEdgeTracker({
    required this.onAutoCapture,
    this.holdDuration = const Duration(milliseconds: 900),
  });

  /// Confidence below which the detection is ignored entirely.
  ///
  /// Set below the weakest genuine detections (a pale page on a pale desk
  /// scores ~0.52) rather than above the strongest false positives (heavy
  /// surface texture can reach ~0.66). The two ranges overlap, so this cannot
  /// separate them — showing a guide that turns out to be wrong costs the user
  /// nothing, whereas hiding one on a real document looks broken.
  /// [autoCaptureConfidence] is what actually has to be safe.
  static const minTrackConfidence = 0.50;

  /// Smallest share of the frame a document may cover and still be captured
  /// automatically.
  ///
  /// A card filling 5% of the frame is detected accurately, but capturing it
  /// there wastes 95% of the sensor and yields an unreadable scan. Below this
  /// the guides still track; the user is asked to move closer, and can always
  /// override with the shutter.
  static const minAutoCaptureArea = 0.12;

  /// Confidence required before the hold timer can start.
  static const autoCaptureConfidence = 0.78;

  /// Mean corner movement (as a fraction of the frame) still considered
  /// "steady". Roughly the jitter of a hand held still.
  static const steadyMotionThreshold = 0.014;

  /// How long the page must stay unrecognised before the guide relaxes back
  /// to its resting frame, in frames.
  static const _framesBeforeRelease = 5;

  /// Quiet period after a capture so one page is not scanned twice.
  static const _cooldown = Duration(milliseconds: 1200);

  /// A new page must differ from the last captured one by at least this much.
  static const _duplicateThreshold = 0.03;

  final VoidCallback onAutoCapture;
  final Duration holdDuration;

  final ValueNotifier<ScanState> state = ValueNotifier(ScanState.idle);

  Quad _quad = const Quad.centered();
  double _confidence = 0;
  Quad? _lastDetection;
  int _missedFrames = 0;

  Duration _steadyFor = Duration.zero;
  DateTime? _lastTick;
  Timer? _ticker;

  bool _autoCaptureEnabled = true;
  bool _capturing = false;
  DateTime? _cooldownUntil;
  Quad? _lastCapturedQuad;

  ScanState get value => state.value;

  void start() {
    _ticker?.cancel();
    _lastTick = DateTime.now();
    // Drives the hold countdown independently of camera frame delivery, so
    // the ring animates smoothly even when frames arrive unevenly.
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  void setAutoCapture(bool enabled) {
    if (_autoCaptureEnabled == enabled) return;
    _autoCaptureEnabled = enabled;
    _steadyFor = Duration.zero;
    _publish();
  }

  /// Feeds one analysed frame. [detected] is null when nothing was found.
  void updateFromFrame({required Quad? detected, required double confidence}) {
    if (detected != null && confidence >= minTrackConfidence) {
      _missedFrames = 0;

      final previous = _lastDetection;
      final motion = previous == null
          ? 1.0
          : detected.averageCornerDistance(previous);
      _lastDetection = detected;

      // Snap toward a detection that jumped; smooth one that barely moved.
      // A single blend rate either lags a moving page or shivers on a still
      // one.
      final blend = (motion * 12).clamp(0.30, 0.85);
      _quad = _quad.lerp(detected, blend);
      _confidence = _confidence * 0.35 + confidence * 0.65;

      if (motion > steadyMotionThreshold) {
        _steadyFor = Duration.zero;
      }
    } else {
      _missedFrames++;
      _confidence *= 0.7;
      _steadyFor = Duration.zero;
      if (_missedFrames >= _framesBeforeRelease) {
        _lastDetection = null;
        _quad = _quad.lerp(const Quad.centered(), 0.15);
      }
    }
    _publish();
  }

  /// Called by the camera once a capture is under way.
  void lockAfterCapture(Quad capturedAt) {
    _capturing = false;
    _steadyFor = Duration.zero;
    _cooldownUntil = DateTime.now().add(_cooldown);
    _lastCapturedQuad = capturedAt;
    _publish(phase: ScanPhase.captured);
  }

  /// Called when a capture attempt failed, so the shutter can arm again.
  void releaseCaptureLock() {
    _capturing = false;
    _steadyFor = Duration.zero;
    _publish();
  }

  void _tick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick ?? now);
    _lastTick = now;

    if (_capturing) return;

    final steady =
        _confidence >= autoCaptureConfidence &&
        _lastDetection != null &&
        _missedFrames == 0 &&
        !_isTooFar;

    if (steady) {
      _steadyFor += elapsed;
      if (_autoCaptureEnabled &&
          _steadyFor >= holdDuration &&
          !_inCooldown(now) &&
          !_isDuplicate()) {
        _capturing = true;
        _steadyFor = Duration.zero;
        _publish(phase: ScanPhase.capturing);
        onAutoCapture();
        return;
      }
    } else {
      _steadyFor = Duration.zero;
    }

    _publish();
  }

  /// True when a real document is tracked but is too small to capture well.
  bool get _isTooFar {
    final detection = _lastDetection;
    return detection != null && detection.areaRatio < minAutoCaptureArea;
  }

  bool _inCooldown(DateTime now) {
    final until = _cooldownUntil;
    return until != null && now.isBefore(until);
  }

  /// Guards against re-scanning the page still sitting under the camera.
  bool _isDuplicate() {
    final last = _lastCapturedQuad;
    final current = _lastDetection;
    if (last == null || current == null) return false;
    if (!_inCooldownWindow()) return false;
    return current.averageCornerDistance(last) < _duplicateThreshold;
  }

  bool _inCooldownWindow() {
    final until = _cooldownUntil;
    if (until == null) return false;
    // Duplicate suppression stays active a little past the cooldown so a
    // motionless phone does not immediately re-fire on the same sheet.
    return DateTime.now().isBefore(until.add(const Duration(seconds: 3)));
  }

  void _publish({ScanPhase? phase}) {
    final resolved = phase ?? _resolvePhase();
    final progress = holdDuration.inMicroseconds == 0
        ? 0.0
        : (_steadyFor.inMicroseconds / holdDuration.inMicroseconds).clamp(
            0.0,
            1.0,
          );

    state.value = ScanState(
      quad: _quad,
      phase: resolved,
      confidence: _confidence.clamp(0.0, 1.0),
      holdProgress: _autoCaptureEnabled ? progress : 0,
      hasDocument: _lastDetection != null,
    );
  }

  ScanPhase _resolvePhase() {
    if (_capturing) return ScanPhase.capturing;
    if (_inCooldown(DateTime.now())) return ScanPhase.captured;
    if (_lastDetection == null || _confidence < minTrackConfidence) {
      return ScanPhase.searching;
    }
    if (_isTooFar) return ScanPhase.tooFar;
    if (_confidence < autoCaptureConfidence) return ScanPhase.positioning;
    return ScanPhase.holdSteady;
  }

  @visibleForTesting
  double get confidence => _confidence;

  @visibleForTesting
  Duration get steadyFor => _steadyFor;

  void dispose() {
    stop();
    state.dispose();
  }
}

/// Mean corner motion between two quads, exposed for the camera to decide
/// whether a still capture is worth re-detecting.
double quadMotion(Quad a, Quad b) => a.averageCornerDistance(b);

/// Clamps a normalized quad into the frame, used before handing corners to
/// the crop screen.
Quad clampQuad(Quad quad) {
  double c(double v) => math.min(1, math.max(0, v));
  return Quad(
    topLeft: Offset(c(quad.topLeft.dx), c(quad.topLeft.dy)),
    topRight: Offset(c(quad.topRight.dx), c(quad.topRight.dy)),
    bottomRight: Offset(c(quad.bottomRight.dx), c(quad.bottomRight.dy)),
    bottomLeft: Offset(c(quad.bottomLeft.dx), c(quad.bottomLeft.dy)),
  );
}
