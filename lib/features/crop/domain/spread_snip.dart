import 'dart:ui' show Offset;

import 'package:scan2/core/imaging/raster.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';

/// One page taken from an open two-page spread.
class SpreadSnip {
  const SpreadSnip({required this.gutterX, required this.keepRight});

  /// Normalised x of the gutter, 0–1 across the spread.
  final double gutterX;

  /// True when the right-hand page is the one facing the camera.
  final bool keepRight;
}

/// Finds a book gutter and which page to keep.
///
/// A single sheet has no deep vertical valley, so this returns null and the
/// capture is left alone. An open book has a dark strip down the middle
/// (the fold, often a holder) with paper on both sides — that is a snip.
SpreadSnip? detectSpreadSnip(Raster source) {
  final small = source.downscaledTo(240);
  final w = small.width;
  final h = small.height;
  if (w < 40 || h < 40) return null;

  final luma = small.toLuma();
  final y0 = (h * 0.12).round();
  final y1 = (h * 0.88).round();
  final colH = y1 - y0;
  if (colH < 8) return null;

  final means = List<double>.filled(w, 0);
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var y = y0; y < y1; y++) {
      sum += luma[y * w + x];
    }
    means[x] = sum / colH;
  }

  const radius = 2;
  final smooth = List<double>.filled(w, 0);
  for (var x = 0; x < w; x++) {
    var s = 0.0;
    var n = 0;
    for (var i = x - radius; i <= x + radius; i++) {
      if (i < 0 || i >= w) continue;
      s += means[i];
      n++;
    }
    smooth[x] = s / n;
  }

  final search0 = (w * 0.22).round();
  final search1 = (w * 0.78).round();
  var minX = search0;
  var minV = smooth[search0];
  for (var x = search0; x <= search1; x++) {
    if (smooth[x] < minV) {
      minV = smooth[x];
      minX = x;
    }
  }

  final ranked = [...smooth]..sort();
  final paper = ranked[(ranked.length * 0.75).floor()];
  if (paper - minV < 32) return null;

  var left = minX;
  var right = minX;
  final darkCut = minV + 14;
  while (left > 1 && smooth[left - 1] <= darkCut) {
    left--;
  }
  while (right < w - 2 && smooth[right + 1] <= darkCut) {
    right++;
  }
  final valleyW = (right - left + 1) / w;
  if (valleyW < 0.012 || valleyW > 0.14) return null;

  double sideMean(int a, int b) {
    if (b <= a) return 0;
    var s = 0.0;
    for (var x = a; x < b; x++) {
      s += smooth[x];
    }
    return s / (b - a);
  }

  final leftMean = sideMean(0, left);
  final rightMean = sideMean(right + 1, w);
  // Both sides must be paper, not more background. One page is often
  // darker because it recedes from the camera.
  if (leftMean < minV + 28 || rightMean < minV + 28) return null;

  final leftShare = left / w;
  final rightShare = (w - 1 - right) / w;
  if (leftShare < 0.18 || rightShare < 0.18) return null;

  final keepRight = rightMean * rightShare >= leftMean * leftShare;
  return SpreadSnip(gutterX: (left + right) / 2 / w, keepRight: keepRight);
}

/// Cuts [outer] at [gutterX], keeping one page and stepping a little away
/// from the fold so a holder on the gutter is not part of the snip.
Quad splitQuadAtGutter(
  Quad outer,
  double gutterX, {
  required bool keepRight,
}) {
  final cut = keepRight
      ? (gutterX + 0.02).clamp(0.02, 0.95)
      : (gutterX - 0.02).clamp(0.05, 0.98);
  final top = Offset.lerp(outer.topLeft, outer.topRight, cut)!;
  final bottom = Offset.lerp(outer.bottomLeft, outer.bottomRight, cut)!;
  if (keepRight) {
    return Quad(
      topLeft: top,
      topRight: outer.topRight,
      bottomRight: outer.bottomRight,
      bottomLeft: bottom,
    );
  }
  return Quad(
    topLeft: outer.topLeft,
    topRight: top,
    bottomRight: bottom,
    bottomLeft: outer.bottomLeft,
  );
}
