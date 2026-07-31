enum ScanFilter {
  original,
  magic,
  bw,
  grayscale,
  enhance,
}

class ImageProcessor {
  /// Applies a lightweight demo filter description; real pixel work is on-device.
  Future<List<int>> applyFilter({
    required List<int> imageBytes,
    required ScanFilter filter,
    double brightness = 0,
    double contrast = 0,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return imageBytes;
  }

  static String labelFor(ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.magic:
        return 'Magic';
      case ScanFilter.bw:
        return 'B&W';
      case ScanFilter.grayscale:
        return 'Gray';
      case ScanFilter.enhance:
        return 'Enhance';
    }
  }
}
