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
  const CameraScreen({super.key, this.initialMode = ScanMode.document});

  final ScanMode initialMode;

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

  final List<_PendingPage> _batch = [];
  String? _cameraError;
  bool _isFlashOn = false;
  bool _streaming = false;
  bool _capturing = false;
  bool _analyzing = false;
  bool _initializing = false;
  int _processingCount = 0;
  late ScanMode _mode = widget.initialMode;

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
      // The screen can be torn down while the shutter is open; everything
      // below touches state that dispose() has already released.
      if (!mounted) return;
      _playShutter();

      tracker?.lockAfterCapture(quadAtCapture ?? const Quad.centered());

      // Restart the preview immediately; processing continues in the
      // background so the next page can be framed while this one renders.
      unawaited(_startStream());

      setState(() => _processingCount++);
      final processed = await _processor.process(
        imagePath: file.path,
        // Fall back to the outline the preview was tracking, so a still that
        // fails to detect does not save as an uncropped full frame.
        fallbackQuad: tracker?.value.hasDocument ?? false
            ? quadAtCapture
            : null,
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
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPreview(controller),
                _buildShutterFlash(),
                _buildInstructionPill(),
              ],
            ),
          ),
          _buildBottomChrome(),
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
    if (state.hasDocument) return Brand.blue;
    if (state.phase == ScanPhase.capturing ||
        state.phase == ScanPhase.captured) {
      return const Color(0xFF4CAF50);
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
    final auto = ref.watch(settingsProvider.select((s) => s.autoCapture));
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Scan ',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Document',
                          style: TextStyle(color: Brand.blue),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _isFlashOn ? 'Torch on' : 'Torch off',
                  onPressed: _toggleFlash,
                  icon: Icon(
                    _isFlashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    color: _isFlashOn ? Brand.blue : Colors.white,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Auto capture is '),
                    TextSpan(
                      text: auto ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: auto ? const Color(0xFF35C759) : Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionPill() {
    final tracker = _tracker;
    if (tracker == null) {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _HintPill(text: 'Align document within the frame'),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ValueListenableBuilder<ScanState>(
          valueListenable: tracker.state,
          builder: (context, state, _) {
            final text = switch (state.phase) {
              ScanPhase.holdSteady => 'Hold steady…',
              ScanPhase.capturing || ScanPhase.captured => state.phase.message,
              ScanPhase.tooFar => state.phase.message,
              _ => 'Align document within the frame',
            };
            return _HintPill(text: text);
          },
        ),
      ),
    );
  }

  Widget _buildBottomChrome() {
    final tracker = _tracker;
    final auto = ref.watch(settingsProvider.select((s) => s.autoCapture));

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_processingCount > 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Enhancing page…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              if (_batch.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton(
                    onPressed: _finishBatch,
                    child: Text(
                      'Done (${_batch.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              _ModeSelector(
                mode: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildGalleryControl()),
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
                  Expanded(
                    child: _LabeledControl(
                      icon: auto
                          ? Icons.auto_awesome_mosaic_outlined
                          : Icons.crop_free_rounded,
                      label: auto ? 'Auto' : 'Manual',
                      onTap: () => ref
                          .read(settingsProvider.notifier)
                          .setAutoCapture(!auto),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryControl() {
    if (_batch.isEmpty) {
      return _LabeledControl(
        icon: Icons.photo_outlined,
        label: 'Gallery',
        onTap: _importFromGallery,
      );
    }

    final last = _batch.last;
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: _finishBatch,
        onLongPress: _discardLastPage,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_batch.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Gallery',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
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
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: progress <= 0.01 ? 0 : progress,
                strokeWidth: 3,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF35C759)),
              ),
            ),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                border: Border.all(color: Brand.blue, width: 4),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: onPressed == null ? 52 : 58,
              height: onPressed == null ? 52 : 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onPressed == null ? Colors.white54 : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final item in ScanMode.values)
          GestureDetector(
            onTap: () => onChanged(item),
            child: Column(
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: item == mode ? Brand.blue : Colors.white70,
                    fontSize: 14,
                    fontWeight: item == mode ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item == mode ? Brand.blue : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
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
