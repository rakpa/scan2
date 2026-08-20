/// Capture target selected on the camera scanner.
enum ScanMode { idCard, document, book, whiteboard }

extension ScanModeX on ScanMode {
  String get label => switch (this) {
    ScanMode.idCard => 'ID Card',
    ScanMode.document => 'Document',
    ScanMode.book => 'Book',
    ScanMode.whiteboard => 'Whiteboard',
  };

  /// Smallest page area (fraction of the frame) that may auto-capture.
  double get minAutoCaptureArea => switch (this) {
    ScanMode.idCard => 0.04,
    ScanMode.document => 0.12,
    ScanMode.book => 0.16,
    ScanMode.whiteboard => 0.10,
  };
}
