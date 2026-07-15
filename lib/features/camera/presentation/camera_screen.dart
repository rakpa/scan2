import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/camera/presentation/widgets/quad_overlay.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isFlashOn = false;
  int _batchCount = 0;
  Quad? _currentQuad;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.back),
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || kIsWeb) return;
    _isFlashOn = !_isFlashOn;
    await _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _capture() async {
    if (kIsWeb) {
      HapticFeedback.mediumImpact();
      setState(() => _batchCount++);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demo: Page $_batchCount captured (web mock)')),
        );
      }
      return;
    }

    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile file = await _controller!.takePicture();
      HapticFeedback.mediumImpact();
      _currentQuad = await QuadDetector().detectQuadFromPath(file.path);

      setState(() => _batchCount++);

      if (mounted) {
        context.push('/crop', extra: null);
      }
    } catch (e) {
      debugPrint('Capture error: $e');
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
      final doc = repo.createDocument('Scan ${DateTime.now().toString().substring(0, 16)}');
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && (_controller == null || !_controller!.value.isInitialized)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            QuadOverlay(quad: _currentQuad ?? const Quad.centered()),

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
                      icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 28),
                      onPressed: _toggleFlash,
                    ),
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          icon: const Icon(Icons.photo, color: Colors.white, size: 32),
                          onPressed: _importFromGallery,
                        ),
                        GestureDetector(
                          onTap: _capture,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.white24,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
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