import 'dart:ui';
import 'package:scan2/features/camera/domain/quad_detector.dart';

class PerspectiveTransformer {
  /// Placeholder warp — returns the input unchanged in demo mode.
  Future<List<int>> warp({
    required List<int> imageBytes,
    required Quad quad,
    required Size imageSize,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return imageBytes;
  }
}
