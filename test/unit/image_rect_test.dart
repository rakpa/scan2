import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/core/imaging/raster_image.dart';

void main() {
  group('containedImageRect', () {
    // The crop handles are positioned against this rectangle. When it was
    // assumed to be the whole container, every handle sat off the page and
    // saving cropped the wrong region.
    test('letterboxes a landscape image in a portrait container', () {
      final rect = containedImageRect(
        const Size(400, 800),
        const Size(1000, 500),
      );
      expect(rect.width, 400);
      expect(rect.height, 200);
      expect(rect.left, 0);
      expect(rect.top, 300, reason: 'centred vertically');
    });

    test('pillarboxes a portrait image in a landscape container', () {
      final rect = containedImageRect(
        const Size(800, 400),
        const Size(500, 1000),
      );
      expect(rect.width, 200);
      expect(rect.height, 400);
      expect(rect.top, 0);
      expect(rect.left, 300);
    });

    test('fills exactly when aspect ratios match', () {
      final rect = containedImageRect(
        const Size(300, 600),
        const Size(1000, 2000),
      );
      expect(rect, const Rect.fromLTWH(0, 0, 300, 600));
    });

    test('a normalized corner maps onto the image, not the container', () {
      const container = Size(400, 800);
      final rect = containedImageRect(container, const Size(1000, 500));

      // The document's bottom-right corner.
      final mapped = Offset(
        rect.left + 1.0 * rect.width,
        rect.top + 1.0 * rect.height,
      );
      expect(mapped, const Offset(400, 500));
      // Mapping against the container would have put it at (400, 800) —
      // 300px below the image.
      expect(mapped.dy, isNot(container.height));
    });

    test('degenerate sizes fall back to the container', () {
      final rect = containedImageRect(const Size(100, 100), Size.zero);
      expect(rect, const Rect.fromLTWH(0, 0, 100, 100));
    });
  });
}
