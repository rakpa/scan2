import 'package:flutter/foundation.dart';

/// How to open the home shell after leaving the scan-result or saved screens.
@immutable
class LibraryLaunch {
  const LibraryLaunch({this.tab = 0, this.highlightDocumentId});

  /// 0 = Home, 1 = Documents (Screen 12).
  final int tab;

  /// When set, the Documents tab highlights this newly saved scan.
  final int? highlightDocumentId;
}
