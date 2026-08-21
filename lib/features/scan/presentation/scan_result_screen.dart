import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/domain/page_processor.dart';
import 'package:scan2/features/crop/domain/scan_preview.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/export_service.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';

/// Enhancement chips shown under the page preview (mockup labels).
enum _EnhancePreset {
  original,
  autoEnhance,
  bw,
  magicColor,
  grayscale,
}

extension _EnhancePresetX on _EnhancePreset {
  String get label => switch (this) {
    _EnhancePreset.original => 'Original',
    _EnhancePreset.autoEnhance => 'Auto Enhance',
    _EnhancePreset.bw => 'B&W',
    _EnhancePreset.magicColor => 'Magic Color',
    _EnhancePreset.grayscale => 'Grayscale',
  };

  ScanFilter get filter => switch (this) {
    _EnhancePreset.original => ScanFilter.original,
    _EnhancePreset.autoEnhance => ScanFilter.magic,
    _EnhancePreset.bw => ScanFilter.bw,
    _EnhancePreset.magicColor => ScanFilter.enhance,
    _EnhancePreset.grayscale => ScanFilter.grayscale,
  };

  static _EnhancePreset fromFilter(ScanFilter filter) => switch (filter) {
    ScanFilter.original => _EnhancePreset.original,
    ScanFilter.magic => _EnhancePreset.autoEnhance,
    ScanFilter.bw => _EnhancePreset.bw,
    ScanFilter.enhance => _EnhancePreset.magicColor,
    ScanFilter.grayscale => _EnhancePreset.grayscale,
  };
}

/// Opens the scan-result editor instead of filing the capture immediately.
void goToScanResult(BuildContext context, List<ProcessedPage> pages) {
  if (!context.mounted) return;
  if (pages.isEmpty) {
    context.go('/library');
    return;
  }
  context.go(
    '/scan-result',
    extra: ScanResultArgs(
      pages: [
        for (final page in pages)
          ScanResultPageDraft(
            originalPath: page.originalPath,
            bytes: page.bytes,
            quad: page.quad,
            adjustments: page.adjustments,
          ),
      ],
    ),
  );
}

/// Review screen shown immediately after a capture: preview, presets, edit
/// actions, then Save into the library.
class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({super.key, required this.args});

  final ScanResultArgs args;

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  static const _processor = PageProcessor();
  static const _exporter = ExportService();

  late final List<_PageEdit> _pages;
  int _index = 0;
  bool _saving = false;
  final GlobalKey _presetsKey = GlobalKey();

  _PageEdit get _current => _pages[_index];

  @override
  void initState() {
    super.initState();
    _pages = widget.args.pages.map(_PageEdit.fromDraft).toList();
  }

  Future<void> _crop() async {
    final page = _current;
    var originalPath = page.originalPath;
    var turns = page.quarterTurns % 4;
    if (turns != 0) {
      final rotated = await _bakeRotation(originalPath, turns);
      if (rotated == null) return;
      originalPath = rotated;
      turns = 0;
    }
    if (!mounted) return;
    final result = await context.push<CropResult>(
      '/crop',
      extra: CropArgs(
        imagePath: originalPath,
        initialQuad: page.quad,
        adjustments: page.adjustments,
        edgesAlreadyApplied: true,
        popWithResult: true,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      page.originalPath = originalPath;
      page.quarterTurns = turns;
      page.quad = result.quad;
      page.adjustments = result.adjustments;
      page.preset = _EnhancePresetX.fromFilter(result.adjustments.filter);
      page.previewBytes = result.bytes;
      page.invalidateThumbs();
    });
  }

  Future<String?> _bakeRotation(String path, int quarterTurns) async {
    try {
      final src = await File(path).readAsBytes();
      final decoded = img.decodeImage(src);
      if (decoded == null) return null;
      final rotated = img.copyRotate(decoded, angle: (quarterTurns % 4) * 90);
      final png = _isPng(src);
      final out = await File(
        '${Directory.systemTemp.path}/scanella_rot_${DateTime.now().millisecondsSinceEpoch}${png ? '.png' : '.jpg'}',
      ).create();
      await out.writeAsBytes(
        png ? img.encodePng(rotated) : img.encodeJpg(rotated, quality: 95),
        flush: true,
      );
      return out.path;
    } catch (e) {
      debugPrint('Rotation bake failed: $e');
      return null;
    }
  }

  void _rotate() {
    setState(() => _current.quarterTurns = (_current.quarterTurns + 1) % 4);
  }

  Future<void> _adjust() async {
    final page = _current;
    var brightness = page.adjustments.brightness;
    var contrast = page.adjustments.contrast;
    var sharpness = page.adjustments.sharpness;
    var saturation = page.adjustments.saturation;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Brand.ink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Adjust', style: BrandType.title),
                  const SizedBox(height: 8),
                  _AdjustSlider(
                    label: 'Brightness',
                    value: brightness,
                    onChanged: (v) => setSheet(() => brightness = v),
                  ),
                  _AdjustSlider(
                    label: 'Contrast',
                    value: contrast,
                    onChanged: (v) => setSheet(() => contrast = v),
                  ),
                  _AdjustSlider(
                    label: 'Sharpness',
                    value: sharpness,
                    onChanged: (v) => setSheet(() => sharpness = v),
                  ),
                  _AdjustSlider(
                    label: 'Saturation',
                    value: saturation,
                    onChanged: (v) => setSheet(() => saturation = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (applied != true || !mounted) return;
    page.adjustments = page.adjustments.copyWith(
      brightness: brightness,
      contrast: contrast,
      sharpness: sharpness,
      saturation: saturation,
    );
    page.invalidateThumbs();
    setState(() {});
    await _rerender(page);
  }

  Future<void> _selectPreset(_EnhancePreset preset) async {
    final page = _current;
    if (page.preset == preset) return;
    page.preset = preset;
    page.adjustments = page.adjustments.copyWith(filter: preset.filter);
    page.invalidateThumbs();
    setState(() {});
    await _rerender(page);
  }

  Future<void> _rerender(_PageEdit page) async {
    final gen = ++page.renderGen;
    try {
      final bytes = await page.renderFull(_processor);
      if (!mounted || gen != page.renderGen) return;
      setState(() => page.previewBytes = bytes);
    } catch (e) {
      debugPrint('Preview render failed: $e');
    }
  }

  Future<void> _retake() async {
    final editing = widget.args.existingDocumentId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(editing ? 'Discard edits?' : 'Retake scan?'),
          content: Text(
            editing
                ? 'Unsaved changes to this document will be discarded.'
                : 'This capture will be discarded and you will return to the camera.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(editing ? 'Discard' : 'Retake'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      if (editing) {
        _back();
      } else {
        context.go('/camera');
      }
    }
  }

  void _back() {
    final id = widget.args.existingDocumentId;
    if (id != null) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/library/document/$id');
      }
      return;
    }
    context.go('/library');
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(documentRepositoryProvider);
      if (repository is! DocumentStore) {
        if (mounted) context.go('/library');
        return;
      }
      final processed = await Future.wait([
        for (final page in _pages) page.toProcessed(_processor),
      ]);
      final existingId = widget.args.existingDocumentId;
      Document doc;
      if (existingId != null) {
        final updated = await repository.replaceProcessedDocument(
          documentId: existingId,
          pages: processed,
        );
        if (updated == null) {
          throw StateError('This document is no longer in the library.');
        }
        doc = updated;
      } else {
        final title = await repository.nextScanTitle();
        doc = await repository.createProcessedDocument(
          pages: processed,
          title: title,
        );
      }
      try {
        final pdfBytes = await _exporter.buildPdfBytes(doc);
        doc = await repository.attachPdf(documentId: doc.id, bytes: pdfBytes) ??
            doc;
      } catch (e) {
        debugPrint('Local PDF generation failed, keeping image pages: $e');
      }
      bumpLibrary(ref);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (existingId != null) {
        context.go('/library/document/${doc.id}');
      } else {
        context.go('/saved/${doc.id}');
      }
    } catch (e) {
      debugPrint('Scan save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  void _revealFilters() {
    final ctx = _presetsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _current;
    final count = _pages.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(saving: _saving, onBack: _back, onSave: _save),
              _StatusRow(
                pageLabel: 'Page ${_index + 1} of $count',
                onCrop: _crop,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _DocumentCard(
                    bytes: page.previewBytes,
                    quarterTurns: page.quarterTurns,
                  ),
                ),
              ),
              if (count > 1)
                _PageDots(
                  count: count,
                  index: _index,
                  onChanged: (i) => setState(() => _index = i),
                ),
              _EditToolbar(
                onCrop: _crop,
                onRotate: _rotate,
                onFilter: _revealFilters,
                onAdjust: _adjust,
                onRetake: _retake,
              ),
              KeyedSubtree(
                key: _presetsKey,
                child: _PresetStrip(page: page, onSelect: _selectPreset),
              ),
              _SaveDocumentButton(saving: _saving, onSave: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageEdit {
  _PageEdit({
    required this.originalPath,
    required this.previewBytes,
    required this.quad,
    required this.adjustments,
    required this.preset,
    required this.quarterTurns,
  });

  factory _PageEdit.fromDraft(ScanResultPageDraft draft) {
    return _PageEdit(
      originalPath: draft.originalPath,
      previewBytes: draft.bytes,
      quad: draft.quad ?? const Quad.fullFrame(),
      adjustments: draft.adjustments,
      preset: _EnhancePresetX.fromFilter(draft.adjustments.filter),
      quarterTurns: draft.rotationQuarterTurns,
    );
  }

  String originalPath;
  Uint8List previewBytes;
  Quad quad;
  ScanAdjustments adjustments;
  _EnhancePreset preset;
  int quarterTurns;
  int renderGen = 0;

  final Map<_EnhancePreset, Uint8List> thumbs = {};

  void invalidateThumbs() => thumbs.clear();

  Future<Uint8List> renderFull(PageProcessor processor) {
    return File(originalPath).readAsBytes().then(
      (sourceBytes) => processor.render(
        sourceBytes: sourceBytes,
        quad: quad,
        adjustments: adjustments,
      ),
    );
  }

  Future<ProcessedPage> toProcessed(PageProcessor processor) async {
    var path = originalPath;
    final turns = quarterTurns % 4;
    // Capture and filter changes already produced [previewBytes] at full
    // scan resolution. Re-running Auto/B&W on every page is what made a
    // passport save take so long.
    if (turns == 0) {
      return ProcessedPage(
        originalPath: path,
        bytes: previewBytes,
        quad: quad,
        adjustments: adjustments,
      );
    }
    final src = await File(path).readAsBytes();
    final decoded = img.decodeImage(src);
    if (decoded != null) {
      final rotated = img.copyRotate(decoded, angle: turns * 90);
      final png = _isPng(src);
      final out = await File(
        '${Directory.systemTemp.path}/scanella_save_${DateTime.now().millisecondsSinceEpoch}${png ? '.png' : '.jpg'}',
      ).create();
      await out.writeAsBytes(
        png ? img.encodePng(rotated) : img.encodeJpg(rotated, quality: 95),
        flush: true,
      );
      path = out.path;
    }
    final bytes = await processor.render(
      sourceBytes: await File(path).readAsBytes(),
      quad: quad,
      adjustments: adjustments,
    );
    return ProcessedPage(
      originalPath: path,
      bytes: bytes,
      quad: quad,
      adjustments: adjustments,
    );
  }

  Future<Uint8List> thumbFor(_EnhancePreset p) async {
    final cached = thumbs[p];
    if (cached != null) return cached;
    try {
      final fileBytes = await File(originalPath).readAsBytes();
      final source = await loadPreviewSource(fileBytes);
      if (source == null) return previewBytes;
      final raster = await renderPreview(
        PreviewRequest(
          source: source,
          adjustments: adjustments.copyWith(filter: p.filter),
          quad: quad,
        ),
      );
      final jpeg = Uint8List.fromList(
        img.encodeJpg(raster.downscaledTo(220).toImage(), quality: 70),
      );
      thumbs[p] = jpeg;
      return jpeg;
    } catch (_) {
      return previewBytes;
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.saving,
    required this.onBack,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 32),
              color: Brand.blue,
            ),
            const Expanded(
              child: Center(
                child: ScanellaWordmark(fontSize: 22, color: Brand.blue),
              ),
            ),
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Brand.blue.withValues(alpha: 0.45),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: BrandType.button.copyWith(fontSize: 15),
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.pageLabel, required this.onCrop});

  final String pageLabel;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 36),
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: Brand.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Brand.outline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Auto-detect • $pageLabel',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Brand.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Crop',
              onPressed: onCrop,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.crop_rounded, color: Brand.blue, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.bytes, required this.quarterTurns});

  final Uint8List bytes;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Brand.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Brand.ink.withValues(alpha: 0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RotatedBox(
                      quarterTurns: quarterTurns % 4,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.onChanged,
  });

  final int count;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: index == 0 ? null : () => onChanged(index - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: Brand.ink,
          ),
          for (var i = 0; i < count; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: i == index ? 18 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == index
                      ? Brand.blue
                      : Brand.ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          IconButton(
            onPressed: index >= count - 1 ? null : () => onChanged(index + 1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: Brand.ink,
          ),
        ],
      ),
    );
  }
}

class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.onCrop,
    required this.onRotate,
    required this.onFilter,
    required this.onAdjust,
    required this.onRetake,
  });

  final VoidCallback onCrop;
  final VoidCallback onRotate;
  final VoidCallback onFilter;
  final VoidCallback onAdjust;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _ToolButton(
            icon: const Icon(Icons.crop_rounded),
            label: 'Crop',
            onTap: onCrop,
          ),
          _ToolButton(
            icon: const Icon(Icons.rotate_right_rounded),
            label: 'Rotate',
            onTap: onRotate,
          ),
          _ToolButton(
            icon: const _VennIcon(),
            label: 'Filter',
            onTap: onFilter,
          ),
          _ToolButton(
            icon: const Icon(Icons.tune_rounded),
            label: 'Adjust',
            onTap: onAdjust,
          ),
          _ToolButton(
            icon: const Icon(Icons.refresh_rounded),
            label: 'Retake',
            onTap: onRetake,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Brand.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Brand.outline),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 68,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTheme(
                    data: const IconThemeData(color: Brand.blue, size: 22),
                    child: icon,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Brand.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetStrip extends StatelessWidget {
  const _PresetStrip({required this.page, required this.onSelect});

  final _PageEdit page;
  final ValueChanged<_EnhancePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          for (final preset in _EnhancePreset.values)
            _PresetThumb(
              preset: preset,
              selected: page.preset == preset,
              page: page,
              onTap: () => onSelect(preset),
            ),
        ],
      ),
    );
  }
}

class _PresetThumb extends StatelessWidget {
  const _PresetThumb({
    required this.preset,
    required this.selected,
    required this.page,
    required this.onTap,
  });

  final _EnhancePreset preset;
  final bool selected;
  final _PageEdit page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? Brand.blue
                          : Brand.ink.withValues(alpha: 0.12),
                      width: selected ? 3 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: ColoredBox(
                      color: const Color(0xFFF4F6FB),
                      child: FutureBuilder<Uint8List>(
                        future: page.thumbFor(preset),
                        builder: (context, snap) {
                          final bytes = snap.data ?? page.previewBytes;
                          final desaturate =
                              snap.data == null &&
                              (preset == _EnhancePreset.bw ||
                                  preset == _EnhancePreset.grayscale);
                          return Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            gaplessPlayback: true,
                            color: desaturate ? Colors.grey : null,
                            colorBlendMode: desaturate
                                ? BlendMode.saturation
                                : null,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Brand.blue : Brand.grey,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveDocumentButton extends StatelessWidget {
  const _SaveDocumentButton({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: saving ? null : onSave,
          style: FilledButton.styleFrom(
            backgroundColor: Brand.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Brand.blue.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: BrandType.button.copyWith(fontSize: 17),
          ),
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Document'),
        ),
      ),
    );
  }
}

class _VennIcon extends StatelessWidget {
  const _VennIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Brand.blue;
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: _VennPainter(color)),
    );
  }
}

class _VennPainter extends CustomPainter {
  _VennPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final r = size.shortestSide * 0.28;
    canvas.drawCircle(Offset(size.width * 0.38, size.height * 0.58), r, paint);
    canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.58), r, paint);
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.38), r, paint);
  }

  @override
  bool shouldRepaint(covariant _VennPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: BrandType.caption.copyWith(
                color: Brand.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(2),
              style: BrandType.caption.copyWith(color: Brand.grey),
            ),
          ],
        ),
        Slider(
          value: value.clamp(-1, 1),
          min: -1,
          max: 1,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

bool _isPng(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;
