import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/camera_frame_analyzer.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/camera/domain/scan_mode.dart';
import 'package:scan2/features/camera/presentation/widgets/quad_overlay.dart';
import 'package:scan2/features/camera/presentation/widgets/scanner_chrome.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  DocumentEdgeTracker? _tracker;
  final _analyzer = CameraFrameAnalyzer();
  final _picker = ImagePicker();
  final _processor = const PageProcessor();

  String? _cameraError;
  ScannerFlash _flash = ScannerFlash.off;
  ScanMode _mode = ScanMode.document;
  bool _autoDetect = true;
  bool _streaming = false;
  bool _capturing = false;
  bool _processing = false;
  bool _analyzing = false;
  bool _initializing = false;

  /// Drives the white flash played over the preview on capture.
  final ValueNotifier<double> _shutterFlash = ValueNotifier(0);
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _shutterFlash.dispose();
    _tracker?.dispose();
    _analyzer.dispose();
    unawaited(_disposeController());
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;

    // The OS revokes the camera when the app leaves the foreground. Without
    // releasing and reacquiring it, the preview comes back as a frozen black
    // rectangle — the most common way a camera screen "breaks" in the wild.
    switch (state) {
      case AppLifecycleState.resumed:
        // Note this runs when _controller is already null, so it must not be
        // guarded on having a live controller.
        unawaited(_initCamera());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_releaseCamera());
    }
  }

  Future<void> _releaseCamera() async {
    _tracker?.stop();
    await _stopStream();
    await _disposeController();
    if (mounted) setState(() {});
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Nothing useful to do if the platform side already tore it down.
    }
  }

  // -------------------------------------------------------------------------
  // Camera setup
  // -------------------------------------------------------------------------

  Future<void> _initCamera() async {
    // Backgrounding and foregrounding quickly can land two of these in flight
    // before either has assigned _controller, leaving an orphaned controller
    // holding the camera.
    if (_controller != null || _initializing) return;
    _initializing = true;
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        setState(
          () =>
              _cameraError = 'Scanella needs camera access to scan documents.',
        );
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      _camera = back;
      _cameraError = null;

      await _analyzer.ensureStarted();
      _startTracker();
      await _startStream();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        setState(() => _cameraError = 'Camera failed to start: $e');
      }
    } finally {
      _initializing = false;
    }
  }

  void _startTracker() {
    // Reused across resumes: disposing one the widget tree is still listening
    // to would leave a ValueListenableBuilder bound to a dead notifier until
    // the next rebuild.
    final tracker =
        _tracker ?? DocumentEdgeTracker(onAutoCapture: _onAutoCapture);
    _tracker = tracker;
    tracker
      ..setAutoCapture(ref.read(settingsProvider).autoCapture)
      ..setMinAutoCaptureArea(_mode.minAutoCaptureArea)
      ..start();
  }

  Future<void> _startStream() async {
    final controller = _controller;
    final camera = _camera;
    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized ||
        _streaming) {
      return;
    }

    _streaming = true;
    await controller.startImageStream((image) {
      // Frames arrive faster than detection completes; skipping is correct.
      // Queueing would show the user edges from half a second ago.
      if (_analyzing || _capturing || !_autoDetect || !mounted) return;
      _analyzing = true;

      final orientation = _deviceOrientationDegrees(controller);
      _analyzer
          .analyze(image, camera, orientation)
          .then((result) {
            if (!mounted || result == null) return;
            _tracker?.updateFromFrame(
              detected: result.quad,
              confidence: result.confidence,
            );
          })
          .catchError((Object e) {
            debugPrint('Frame analysis failed: $e');
          })
          .whenComplete(() => _analyzing = false);
    });
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) {
      _streaming = false;
      return;
    }
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Already stopped, or the controller is going away.
    }
  }

  int _deviceOrientationDegrees(CameraController controller) {
    return switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeRight => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeLeft => 270,
    };
  }

  // -------------------------------------------------------------------------
  // Capture
  // -------------------------------------------------------------------------

  Future<void> _onAutoCapture() => _capture(automatic: true);

  Future<void> _capture({bool automatic = false}) async {
    if (kIsWeb || _capturing || _processing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final tracker = _tracker;
    _capturing = true;
    final quadAtCapture = tracker?.value.quad;

    try {
      await _stopStream();
      if (_flash == ScannerFlash.auto) {
        try {
          await controller.setFlashMode(FlashMode.auto);
        } catch (_) {}
      }
      final file = await controller.takePicture();
      if (!mounted) return;
      _playShutter();

      tracker?.lockAfterCapture(quadAtCapture ?? const Quad.centered());
      setState(() => _processing = true);

      final processed = await _processor.process(
        imagePath: file.path,
        fallbackQuad: tracker?.value.hasDocument ?? false
            ? quadAtCapture
            : null,
        adjustments: _captureAdjustments(),
      );

      if (!mounted) return;
      goToScanResult(context, [
        ProcessedPage(
          originalPath: file.path,
          bytes: processed.bytes,
          quad: processed.quad,
          adjustments: processed.adjustments,
        ),
      ]);
    } catch (e) {
      debugPrint('Capture failed: $e');
      tracker?.releaseCaptureLock();
      if (mounted) {
        setState(() => _processing = false);
        _showMessage('Capture failed. Try again.');
        unawaited(_startStream());
      }
    } finally {
      _capturing = false;
    }
  }

  void _playShutter() {
    HapticFeedback.mediumImpact();
    if (ref.read(settingsProvider).shutterSound) {
      SystemSound.play(SystemSoundType.click);
    }
    _flashTimer?.cancel();
    _shutterFlash.value = 1;
    _flashTimer = Timer(const Duration(milliseconds: 120), () {
      _shutterFlash.value = 0;
    });
  }

  Future<void> _tapToFocus(TapDownDetails details, Size previewSize) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final point = Offset(
      (details.localPosition.dx / previewSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / previewSize.height).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      HapticFeedback.selectionClick();
    } catch (_) {
      // Not every device exposes focus points.
    }
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || kIsWeb) return;
    final next = _flash.next;
    try {
      await controller.setFlashMode(switch (next) {
        ScannerFlash.off => FlashMode.off,
        ScannerFlash.on => FlashMode.torch,
        ScannerFlash.auto => FlashMode.auto,
      });
      if (mounted) setState(() => _flash = next);
    } catch (e) {
      debugPrint('Flash unavailable: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Batch actions
  // -------------------------------------------------------------------------

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/library');
    }
  }

  void _setMode(ScanMode mode) {
    setState(() => _mode = mode);
    _tracker?.setMinAutoCaptureArea(mode.minAutoCaptureArea);
  }

  void _toggleAutoDetect() {
    setState(() => _autoDetect = !_autoDetect);
    if (!_autoDetect) {
      _tracker?.updateFromFrame(detected: null, confidence: 0);
    }
  }

  void _toggleAutoCapture() {
    final next = !ref.read(settingsProvider).autoCapture;
    ref.read(settingsProvider.notifier).setAutoCapture(next);
    _tracker?.setAutoCapture(next);
    setState(() {});
  }

  Future<void> _importFromGallery() async {
    if (_processing) return;
    await _stopStream();
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;

    if (picked == null) {
      unawaited(_startStream());
      return;
    }

    if (kIsWeb) {
      _showMessage('Import is available on device.');
      unawaited(_startStream());
      return;
    }

    setState(() => _processing = true);
    try {
      final processed = await _processor.process(
        imagePath: picked.path,
        adjustments: _captureAdjustments(),
      );
      if (!mounted) return;
      goToScanResult(context, [
        ProcessedPage(
          originalPath: picked.path,
          bytes: processed.bytes,
          quad: processed.quad,
          adjustments: processed.adjustments,
        ),
      ]);
    } catch (e) {
      debugPrint('Import failed: $e');
      if (mounted) {
        setState(() => _processing = false);
        _showMessage('Could not import that image.');
        unawaited(_startStream());
      }
    }
  }

  /// Filter applied to freshly captured pages, from settings.
  ScanAdjustments _captureAdjustments() =>
      ScanAdjustments(filter: ref.read(settingsProvider).defaultFilter);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const _WebDemoCamera();

    final error = _cameraError;
    if (error != null) {
      return _CameraErrorView(
        message: error,
        onRetry: () {
          setState(() => _cameraError = null);
          unawaited(_initCamera());
        },
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _CameraLoadingView();
    }

    ref.listen(settingsProvider.select((s) => s.autoCapture), (_, enabled) {
      _tracker?.setAutoCapture(enabled);
    });

    final autoCapture = ref.watch(
      settingsProvider.select((s) => s.autoCapture),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          ScannerTopBar(
            flash: _flash,
            onClose: _close,
            onToggleFlash: _cycleFlash,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPreview(controller),
                _buildShutterFlash(),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AutoDetectPill(
                      enabled: _autoDetect,
                      onToggle: _toggleAutoDetect,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(
                    child: _tracker == null
                        ? AlignHint(visible: _autoDetect)
                        : ValueListenableBuilder<ScanState>(
                            valueListenable: _tracker!.state,
                            builder: (context, state, _) {
                              final show =
                                  _autoDetect &&
                                  (state.phase == ScanPhase.searching ||
                                      state.phase == ScanPhase.positioning ||
                                      state.phase == ScanPhase.tooFar);
                              return AlignHint(visible: show);
                            },
                          ),
                  ),
                ),
                if (_processing)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 14),
                          Text(
                            'Enhancing page…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _tracker == null
              ? ScannerBottomBar(
                  mode: _mode,
                  autoCapture: autoCapture,
                  capturing: _capturing || _processing,
                  holdProgress: 0,
                  onModeSelected: _setMode,
                  onGallery: _importFromGallery,
                  onShutter: () => _capture(),
                  onToggleAuto: _toggleAutoCapture,
                )
              : ValueListenableBuilder<ScanState>(
                  valueListenable: _tracker!.state,
                  builder: (context, state, _) {
                    return ScannerBottomBar(
                      mode: _mode,
                      autoCapture: autoCapture,
                      capturing: _capturing || _processing,
                      holdProgress: autoCapture ? state.holdProgress : 0,
                      onModeSelected: _setMode,
                      onGallery: _importFromGallery,
                      onShutter: () => _capture(),
                      onToggleAuto: _toggleAutoCapture,
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController controller) {
    final buffer = controller.value.previewSize ?? const Size(720, 1280);
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final previewSize = Size(
      portrait ? buffer.shortestSide : buffer.longestSide,
      portrait ? buffer.longestSide : buffer.shortestSide,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _tapToFocus(
            details,
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: previewSize.width,
                height: previewSize.height,
                // The overlay is a child of CameraPreview so it shares the
                // preview's coordinate space; normalized corners then land on
                // the actual document pixels rather than on the screen box.
                child: CameraPreview(controller, child: _buildOverlay()),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlay() {
    final tracker = _tracker;
    if (tracker == null) return const SizedBox.expand();

    // Repaints on detection updates without rebuilding the controls above it.
    return ValueListenableBuilder<ScanState>(
      valueListenable: tracker.state,
      builder: (context, state, _) {
        if (!_autoDetect || !state.hasDocument) {
          return const SizedBox.expand();
        }
        return QuadOverlay(
          quad: state.quad,
          color: Brand.blue,
          locked: true,
          progress: 0,
          showCornerHandles: true,
          dimOutside: false,
        );
      },
    );
  }

  Widget _buildShutterFlash() {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: _shutterFlash,
        builder: (context, value, _) => AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 110),
          child: Container(color: Colors.white),
        ),
      ),
    );
  }
}

class _CameraLoadingView extends StatelessWidget {
  const _CameraLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting camera…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/library');
                  }
                },
                child: const Text(
                  'Go back',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebDemoCamera extends StatelessWidget {
  const _WebDemoCamera();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera (demo)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 96,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 16),
              const Text(
                'Scanning needs a device camera.\n'
                'Run Scan2 on iOS or Android to scan documents.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/library'),
                child: const Text('Back to library'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
