import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A document quad detected on a grayscale grid, with corners in normalized
/// (0–1) grid coordinates ordered TL, TR, BR, BL.
class QuadDetection {
  const QuadDetection({required this.corners, required this.confidence});

  final List<Offset> corners;
  final double confidence;
}

/// Pure-Dart document boundary detector (no ML / OpenCV dependency).
///
/// Primary strategy — the one real scanners use — is line-based:
///  1. 3×3 box blur, then Sobel gradients.
///  2. Strong gradient pixels vote in a Hough space for near-vertical and
///     near-horizontal lines (document edges up to ~30° of tilt).
///  3. The best well-separated left/right and top/bottom line pairs are
///     intersected into the document quad.
/// This stays reliable on textured desks, partial contrast, and documents
/// that fill most of the frame — cases where region-based segmentation fails.
///
/// A contrast-blob fallback (largest connected component + extreme corners)
/// covers soft-edged documents on plain backgrounds when no line quad is
/// found.
class DocumentQuadDetector {
  const DocumentQuadDetector();

  /// Minimum fraction of the frame a document must cover to count.
  static const _minAreaRatio = 0.06;

  /// Hough slope range (± tan 31°) for "near-axis" document edges.
  static const _maxSlope = 0.6;
  static const _slopeBins = 21;

  /// Detects the dominant document quad in a grayscale [lum] grid of
  /// [width]×[height]. Returns null when nothing document-like is found.
  QuadDetection? detect(Uint8List lum, int width, int height) {
    if (width < 16 || height < 16 || lum.length < width * height) return null;

    final blurred = _boxBlur3(lum, width, height);

    final lineResult = _detectByLines(blurred, width, height);
    if (lineResult != null) return lineResult;

    return _detectByBlob(blurred, width, height);
  }

  /// Orders 4 points as TL, TR, BR, BL using the sum/diff heuristic.
  static List<Offset> orderCorners(List<Offset> pts) {
    assert(pts.length == 4);
    Offset pick(double Function(Offset) score, bool minimum) {
      var best = pts.first;
      for (final p in pts.skip(1)) {
        final better = minimum ? score(p) < score(best) : score(p) > score(best);
        if (better) best = p;
      }
      return best;
    }

    final tl = pick((p) => p.dx + p.dy, true);
    final br = pick((p) => p.dx + p.dy, false);
    final tr = pick((p) => p.dx - p.dy, false);
    final bl = pick((p) => p.dx - p.dy, true);
    return [tl, tr, br, bl];
  }

  // ---------------------------------------------------------------------
  // Line-based detection (primary)
  // ---------------------------------------------------------------------

  QuadDetection? _detectByLines(Uint8List lum, int w, int h) {
    // Sobel gradients.
    final gx = Int16List(w * h);
    final gy = Int16List(w * h);
    var magSum = 0;
    var magCount = 0;
    for (var y = 1; y < h - 1; y++) {
      final r0 = (y - 1) * w;
      final r1 = y * w;
      final r2 = (y + 1) * w;
      for (var x = 1; x < w - 1; x++) {
        final a = lum[r0 + x - 1], b = lum[r0 + x], c = lum[r0 + x + 1];
        final d = lum[r1 + x - 1], f = lum[r1 + x + 1];
        final g = lum[r2 + x - 1], hh = lum[r2 + x], i = lum[r2 + x + 1];
        final sx = (c + 2 * f + i) - (a + 2 * d + g);
        final sy = (g + 2 * hh + i) - (a + 2 * b + c);
        gx[r1 + x] = sx;
        gy[r1 + x] = sy;
        magSum += sx.abs() + sy.abs();
        magCount++;
      }
    }
    if (magCount == 0) return null;
    final meanMag = magSum / magCount;
    final threshold = math.max(60.0, meanMag * 2.6);

    // Hough accumulators. Near-vertical lines: x = a*y + b.
    // Near-horizontal lines: y = c*x + d.
    final bOffset = (_maxSlope * h).ceil();
    final bCount = w + 2 * bOffset;
    final dOffset = (_maxSlope * w).ceil();
    final dCount = h + 2 * dOffset;
    final accV = Int32List(_slopeBins * bCount);
    final accH = Int32List(_slopeBins * dCount);

    for (var y = 1; y < h - 1; y++) {
      final row = y * w;
      for (var x = 1; x < w - 1; x++) {
        final sx = gx[row + x];
        final sy = gy[row + x];
        final mag = sx.abs() + sy.abs();
        if (mag < threshold) continue;

        if (sx.abs() >= sy.abs()) {
          // Vertical-ish edge (strong horizontal gradient).
          for (var s = 0; s < _slopeBins; s++) {
            final a = -_maxSlope + s * (2 * _maxSlope / (_slopeBins - 1));
            final b = (x - a * y + bOffset).round();
            if (b >= 0 && b < bCount) accV[s * bCount + b]++;
          }
        } else {
          for (var s = 0; s < _slopeBins; s++) {
            final c = -_maxSlope + s * (2 * _maxSlope / (_slopeBins - 1));
            final d = (y - c * x + dOffset).round();
            if (d >= 0 && d < dCount) accH[s * dCount + d]++;
          }
        }
      }
    }

    final vLines = _topLines(
      accV,
      bCount,
      offset: bOffset,
      minVotes: math.max(8, (0.22 * h).round()),
    );
    final hLines = _topLines(
      accH,
      dCount,
      offset: dOffset,
      minVotes: math.max(8, (0.22 * w).round()),
    );
    if (vLines.length < 2 || hLines.length < 2) return null;

    // Pick the strongest pair with real separation (a document has two
    // distinct edges, not one edge counted twice).
    final vPair = _bestPair(vLines, midSpan: h, separation: 0.30 * w);
    final hPair = _bestPair(hLines, midSpan: w, separation: 0.30 * h);
    if (vPair == null || hPair == null) return null;

    final (left, right) = vPair;
    final (top, bottom) = hPair;

    final corners = <Offset>[];
    for (final v in [left, right]) {
      for (final hLine in [top, bottom]) {
        final p = _intersect(v, hLine);
        if (p == null) return null;
        corners.add(p);
      }
    }

    // Reject corners far outside the frame or degenerate quads.
    for (final p in corners) {
      if (p.dx < -0.2 * w || p.dx > 1.2 * w) return null;
      if (p.dy < -0.2 * h || p.dy > 1.2 * h) return null;
    }
    final ordered = orderCorners(corners);
    if (!_isConvex(ordered)) return null;

    final areaRatio = _polygonArea(ordered) / (w * h);
    if (areaRatio < _minAreaRatio || areaRatio > 0.98) return null;

    // Support: how much of each edge's span is backed by votes.
    final supports = [
      left.votes / h,
      right.votes / h,
      top.votes / w,
      bottom.votes / w,
    ].map((s) => s.clamp(0.0, 1.0)).toList();
    final avg = supports.reduce((a, b) => a + b) / 4;
    final weakest = supports.reduce(math.min);

    final confidence =
        (0.28 + 0.50 * avg + 0.15 * weakest + 0.07 * math.min(areaRatio * 2, 1))
            .clamp(0.0, 0.97);

    return QuadDetection(
      corners: ordered
          .map((p) => Offset(
                (p.dx / w).clamp(0.0, 1.0),
                (p.dy / h).clamp(0.0, 1.0),
              ))
          .toList(growable: false),
      confidence: confidence,
    );
  }

  /// Extracts up to 6 distinct peaks from a Hough accumulator.
  List<_HoughLine> _topLines(
    Int32List acc,
    int interceptCount, {
    required int offset,
    required int minVotes,
  }) {
    final lines = <_HoughLine>[];
    final working = Int32List.fromList(acc);

    int smoothed(int s, int b) {
      var v = working[s * interceptCount + b];
      if (b > 0) v += working[s * interceptCount + b - 1];
      if (b < interceptCount - 1) v += working[s * interceptCount + b + 1];
      return v;
    }

    for (var n = 0; n < 6; n++) {
      var bestVotes = 0;
      var bestS = -1;
      var bestB = -1;
      for (var s = 0; s < _slopeBins; s++) {
        for (var b = 1; b < interceptCount - 1; b++) {
          final v = smoothed(s, b);
          if (v > bestVotes) {
            bestVotes = v;
            bestS = s;
            bestB = b;
          }
        }
      }
      if (bestVotes < minVotes) break;

      lines.add(_HoughLine(
        slope: -_maxSlope + bestS * (2 * _maxSlope / (_slopeBins - 1)),
        intercept: (bestB - offset).toDouble(),
        votes: bestVotes,
      ));

      // Suppress the ridge around this peak so the next pick is a
      // genuinely different edge.
      for (var s = math.max(0, bestS - 3);
          s <= math.min(_slopeBins - 1, bestS + 3);
          s++) {
        for (var b = math.max(0, bestB - 8);
            b <= math.min(interceptCount - 1, bestB + 8);
            b++) {
          working[s * interceptCount + b] = 0;
        }
      }
    }
    return lines;
  }

  /// Best-voted pair of lines whose positions at mid-span differ by at least
  /// [separation]. Returns (nearer, farther) by mid-span position.
  (_HoughLine, _HoughLine)? _bestPair(
    List<_HoughLine> lines, {
    required int midSpan,
    required double separation,
  }) {
    (_HoughLine, _HoughLine)? best;
    var bestScore = 0;
    for (var i = 0; i < lines.length; i++) {
      for (var j = i + 1; j < lines.length; j++) {
        final pi = lines[i].positionAt(midSpan / 2);
        final pj = lines[j].positionAt(midSpan / 2);
        if ((pi - pj).abs() < separation) continue;
        // Document edges are roughly parallel.
        if ((lines[i].slope - lines[j].slope).abs() > 0.45) continue;
        final score = lines[i].votes + lines[j].votes;
        if (score > bestScore) {
          bestScore = score;
          best = pi < pj ? (lines[i], lines[j]) : (lines[j], lines[i]);
        }
      }
    }
    return best;
  }

  /// Intersection of a near-vertical line (x = a·y + b) with a
  /// near-horizontal line (y = c·x + d).
  Offset? _intersect(_HoughLine vertical, _HoughLine horizontal) {
    final a = vertical.slope, b = vertical.intercept;
    final c = horizontal.slope, d = horizontal.intercept;
    final denom = 1 - a * c;
    if (denom.abs() < 1e-6) return null;
    final x = (a * d + b) / denom;
    final y = c * x + d;
    return Offset(x, y);
  }

  // ---------------------------------------------------------------------
  // Contrast-blob detection (fallback)
  // ---------------------------------------------------------------------

  QuadDetection? _detectByBlob(Uint8List blurred, int width, int height) {
    final (bg, bgSpread) = _borderStats(blurred, width, height);
    final threshold = math.max(14.0, bgSpread * 2.2 + 6);

    final mask = Uint8List(width * height);
    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        if ((blurred[row + x] - bg).abs() > threshold) {
          mask[row + x] = 1;
        }
      }
    }

    final component = _largestComponent(mask, width, height);
    if (component == null) return null;

    final areaRatio = component.area / (width * height);
    if (areaRatio < _minAreaRatio) return null;

    final corners = _extremeCorners(component, width);
    if (corners == null) return null;

    if (!_isConvex(corners)) return null;

    final quadArea = _polygonArea(corners);
    final quadAreaRatio = quadArea / (width * height);
    if (quadAreaRatio < _minAreaRatio) return null;

    final solidity = (component.area / math.max(quadArea, 1)).clamp(0.0, 1.0);
    if (solidity < 0.55) return null;

    final edgeSupport = _edgeSupport(blurred, width, height, corners);

    final confidence = (0.25 +
            0.40 * edgeSupport +
            0.20 * solidity +
            0.10 * math.min(quadAreaRatio * 2.5, 1.0))
        .clamp(0.0, 0.90);

    final normalized = corners
        .map((c) => Offset(
              (c.dx / width).clamp(0.0, 1.0),
              (c.dy / height).clamp(0.0, 1.0),
            ))
        .toList(growable: false);

    return QuadDetection(
      corners: orderCorners(normalized),
      confidence: confidence,
    );
  }

  Uint8List _boxBlur3(Uint8List src, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - 1) * w;
      final y1 = y * w;
      final y2 = math.min(h - 1, y + 1) * w;
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - 1);
        final x2 = math.min(w - 1, x + 1);
        final sum = src[y0 + x0] + src[y0 + x] + src[y0 + x2] +
            src[y1 + x0] + src[y1 + x] + src[y1 + x2] +
            src[y2 + x0] + src[y2 + x] + src[y2 + x2];
        out[y1 + x] = sum ~/ 9;
      }
    }
    return out;
  }

  /// Mean and mean-absolute-deviation of the 2px border ring.
  (double, double) _borderStats(Uint8List lum, int w, int h) {
    var sum = 0.0;
    var count = 0;
    void sample(int x, int y) {
      sum += lum[y * w + x];
      count++;
    }

    for (var t = 0; t < 2; t++) {
      for (var x = 0; x < w; x++) {
        sample(x, t);
        sample(x, h - 1 - t);
      }
      for (var y = 2; y < h - 2; y++) {
        sample(t, y);
        sample(w - 1 - t, y);
      }
    }
    final mean = count == 0 ? 128.0 : sum / count;

    var dev = 0.0;
    for (var t = 0; t < 2; t++) {
      for (var x = 0; x < w; x++) {
        dev += (lum[t * w + x] - mean).abs();
        dev += (lum[(h - 1 - t) * w + x] - mean).abs();
      }
      for (var y = 2; y < h - 2; y++) {
        dev += (lum[y * w + t] - mean).abs();
        dev += (lum[y * w + w - 1 - t] - mean).abs();
      }
    }
    return (mean, count == 0 ? 0 : dev / count);
  }

  _Component? _largestComponent(Uint8List mask, int w, int h) {
    final labels = Int32List(w * h); // 0 = unvisited
    var nextLabel = 0;
    _Component? best;
    final stack = <int>[];

    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || labels[i] != 0) continue;
      nextLabel++;
      var area = 0;
      final pixels = <int>[];
      stack.add(i);
      labels[i] = nextLabel;

      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        area++;
        pixels.add(p);
        final px = p % w;
        final py = p ~/ w;
        // 4-connectivity is enough at grid resolution and keeps this fast.
        if (px > 0) _tryPush(p - 1, mask, labels, nextLabel, stack);
        if (px < w - 1) _tryPush(p + 1, mask, labels, nextLabel, stack);
        if (py > 0) _tryPush(p - w, mask, labels, nextLabel, stack);
        if (py < h - 1) _tryPush(p + w, mask, labels, nextLabel, stack);
      }

      if (best == null || area > best.area) {
        best = _Component(area: area, pixels: pixels);
      }
    }
    return best;
  }

  void _tryPush(
    int index,
    Uint8List mask,
    Int32List labels,
    int label,
    List<int> stack,
  ) {
    if (mask[index] != 0 && labels[index] == 0) {
      labels[index] = label;
      stack.add(index);
    }
  }

  List<Offset>? _extremeCorners(_Component component, int w) {
    if (component.pixels.length < 12) return null;

    var tl = component.pixels.first;
    var tr = tl, br = tl, bl = tl;
    var tlScore = double.infinity, brScore = -double.infinity;
    var trScore = -double.infinity, blScore = double.infinity;

    for (final p in component.pixels) {
      final x = (p % w).toDouble();
      final y = (p ~/ w).toDouble();
      final sum = x + y;
      final diff = x - y;
      if (sum < tlScore) {
        tlScore = sum;
        tl = p;
      }
      if (sum > brScore) {
        brScore = sum;
        br = p;
      }
      if (diff > trScore) {
        trScore = diff;
        tr = p;
      }
      if (diff < blScore) {
        blScore = diff;
        bl = p;
      }
    }

    Offset toOffset(int p) => Offset((p % w).toDouble(), (p ~/ w).toDouble());
    final corners = [toOffset(tl), toOffset(tr), toOffset(br), toOffset(bl)];

    // Degenerate quads (all corners bunched together) are noise.
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      if ((a - b).distance < 4) return null;
    }
    return corners;
  }

  bool _isConvex(List<Offset> quad) {
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final c = cross(quad[i], quad[(i + 1) % 4], quad[(i + 2) % 4]);
      if (c.abs() < 1e-6) continue;
      final s = c > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return sign != 0;
  }

  double _polygonArea(List<Offset> quad) {
    var area = 0.0;
    for (var i = 0; i < quad.length; i++) {
      final a = quad[i];
      final b = quad[(i + 1) % quad.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return area.abs() / 2;
  }

  /// Fraction of samples along the quad perimeter that sit on a strong
  /// luminance gradient (a real paper edge).
  double _edgeSupport(
    Uint8List lum,
    int w,
    int h,
    List<Offset> corners,
  ) {
    var supported = 0;
    var total = 0;

    double lumAt(double x, double y) {
      final xi = x.round().clamp(0, w - 1);
      final yi = y.round().clamp(0, h - 1);
      return lum[yi * w + xi].toDouble();
    }

    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final edge = b - a;
      final len = edge.distance;
      if (len < 1) continue;
      // Unit normal to the edge — we compare luminance on both sides.
      final normal = Offset(-edge.dy / len, edge.dx / len);
      final steps = math.max(6, len ~/ 3);
      for (var s = 1; s < steps; s++) {
        final t = s / steps;
        final p = a + edge * t;
        final inside = lumAt(p.dx + normal.dx * 2, p.dy + normal.dy * 2);
        final outside = lumAt(p.dx - normal.dx * 2, p.dy - normal.dy * 2);
        total++;
        if ((inside - outside).abs() > 10) supported++;
      }
    }
    return total == 0 ? 0 : supported / total;
  }
}

class _Component {
  const _Component({required this.area, required this.pixels});

  final int area;
  final List<int> pixels;
}

class _HoughLine {
  const _HoughLine({
    required this.slope,
    required this.intercept,
    required this.votes,
  });

  final double slope;
  final double intercept;
  final int votes;

  /// Line position (x for vertical family, y for horizontal) at [t] along
  /// the perpendicular span.
  double positionAt(double t) => slope * t + intercept;
}
