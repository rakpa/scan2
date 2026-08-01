import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/perspective_transformer.dart';
import 'package:scan2/features/crop/presentation/widgets/draggable_quad.dart';
import 'package:scan2/features/library/data/drift/database.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class CropScreen extends ConsumerStatefulWidget {
  final int? pageId;
  final String? imagePath;
  final Quad? initialQuad;
  final bool edgesAlreadyApplied;

  const CropScreen({
    super.key,
    this.pageId,
    this.imagePath,
    this.initialQuad,
    this.edgesAlreadyApplied = false,
  });

  factory CropScreen.fromArgs(CropArgs args) {
    return CropScreen(
      pageId: args.pageId,
      imagePath: args.imagePath,
      initialQuad: args.initialQuad,
      edgesAlreadyApplied: args.edgesAlreadyApplied,
    );
  }

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  late Quad _quad;
  late ScanFilter _filter;
  double _brightness = 0;
  double _contrast = 0;
  var _detecting = false;
  var _showEdgeHandles = true;
  var _saving = false;
  var _previewBusy = false;
  int _previewToken = 0;
  int _quadGeneration = 0;
  Uint8List? _sourceBytes;
  Uint8List? _previewBytes;
  Timer? _previewDebounce;

  final _processor = ImageProcessor();
  final _transformer = PerspectiveTransformer();

  @override
  void initState() {
    super.initState();
    _filter = ScanFilter.magic;
    _quad = widget.edgesAlreadyApplied
        ? const Quad.fullFrame()
        : (widget.initialQuad ?? const Quad.centered());
    _showEdgeHandles = !widget.edgesAlreadyApplied;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      setState(() {
        _filter =
            settings.enhanceByDefault ? ScanFilter.magic : ScanFilter.original;
      });
      _loadSourceAndPreview();
    });

    _maybeDetectEdges();
  }

  void _maybeDetectEdges() {
    final path = widget.imagePath;
    if (path == null || kIsWeb) return;
    if (widget.edgesAlreadyApplied) return;
    if (widget.initialQuad != null) return;

    _detecting = true;
    const QuadDetector().detectQuadFromPath(path).then((q) {
      if (!mounted) return;
      setState(() {
        _quad = q;
        _quadGeneration++;
        _detecting = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _detecting = false);
    });
  }

  Future<void> _loadSourceAndPreview() async {
    final path = widget.imagePath;
    if (path == null || kIsWeb) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() => _sourceBytes = bytes);
      await _schedulePreview(immediate: true);
    } catch (e) {
      debugPrint('Failed to load crop source: $e');
    }
  }

  void _onFilterSelected(ScanFilter filter) {
    setState(() => _filter = filter);
    _schedulePreview();
  }

  void _onBrightness(double v) {
    setState(() => _brightness = v);
    _schedulePreview();
  }

  void _onContrast(double v) {
    setState(() => _contrast = v);
    _schedulePreview();
  }

  Future<void> _schedulePreview({bool immediate = false}) async {
    _previewDebounce?.cancel();
    if (immediate) {
      await _rebuildPreview();
      return;
    }
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      _rebuildPreview();
    });
  }

  Future<void> _rebuildPreview() async {
    final source = _sourceBytes;
    if (source == null) return;

    final token = ++_previewToken;
    setState(() => _previewBusy = true);
    try {
      final filtered = await _processor.applyFilter(
        imageBytes: source,
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
      );
      if (!mounted || token != _previewToken) return;
      setState(() {
        _previewBytes = filtered;
        _previewBusy = false;
      });
    } catch (e) {
      debugPrint('Preview filter failed: $e');
      if (mounted && token == _previewToken) {
        setState(() => _previewBusy = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final path = widget.imagePath;

    if (kIsWeb || path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page saved')),
      );
      context.pop();
      return;
    }

    setState(() => _saving = true);
    try {
      final source = _sourceBytes ?? await File(path).readAsBytes();
      final warped = widget.edgesAlreadyApplied && !_showEdgeHandles
          ? source
          : await _transformer.warp(imageBytes: source, quad: _quad);
      final filtered = await _processor.applyFilter(
        imageBytes: warped,
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
      );

      final db = ref.read(appDatabaseProvider);
      if (db is AppDatabase) {
        final owner = await db.findDocumentByPagePath(path);
        if (owner != null) {
          await db.replacePageBytes(
            documentId: owner.id,
            pagePath: path,
            bytes: filtered,
          );
        } else {
          await File(path).writeAsBytes(filtered, flush: true);
        }
        bumpLibrary(ref);
      } else {
        await File(path).writeAsBytes(filtered, flush: true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page saved')),
      );
      context.pop();
    } catch (e) {
      debugPrint('Save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = widget.imagePath;
    final preview = _previewBytes;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.edgesAlreadyApplied && !_showEdgeHandles
              ? (kIsWeb ? 'Enhance (Demo)' : 'Enhance')
              : (kIsWeb ? 'Crop & Enhance (Demo)' : 'Crop & Enhance'),
        ),
        actions: [
          if (widget.edgesAlreadyApplied)
            TextButton(
              onPressed: () {
                setState(() {
                  _showEdgeHandles = !_showEdgeHandles;
                  if (!_showEdgeHandles) {
                    _quad = const Quad.fullFrame();
                  }
                });
              },
              child: Text(_showEdgeHandles ? 'Hide edges' : 'Adjust edges'),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Container(
                  color: Colors.black87,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: path != null && !kIsWeb
                            ? (preview != null
                                ? Image.memory(
                                    preview,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  )
                                : Image.file(
                                    File(path),
                                    fit: BoxFit.contain,
                                  ))
                            : Container(
                                margin: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.description,
                                    size: 96,
                                    color: Colors.black38,
                                  ),
                                ),
                              ),
                      ),
                      if (_detecting || _previewBusy)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      if (_showEdgeHandles)
                        DraggableQuad(
                          key: ValueKey(_quadGeneration),
                          initialQuad: _quad,
                          size: size,
                          onChanged: (q) => setState(() => _quad = q),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: ScanFilter.values.map((f) {
                          final selected = f == _filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(ImageProcessor.labelFor(f)),
                              selected: selected,
                              onSelected: (_) => _onFilterSelected(f),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Brightness',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Slider(
                      value: _brightness,
                      min: -1,
                      max: 1,
                      onChanged: _onBrightness,
                    ),
                    Text(
                      'Contrast',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Slider(
                      value: _contrast,
                      min: -1,
                      max: 1,
                      activeColor: scheme.primary,
                      onChanged: _onContrast,
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
