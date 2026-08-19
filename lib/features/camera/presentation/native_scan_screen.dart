import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/domain/native_document_scanner.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

/// The default scanning screen: hands straight over to the platform's own
/// document scanner — VisionKit on iOS, ML Kit Document Scanner on Android.
///
/// Those are trained models maintained by Apple and Google, and they beat the
/// in-app geometric detector on exactly the awkward frames that matter: a
/// small card on a patterned surface, a page in poor light, a document held at
/// an angle. Scan2's own value is everything after the capture — enhancement,
/// multi-page documents, re-editable pages, export — so the capture step uses
/// whatever detects best on the device.
///
/// Pages come back already perspective-corrected, so they only need enhancing
/// and filing.
class NativeScanScreen extends ConsumerStatefulWidget {
  const NativeScanScreen({super.key});

  @override
  ConsumerState<NativeScanScreen> createState() => _NativeScanScreenState();
}

class _NativeScanScreenState extends ConsumerState<NativeScanScreen> {
  static const _scanner = NativeDocumentScanner();
  static const _processor = PageProcessor();

  String _status = 'Opening scanner…';
  String? _error;
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_launched) return;
    _launched = true;

    if (kIsWeb) {
      setState(() => _error = 'Scanning needs a device camera.');
      return;
    }

    try {
      final pages = await _scanner.scan();

      // Cancelled from inside the system scanner.
      if (pages == null || pages.isEmpty) {
        if (mounted) context.pop();
        return;
      }

      if (!mounted) return;
      setState(
        () => _status = pages.length == 1
            ? 'Enhancing page…'
            : 'Enhancing ${pages.length} pages…',
      );

      final filter = ref.read(settingsProvider).defaultFilter;
      final processed = <ProcessedPage>[];
      for (final path in pages) {
        final result = await _processor.process(
          imagePath: path,
          // Already perspective-corrected by the platform scanner; running
          // edge detection again would only crop into the page.
          detectEdges: false,
          adjustments: ScanAdjustments(filter: filter),
        );
        processed.add(
          ProcessedPage(
            originalPath: path,
            bytes: result.bytes,
            // Recorded as full-frame so reopening the editor shows the page
            // as-is. Without it the crop screen would run detection on an
            // already-cropped page and crop a second time, into the content.
            quad: const Quad.fullFrame(),
            adjustments: result.adjustments,
          ),
        );
      }

      final repository = ref.read(documentRepositoryProvider);
      if (repository is! DocumentStore) {
        if (mounted) context.go('/library');
        return;
      }

      final doc = await repository.createProcessedDocument(pages: processed);
      bumpLibrary(ref);
      HapticFeedback.mediumImpact();

      if (!mounted) return;
      context.go('/library/document/${doc.id}');
    } catch (e) {
      debugPrint('Scan failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 20),
                    Text(
                      _status,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _launched = false;
                          _status = 'Opening scanner…';
                        });
                        _run();
                      },
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: () => context.go('/library'),
                      child: const Text(
                        'Back to library',
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
