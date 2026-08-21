import 'package:scan2/features/library/data/document_store.dart';

/// One page of an OCR session: the image that was read, and the text on it.
class OcrPageResult {
  const OcrPageResult({
    required this.page,
    required this.text,
  });

  final ProcessedPage page;
  final String text;
}

class OcrArgs {
  const OcrArgs({required this.pages}) : assert(pages.length > 0);

  final List<OcrPageResult> pages;
}
