import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A page thumbnail, falling back to a drawn stand-in.
///
/// The fallback is a sketched page rather than a broken-image glyph: it keeps
/// the library looking like a shelf of documents when a file is still being
/// written, has gone missing, or when running the browser demo where there is
/// no file system at all.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({
    super.key,
    required this.path,
    this.cacheWidth,
    this.seed = 0,
    this.fit = BoxFit.cover,
  });

  final String? path;
  final int? cacheWidth;

  /// Varies the drawn stand-in so a grid of them does not look tiled.
  final int seed;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final file = path;
    if (file == null || kIsWeb) return _PagePlaceholder(seed: seed);

    return Image.file(
      File(file),
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _PagePlaceholder(seed: seed),
    );
  }
}

class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _PagePainter(
        seed: seed,
        paper: scheme.surface,
        ink: scheme.onSurfaceVariant.withValues(alpha: 0.30),
        accent: scheme.primary.withValues(alpha: 0.22),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter({
    required this.seed,
    required this.paper,
    required this.ink,
    required this.accent,
  });

  final int seed;
  final Color paper;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);

    final random = math.Random(seed * 7919 + 13);
    final margin = size.width * 0.14;
    final width = size.width - margin * 2;
    var y = size.height * 0.16;

    // A heading block, then body lines with ragged right edges.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, y, width * 0.55, size.height * 0.035),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );
    y += size.height * 0.09;

    final lineHeight = size.height * 0.020;
    final gap = size.height * 0.042;
    while (y < size.height * 0.86) {
      final lineWidth = width * (0.55 + random.nextDouble() * 0.45);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(margin, y, lineWidth, lineHeight),
          const Radius.circular(1.5),
        ),
        Paint()..color = ink,
      );
      y += gap;
    }
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) =>
      old.seed != seed || old.paper != paper || old.ink != ink;
}
