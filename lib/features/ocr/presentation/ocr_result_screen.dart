import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/library/data/document_store.dart';
import 'package:scan2/features/ocr/domain/ocr_args.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:scan2/features/shared/providers/db_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows extracted text beside the page it came from.
class OcrResultScreen extends ConsumerStatefulWidget {
  const OcrResultScreen({super.key, required this.args});

  final OcrArgs args;

  @override
  ConsumerState<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends ConsumerState<OcrResultScreen> {
  late final List<TextEditingController> _controllers;
  int _index = 0;
  bool _saving = false;

  OcrPageResult get _current => widget.args.pages[_index];

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final page in widget.args.pages)
        TextEditingController(text: page.text),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _text => _controllers[_index].text;

  Future<void> _copy() async {
    final text = _text.trim();
    if (text.isEmpty) {
      _toast('No text to copy on this page.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('Copied to clipboard');
  }

  Future<void> _share() async {
    final text = _text.trim();
    if (text.isEmpty) {
      _toast('No text to share on this page.');
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(80, 120, 48, 48)
        : box.localToGlobal(Offset.zero) & box.size;
    await Share.share(
      text,
      sharePositionOrigin: origin.width < 1 || origin.height < 1
          ? const Rect.fromLTWH(80, 120, 48, 48)
          : origin,
    );
  }

  Future<void> _saveScan() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      goToScanResult(
        context,
        [for (final page in widget.args.pages) page.page],
        allowRetake: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not open the scan: $e');
    }
  }

  Future<void> _saveTextDocument() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(documentRepositoryProvider);
      if (repository is! DocumentStore) {
        if (mounted) context.go('/library');
        return;
      }
      final doc = await repository.createProcessedDocument(
        pages: [for (final page in widget.args.pages) page.page],
        title: 'OCR text',
      );
      bumpLibrary(ref);
      if (!mounted) return;
      context.go('/library/document/${doc.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.args.pages.length;
    final empty = _text.trim().isEmpty;

    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/library');
                        }
                      },
                      icon: const Icon(Icons.chevron_left_rounded, size: 32),
                      color: Brand.blue,
                    ),
                    const Expanded(
                      child: Text(
                        'OCR Text',
                        textAlign: TextAlign.center,
                        style: BrandType.title,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded),
                      color: Brand.blue,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SizedBox(
                    width: double.infinity,
                    height: 180,
                    child: ColoredBox(
                      color: Brand.surface,
                      child: Image.memory(
                        _current.page.bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (count > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _index == 0
                          ? null
                          : () => setState(() => _index--),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      'Page ${_index + 1} of $count',
                      style: BrandType.caption,
                    ),
                    IconButton(
                      onPressed: _index >= count - 1
                          ? null
                          : () => setState(() => _index++),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Brand.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Brand.outline),
                  ),
                  child: TextField(
                    controller: _controllers[_index],
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: BrandType.body,
                    decoration: InputDecoration(
                      hintText: empty
                          ? 'No text found on this page. Try a sharper photo '
                                'of the document.'
                          : null,
                      hintMaxLines: 4,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share text'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _saveScan,
                          child: const Text('Edit scan'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _saveTextDocument,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
