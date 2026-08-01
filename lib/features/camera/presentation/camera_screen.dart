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
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/library/data/drift/database.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  CameraDescription? _activeCamera;
  bool _isFlashOn = false;
  int _batchCount = 0;
  String? _cameraError;
  final ImagePicker _picker = ImagePicker();
  final _nativeScanner = NativeDocumentScanner();
  final _frameAnalyzer = CameraFrameAnalyzer();
  DocumentEdgeTracker? _tracker;
  var _frameAnalysisBusy = false;
  var _streamActive = false;
  var _isCapturing = false;
  var _openingNative = false;

  Quad _displayQuad = const Quad.centered();
  DetectionPhase _phase = DetectionPhase.looking;
  double _confidence = 0;

  @override
  void initState() {
    super.initState();
    // Live camera + edge guides first (Scanella UX). Native VisionKit is a
    // one-tap action that returns already-cropped pages.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
    }
  }

  Future<void> _openNativeScanner() async {
    if (kIsWeb || _openingNative) return;
    setState(() => _openingNative = true);

    // Pause live stream so VisionKit can take the camera.
    await _stopFrameAnalysis();

    try {
      final pages = await _nativeScanner.scan(maxPages: 24);
      if (!mounted) return;

      if (pages == null || pages.isEmpty) {
        // Cancelled — resume live guides.
        await _startFrameAnalysis();
        return;
      }

      final db = ref.read(appDatabaseProvider) as AppDatabase;
      final doc = await db.createDocumentFromScans(
        pages,
        edgesAlreadyApplied: true,
      );
      bumpLibrary(ref);
      HapticFeedback.mediumImpact();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${pages.length} page${pages.length == 1 ? '' : 's'} '
            'scanned with edge detection',
          ),
        ),
      );
      // Land on the document, then open enhance (edges already applied).
      context.go('/library/document/${doc.id}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.push(
          '/crop',
          extra: CropArgs(
            imagePath: doc.pagePaths.first,
            edgesAlreadyApplied: true,
          ),
        );
      });
    } catch (e) {
      debugPrint('Native scanner error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanner error: $e')),
        );
        await _startFrameAnalysis();
      }
    } finally {
      if (mounted) setState(() => _openingNative = false);
    }
  }

  Future<void> _initCamera() async {
    try {
      final granted = await Permission.camera.request();
      if (!granted.isGranted) {
        if (mounted) {
          setState(() {
            _cameraError =
                'Camera permission is required to scan documents.';
          });
        }
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No camera found on this device.');
        }
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _activeCamera = back;

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
      _controller = controller;

      _startTracker();
      await _startFrameAnalysis();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _cameraError = 'Camera failed to start: $e');
      }
    }
  }

  void _startTracker() {
    _tracker?.dispose();
    final autoCapture = ref.read(settingsProvider).autoDetectEdges;
    _tracker = DocumentEdgeTracker(onStable: _onAutoCapture)
      ..setAutoCapture(autoCapture)
      ..start();
  }

  Future<void> _startFrameAnalysis() async {
    final controller = _controller;
    final camera = _activeCamera;
    if (controller == null ||
        !controller.value.isInitialized ||
        camera == null ||
        _streamActive) {
      return;
    }

    await controller.startImageStream((image) {
      if (_frameAnalysisBusy || _isCapturing) return;
      _frameAnalysisBusy = true;
      try {
        final result = _frameAnalyzer.analyzeThrottled(image, camera);
        if (result != null) {
          _tracker?.updateFromFrame(
            detected: result.quad,
            frameConfidence: result.confidence,
          );
        }
        if (_tracker != null && mounted) {
          setState(() {
            _displayQuad = _tracker!.quad;
            _phase = _tracker!.phase;
            _confidence = _tracker!.confidence;
          });
        }
      } catch (e, st) {
        debugPrint('Frame analysis failed: $e\n$st');
      } finally {
        _frameAnalysisBusy = false;
      }
    });
    _streamActive = true;
  }

  Future<void> _stopFrameAnalysis() async {
    final controller = _controller;
    if (controller == null || !_streamActive) {
      _streamActive = false;
      return;
    }
    try {
      await controller.stopImageStream();
    } catch (_) {}
    _streamActive = false;
  }

  Future<void> _onAutoCapture() async {
    await _capture(fromAuto: true);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || kIsWeb) return;
    _isFlashOn = !_isFlashOn;
    await _controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
    setState(() {});
  }

  Future<void> _capture({bool fromAuto = false}) async {
    if (kIsWeb) {
      HapticFeedback.mediumImpact();
      setState(() => _batchCount++);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Demo: Page $_batchCount captured (web mock)'),
          ),
        );
      }
      return;
    }

    if (_isCapturing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isCapturing = true;
    try {
      await _stopFrameAnalysis();
      final XFile file = await _controller!.takePicture();
      HapticFeedback.mediumImpact();

      final detected = await const QuadDetector().detectQuadFromPath(file.path);
      _tracker?.lockAfterCapture(detected);

      // Persist the capture so library / crop have a real image.
      final db = ref.read(appDatabaseProvider) as AppDatabase;
      final doc = await db.createDocumentFromScans(
        [file.path],
        title: 'Scan ${DateTime.now().toString().substring(0, 16)}',
        edgesAlreadyApplied: false,
      );
      bumpLibrary(ref);

      setState(() {
        _batchCount++;
        _displayQuad = detected;
        _phase = DetectionPhase.pageCaptured;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fromAuto
                  ? 'Auto-scanned page $_batchCount'
                  : 'Page $_batchCount captured',
            ),
            duration: const Duration(milliseconds: 900),
          ),
        );
        context.push(
          '/crop',
          extra: CropArgs(
            imagePath: doc.pagePaths.first,
            initialQuad: detected,
            edgesAlreadyApplied: false,
          ),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      _tracker?.releaseCaptureLock();
    } finally {
      _isCapturing = false;
      if (mounted && _controller != null && _controller!.value.isInitialized) {
        await _startFrameAnalysis();
      }
    }
  }

  Future<void> _importFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    if (!kIsWeb) {
      final db = ref.read(appDatabaseProvider) as AppDatabase;
      final doc = await db.createDocumentFromScans(
        [image.path],
        edgesAlreadyApplied: false,
      );
      bumpLibrary(ref);
      if (!mounted) return;
      context.push(
        '/crop',
        extra: CropArgs(
          imagePath: doc.pagePaths.first,
          edgesAlreadyApplied: false,
        ),
      );
      return;
    }

    setState(() => _batchCount++);
    context.push('/crop', extra: null);
  }

  void _finishBatch() {
    if (kIsWeb) {
      final repo = ref.read(webDemoRepositoryProvider);
      final doc = repo.createDocument(
        'Scan ${DateTime.now().toString().substring(0, 16)}',
      );
      for (int i = 0; i < _batchCount; i++) {
        repo.addPageToDocument(doc.id);
      }
      bumpLibrary(ref);
      context.go('/library');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo document created in browser!')),
      );
      return;
    }
    context.go('/library');
  }

  @override
  void dispose() {
    _tracker?.dispose();
    final controller = _controller;
    if (controller != null) {
      if (_streamActive) {
        controller.stopImageStream().catchError((_) {});
      }
      controller.dispose();
    }
    super.dispose();
  }

  Color get _overlayColor {
    if (_phase == DetectionPhase.capturing || _confidence >= 0.78) {
      return const Color(0xFF4CAF50);
    }
    if (_confidence >= 0.5) return const Color(0xFFFFC107);
    return const Color(0xFF4FC3F7);
  }

  /// Preview + overlay share one coordinate space (Scanella-proven layout).
  Widget _previewWithOverlay(CameraController camera, Widget overlay) {
    final buffer = camera.value.previewSize ?? const Size(720, 1280);
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final shortSide = buffer.shortestSide;
    final longSide = buffer.longestSide;
    final size = Size(
      portrait ? shortSide : longSide,
      portrait ? longSide : shortSide,
    );

    return SizedBox(
      width: size.width,
      height: size.height,
      child: CameraPreview(
        camera,
        child: Stack(
          fit: StackFit.expand,
          children: [overlay],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebDemo(context);
    }

    if (_cameraError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => openAppSettings(),
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

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                _openingNative
                    ? 'Opening edge scanner…'
                    : 'Starting camera…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      );
    }

    final camera = _controller!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Critical: overlay is a child of CameraPreview inside BoxFit.cover
          // so normalized quads land on the real document pixels.
          SizedBox.expand(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: _previewWithOverlay(
                  camera,
                  QuadOverlay(quad: _displayQuad, color: _overlayColor),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 56),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _phase.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => context.pop(),
                  ),
                  IconButton(
                    icon: Icon(
                      _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _toggleFlash,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.document_scanner,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: 'Native edge scanner',
                    onPressed: _openingNative ? null : _openNativeScanner,
                  ),
                ],
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_batchCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_batchCount pages captured',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openingNative ? null : _openNativeScanner,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Scan with auto edges'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.photo,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: _importFromGallery,
                        ),
                        GestureDetector(
                          onTap: () => _capture(),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white24,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _batchCount > 0 ? _finishBatch : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_openingNative)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Opening system edge scanner…',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebDemo(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          Container(
            color: Colors.grey[300],
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 120, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'Web Demo Mode\nTap shutter to simulate capture',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IconButton(
                icon: const Icon(Icons.close, size: 28),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: GestureDetector(
                  onTap: () => _capture(),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black54, width: 4),
                      color: Colors.white,
                    ),
                    child: const Icon(Icons.camera_alt, size: 36),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
