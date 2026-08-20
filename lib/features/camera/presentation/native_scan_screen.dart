import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
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
          // VisionKit / ML Kit usually return a tight page. Crop again only
          // when a holder, desk or second book is still in the frame — a
          // second pass on an already-cropped page would eat into the text.
          detectEdges: true,
          onlyIfUncropped: true,
          adjustments: ScanAdjustments(filter: filter),
        );
        processed.add(
          ProcessedPage(
            originalPath: path,
            bytes: result.bytes,
            quad: result.quad ?? const Quad.fullFrame(),
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
                      style: BrandType.body.copyWith(color: Colors.white70),
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
                      style: BrandType.body.copyWith(color: Colors.white),
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
                      child: Text(
                        'Back to library',
                        style: BrandType.link.copyWith(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
