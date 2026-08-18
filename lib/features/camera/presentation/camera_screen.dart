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
import 'package:scan2/features/camera/domain/camera_frame_analyzer.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/native_document_scanner.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/camera/presentation/widgets/quad_overlay.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

/// A page captured in the current session, held until the batch is finished.
class _PendingPage {
  _PendingPage({required this.originalPath, required this.processed});

  final String originalPath;
  final ProcessedCapture processed;
}

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
  final _nativeScanner = NativeDocumentScanner();
  final _processor = const PageProcessor();

  final List<_PendingPage> _batch = [];
  String? _cameraError;
  bool _isFlashOn = false;
  bool _streaming = false;
  bool _capturing = false;
  bool _openingNative = false;
  bool _analyzing = false;
  int _processingCount = 0;

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
    if (_controller != null) return;
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        setState(
          () => _cameraError = 'Scan2 needs camera access to scan documents.',
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
      if (_analyzing || _capturing || !mounted) return;
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
    if (kIsWeb || _capturing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final tracker = _tracker;
    _capturing = true;
    final quadAtCapture = tracker?.value.quad;

    try {
      await _stopStream();
      final file = await controller.takePicture();
      _playShutter();

      tracker?.lockAfterCapture(quadAtCapture ?? const Quad.centered());

      // Restart the preview immediately; processing continues in the
      // background so the next page can be framed while this one renders.
      unawaited(_startStream());

      setState(() => _processingCount++);
      final processed = await _processor.process(
        imagePath: file.path,
        adjustments: _captureAdjustments(),
      );

      if (!mounted) return;
      setState(() {
        _processingCount--;
        _batch.add(_PendingPage(originalPath: file.path, processed: processed));
      });
    } catch (e) {
      debugPrint('Capture failed: $e');
      tracker?.releaseCaptureLock();
      if (mounted) {
        setState(
          () => _processingCount = _processingCount > 0
              ? _processingCount - 1
              : 0,
        );
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

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || kIsWeb) return;
    final next = !_isFlashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _isFlashOn = next);
    } catch (e) {
      debugPrint('Flash unavailable: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Batch actions
  // -------------------------------------------------------------------------

  Future<void> _finishBatch() async {
    if (_batch.isEmpty) {
      context.pop();
      return;
    }
    if (_processingCount > 0) {
      _showMessage('Finishing the last page…');
      return;
    }

    final repository = ref.read(documentRepositoryProvider);
    if (repository is! DocumentStore) {
      context.go('/library');
      return;
    }

    try {
      final doc = await repository.createProcessedDocument(
        pages: [
          for (final page in _batch)
            ProcessedPage(
              originalPath: page.originalPath,
              bytes: page.processed.bytes,
              quad: page.processed.quad,
              adjustments: page.processed.adjustments,
            ),
        ],
      );
      bumpLibrary(ref);
      if (!mounted) return;
      context.go('/library/document/${doc.id}');
    } catch (e) {
      debugPrint('Saving batch failed: $e');
      if (mounted) _showMessage('Could not save the scan: $e');
    }
  }

  void _discardLastPage() {
    if (_batch.isEmpty) return;
    setState(() => _batch.removeLast());
    HapticFeedback.selectionClick();
  }

  Future<void> _importFromGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    if (kIsWeb) {
      _showMessage('Import is available on device.');
      return;
    }

    setState(() => _processingCount++);
    try {
      final processed = await _processor.process(
        imagePath: picked.path,
        adjustments: _captureAdjustments(),
      );
      if (!mounted) return;
      setState(() {
        _processingCount--;
        _batch.add(
          _PendingPage(originalPath: picked.path, processed: processed),
        );
      });
    } catch (e) {
      debugPrint('Import failed: $e');
      if (mounted) {
        setState(() => _processingCount--);
        _showMessage('Could not import that image.');
      }
    }
  }

  Future<void> _openNativeScanner() async {
    if (kIsWeb || _openingNative) return;
    setState(() => _openingNative = true);
    await _stopStream();

    try {
      final pages = await _nativeScanner.scan();
      if (!mounted) return;

      if (pages == null || pages.isEmpty) {
        await _startStream();
        return;
      }

      final repository = ref.read(documentRepositoryProvider);
      final doc = await repository.createDocumentFromScans(
        pages,
        edgesAlreadyApplied: true,
      );
      bumpLibrary(ref);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      context.go('/library/document/${doc.id}');
    } catch (e) {
      debugPrint('Native scanner failed: $e');
      if (mounted) {
        _showMessage('$e');
        await _startStream();
      }
    } finally {
      if (mounted) setState(() => _openingNative = false);
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
    if (error != null) return _CameraErrorView(message: error);

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _CameraLoadingView();
    }

    // Keep auto-capture in step with the setting while the screen is open.
    ref.listen(settingsProvider.select((s) => s.autoCapture), (_, enabled) {
      _tracker?.setAutoCapture(enabled);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(controller),
          _buildShutterFlash(),
          _buildTopBar(),
          _buildStatusPill(),
          _buildBottomBar(),
          if (_openingNative) const _BlockingOverlay(label: 'Opening scanner…'),
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
        return QuadOverlay(
          quad: state.quad,
          color: _overlayColor(state),
          locked: state.hasDocument,
          progress: state.holdProgress,
        );
      },
    );
  }

  Color _overlayColor(ScanState state) {
    if (state.phase == ScanPhase.capturing ||
        state.phase == ScanPhase.captured) {
      return const Color(0xFF4CAF50);
    }
    if (state.confidence >= DocumentEdgeTracker.autoCaptureConfidence) {
      return const Color(0xFF4CAF50);
    }
    if (state.confidence >= DocumentEdgeTracker.minTrackConfidence) {
      return const Color(0xFFFFC107);
    }
    return Colors.white70;
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

  Widget _buildTopBar() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _CircleButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              _CircleButton(
                icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                tooltip: _isFlashOn ? 'Torch on' : 'Torch off',
                active: _isFlashOn,
                onPressed: _toggleFlash,
              ),
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.document_scanner_outlined,
                tooltip: 'System scanner',
                onPressed: _openingNative ? null : _openNativeScanner,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill() {
    final tracker = _tracker;
    if (tracker == null) return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: ValueListenableBuilder<ScanState>(
            valueListenable: tracker.state,
            builder: (context, state, _) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      switch (state.phase) {
                        ScanPhase.searching => Icons.search,
                        ScanPhase.positioning => Icons.crop_free,
                        ScanPhase.holdSteady => Icons.center_focus_strong,
                        ScanPhase.capturing => Icons.camera,
                        ScanPhase.captured => Icons.check_circle,
                      },
                      size: 18,
                      color: _overlayColor(state),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      state.phase.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final tracker = _tracker;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_processingCount > 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Enhancing page…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(child: _buildBatchThumbnail()),
                    if (tracker != null)
                      ValueListenableBuilder<ScanState>(
                        valueListenable: tracker.state,
                        builder: (context, state, _) => _ShutterButton(
                          progress: state.holdProgress,
                          onPressed: _capturing ? null : () => _capture(),
                        ),
                      )
                    else
                      _ShutterButton(
                        progress: 0,
                        onPressed: _capturing ? null : () => _capture(),
                      ),
                    Expanded(child: _buildTrailingAction()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBatchThumbnail() {
    if (_batch.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _CircleButton(
          icon: Icons.photo_library_outlined,
          tooltip: 'Import from photos',
          onPressed: _importFromGallery,
        ),
      );
    }

    final last = _batch.last;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: _finishBatch,
        onLongPress: _discardLastPage,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
                image: DecorationImage(
                  image: MemoryImage(last.processed.bytes),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_batch.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingAction() {
    return Align(
      alignment: Alignment.centerRight,
      child: _batch.isEmpty
          ? const SizedBox(width: 48, height: 48)
          : FilledButton(
              onPressed: _finishBatch,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text('Done (${_batch.length})'),
            ),
    );
  }
}

// -------------------------------------------------------------------------
// Small presentation pieces
// -------------------------------------------------------------------------

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.progress, required this.onPressed});

  final double progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ring fills as auto-capture approaches, so the shutter never
            // fires as a surprise.
            SizedBox(
              width: 78,
              height: 78,
              child: CircularProgressIndicator(
                value: progress <= 0.01 ? 0 : progress,
                strokeWidth: 4,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: onPressed == null ? 56 : 64,
              height: onPressed == null ? 56 : 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onPressed == null ? Colors.white54 : Colors.white,
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black38),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: active ? Colors.white : Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: active ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockingOverlay extends StatelessWidget {
  const _BlockingOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
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
  const _CameraErrorView({required this.message});

  final String message;

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
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () => context.pop(),
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
