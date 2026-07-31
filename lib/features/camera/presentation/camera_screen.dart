import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan2/features/camera/domain/camera_frame_analyzer.dart';
import 'package:scan2/features/camera/domain/document_edge_tracker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/camera/presentation/widgets/quad_overlay.dart';
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
  final _frameAnalyzer = CameraFrameAnalyzer();
  DocumentEdgeTracker? _tracker;
  var _frameAnalysisBusy = false;
  var _streamActive = false;
  var _isCapturing = false;

  Quad _displayQuad = const Quad.centered();
  DetectionPhase _phase = DetectionPhase.looking;
  double _confidence = 0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initCamera();
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
    final autoDetect = ref.read(settingsProvider).autoDetectEdges;
    _tracker = DocumentEdgeTracker(onStable: _onAutoCapture)
      ..setAutoCapture(autoDetect)
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
          if (mounted) {
            setState(() {
              _displayQuad = _tracker?.quad ?? _displayQuad;
              _phase = _tracker?.phase ?? _phase;
              _confidence = _tracker?.confidence ?? _confidence;
            });
          }
        } else if (_tracker != null && mounted) {
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
        context.push('/crop', extra: null);
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
    if (image != null) {
      setState(() => _batchCount++);
      if (mounted) context.push('/crop', extra: null);
    }
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
    if (_confidence >= 0.78) return const Color(0xFF4CAF50);
    if (_confidence >= 0.5) return const Color(0xFFFFC107);
    return const Color(0xFF90CAF9);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && _cameraError != null) {
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
                  child: const Text('Go back', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!kIsWeb && (_controller == null || !_controller!.value.isInitialized)) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: kIsWeb ? Colors.grey[100] : Colors.black,
      body: Stack(
        children: [
          if (kIsWeb)
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
            )
          else
            CameraPreview(_controller!),

          if (!kIsWeb)
            QuadOverlay(quad: _displayQuad, color: _overlayColor),

          if (!kIsWeb)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
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
                  if (!kIsWeb)
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
                      Icons.photo_library,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _importFromGallery,
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
        ],
      ),
    );
  }
}
