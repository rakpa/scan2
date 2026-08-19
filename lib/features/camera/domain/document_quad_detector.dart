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
/// The strategy is line-based, as in most production scanners:
///  1. 3×3 box blur, then Sobel gradients.
///  2. Strong gradient pixels vote in a Hough space for near-vertical and
///     near-horizontal lines (document edges up to ~30° of tilt).
///  3. Candidate quads are built from those lines and *scored*, and the best
///     scoring quad wins.
///
/// Step 3 is the part that matters. Choosing the highest-voted line pair —
/// the obvious approach — reliably picks printed text lines instead of the
/// page border: body text is high-contrast, dead straight, and there is a lot
/// of it, so it outvotes the paper edge. Two things prevent that here:
///
///  * **Polarity.** Votes are split by gradient sign, so the left edge of a
///    light page (dark→light going right) lands in a different accumulator
///    than its right edge. A text line produces both signs a few pixels
///    apart and cannot supply a consistent left/right pair.
///  * **Verification.** Every candidate quad is scored on whether real
///    luminance steps of the *expected* direction exist along its perimeter,
///    not on how many gradient pixels voted for its lines.
///
/// A contrast-blob fallback (largest connected component + extreme corners)
/// covers soft-edged documents on plain backgrounds when no line quad scores.
class DocumentQuadDetector {
  const DocumentQuadDetector();

  /// Minimum fraction of the frame a document must cover to count.
  ///
  /// Deliberately low. A hotel key card or a receipt held at arm's length
  /// covers about 5% of the frame, and a 10% floor rejected those outright —
  /// the guides simply never appeared. False positives are held off by the
  /// polarity and edge-support scoring instead of by a size floor.
  static const _minAreaRatio = 0.030;

  /// Minimum extent of a document along each axis, as a fraction of the
  /// frame. A card in landscape is short in one axis; requiring a quarter of
  /// the frame in *both* threw those away before scoring.
  static const _minExtentRatio = 0.11;

  /// Gradient thresholds tried in order, as fractions of the scene's
  /// strong-edge level. Strict first.
  static const _thresholdFractions = [0.30, 0.12, 0.05];

  /// Score at which a pass is accepted without trying more permissive ones.
  static const _confidentEnough = 0.74;

  /// Luminance step below which a border sample is treated as noise, and the
  /// step at which it counts as a fully supported border.
  static const _noiseFloor = 3.0;
  static const _fullStep = 14.0;

  /// Hough slope range (± tan 31°) for "near-axis" document edges.
  static const _maxSlope = 0.6;
  static const _slopeBins = 21;

  /// Candidate lines taken from each polarity accumulator.
  ///
  /// Hough votes scale with line length, so a wood grain or table edge running
  /// the full frame outvotes the short border of a card lying on it. Taking
  /// only the top few peaks therefore drops the document's own edges before
  /// scoring ever sees them. Taking more costs little: the vast majority of
  /// combinations fail the cheap extent and convexity checks long before the
  /// expensive edge-support sampling.
  static const _linesPerSide = 8;

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
        final better = minimum
            ? score(p) < score(best)
            : score(p) > score(best);
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
    final gx = Int16List(w * h);
    final gy = Int16List(w * h);
    // Magnitudes bucketed by 4 (max |sx|+|sy| is 2040) to pick a percentile
    // without keeping the full magnitude array around.
    final magHistogram = Int32List(512);
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
        magHistogram[math.min(511, (sx.abs() + sy.abs()) >> 2)]++;
        magCount++;
      }
    }
    if (magCount == 0) return null;

    // Threshold relative to the scene's own strongest edges, not to a fixed
    // value and not to a fixed share of pixels.
    //
    // A fixed threshold cannot serve both a black folder on a white desk and a
    // white page on a light one. But letting a fixed *share* of pixels vote is
    // worse on a textured surface: wood grain is weak yet covers the frame, so
    // a generous share fills the accumulators with full-length grain lines
    // that outvote the short borders of a card lying on the wood — the card's
    // own edges never even become candidates.
    //
    // Measuring the strong-edge level and thresholding relative to it keeps
    // real borders at any contrast while dropping texture that is an order of
    // magnitude weaker than the dominant edges.
    final strongTarget = math.max(1, (magCount * 0.02).round());
    var strongLevel = 0.0;
    var running = 0;
    for (var bucket = 511; bucket >= 0; bucket--) {
      running += magHistogram[bucket];
      if (running >= strongTarget) {
        strongLevel = (bucket << 2).toDouble();
        break;
      }
    }
    // A single gradient threshold cannot serve every scene, and this is not a
    // tuning failure — the requirements are opposed. Excluding wood grain or
    // fabric weave needs a HIGH cut-off; catching a pale page on a pale desk
    // needs a LOW one. When the strongest edges in frame are the printed text
    // *inside* the page, no single value does both.
    //
    // So try several, strict first, and keep the best-scoring quad. The strict
    // pass answers most scenes and returns immediately, so the extra passes
    // are only paid for on the hard frames that need them.
    QuadDetection? best;
    for (final fraction in _thresholdFractions) {
      final threshold = math.max(20.0, strongLevel * fraction);
      final candidate = _detectAtThreshold(lum, gx, gy, w, h, threshold);
      if (candidate == null) continue;
      if (best == null || candidate.confidence > best.confidence) {
        best = candidate;
      }
      // Good enough that a more permissive pass will not beat it.
      if (candidate.confidence >= _confidentEnough) return candidate;
    }
    return best;
  }

  /// One Hough pass at a fixed gradient [threshold].
  QuadDetection? _detectAtThreshold(
    Uint8List lum,
    Int16List gx,
    Int16List gy,
    int w,
    int h,
    double threshold,
  ) {
    // Four accumulators: near-vertical lines (x = a·y + b) and near-horizontal
    // lines (y = c·x + d), each split by the sign of the crossing gradient.
    final bOffset = (_maxSlope * h).ceil();
    final bCount = w + 2 * bOffset;
    final dOffset = (_maxSlope * w).ceil();
    final dCount = h + 2 * dOffset;
    final accVPos = Int32List(_slopeBins * bCount);
    final accVNeg = Int32List(_slopeBins * bCount);
    final accHPos = Int32List(_slopeBins * dCount);
    final accHNeg = Int32List(_slopeBins * dCount);

    final slopeStep = 2 * _maxSlope / (_slopeBins - 1);
    for (var y = 1; y < h - 1; y++) {
      final row = y * w;
      for (var x = 1; x < w - 1; x++) {
        final sx = gx[row + x];
        final sy = gy[row + x];
        final mag = sx.abs() + sy.abs();
        if (mag < threshold) continue;

        if (sx.abs() >= sy.abs()) {
          final acc = sx > 0 ? accVPos : accVNeg;
          for (var s = 0; s < _slopeBins; s++) {
            final a = -_maxSlope + s * slopeStep;
            final b = (x - a * y + bOffset).round();
            if (b >= 0 && b < bCount) acc[s * bCount + b]++;
          }
        } else {
          final acc = sy > 0 ? accHPos : accHNeg;
          for (var s = 0; s < _slopeBins; s++) {
            final c = -_maxSlope + s * slopeStep;
            final d = (y - c * x + dOffset).round();
            if (d >= 0 && d < dCount) acc[s * dCount + d]++;
          }
        }
      }
    }

    // A small document's border is only as long as the document, so the vote
    // floor has to sit under _minExtentRatio or its edges never become
    // candidate lines at all.
    final minVotesV = math.max(5, (_minExtentRatio * 0.7 * h).round());
    final minVotesH = math.max(5, (_minExtentRatio * 0.7 * w).round());
    final vPos = _topLines(
      accVPos,
      bCount,
      offset: bOffset,
      minVotes: minVotesV,
    );
    final vNeg = _topLines(
      accVNeg,
      bCount,
      offset: bOffset,
      minVotes: minVotesV,
    );
    final hPos = _topLines(
      accHPos,
      dCount,
      offset: dOffset,
      minVotes: minVotesH,
    );
    final hNeg = _topLines(
      accHNeg,
      dCount,
      offset: dOffset,
      minVotes: minVotesH,
    );

    // Hypothesis A: page brighter than its surroundings — the left/top borders
    // are rising edges, the right/bottom borders falling. Hypothesis B is a
    // dark page on a light surface, where every sign flips.
    final best =
        _bestCandidate(lum, w, h, vPos, vNeg, hPos, hNeg, true) ??
        _bestCandidate(lum, w, h, vNeg, vPos, hNeg, hPos, false);
    return best;
  }

  /// Searches (left × right × top × bottom) line combinations and returns the
  /// best-scoring valid quad, or null if none passes.
  QuadDetection? _bestCandidate(
    Uint8List lum,
    int w,
    int h,
    List<_HoughLine> leftLines,
    List<_HoughLine> rightLines,
    List<_HoughLine> topLines,
    List<_HoughLine> bottomLines,
    bool pageIsBright,
  ) {
    if (leftLines.isEmpty ||
        rightLines.isEmpty ||
        topLines.isEmpty ||
        bottomLines.isEmpty) {
      return null;
    }

    QuadDetection? best;
    var bestScore = 0.0;

    for (final left in leftLines) {
      for (final right in rightLines) {
        // A page is at least this wide, and its sides do not cross.
        final lx = left.positionAt(h / 2);
        final rx = right.positionAt(h / 2);
        if (rx - lx < _minExtentRatio * w) continue;
        if ((left.slope - right.slope).abs() > 0.5) continue;

        for (final top in topLines) {
          for (final bottom in bottomLines) {
            final ty = top.positionAt(w / 2);
            final by = bottom.positionAt(w / 2);
            if (by - ty < _minExtentRatio * h) continue;
            if ((top.slope - bottom.slope).abs() > 0.5) continue;

            final corners = <Offset>[];
            var degenerate = false;
            for (final v in [left, right]) {
              for (final hLine in [top, bottom]) {
                final p = _intersect(v, hLine);
                if (p == null) {
                  degenerate = true;
                  break;
                }
                corners.add(p);
              }
              if (degenerate) break;
            }
            if (degenerate) continue;

            // Corners may sit slightly outside the frame when a page runs off
            // the edge, but not wildly so.
            var outOfFrame = false;
            for (final p in corners) {
              if (p.dx < -0.25 * w || p.dx > 1.25 * w) outOfFrame = true;
              if (p.dy < -0.25 * h || p.dy > 1.25 * h) outOfFrame = true;
            }
            if (outOfFrame) continue;

            final ordered = orderCorners(corners);
            if (!_isConvex(ordered)) continue;

            final areaRatio = _polygonArea(ordered) / (w * h);
            if (areaRatio < _minAreaRatio || areaRatio > 0.99) continue;

            final support = _signedEdgeSupport(
              lum,
              w,
              h,
              ordered,
              pageIsBright,
            );
            if (support.consistency < 0.46) continue;

            // Prefer strong, consistent borders; break ties toward the larger
            // quad, because the page always encloses whatever is printed on it.
            final score =
                support.consistency * 0.55 +
                math.min(support.contrast / 40, 1.0) * 0.25 +
                math.min(areaRatio * 1.6, 1.0) * 0.20;

            if (score > bestScore) {
              bestScore = score;
              best = QuadDetection(
                corners: ordered
                    .map(
                      (p) => Offset(
                        (p.dx / w).clamp(0.0, 1.0),
                        (p.dy / h).clamp(0.0, 1.0),
                      ),
                    )
                    .toList(growable: false),
                confidence: score.clamp(0.0, 0.98),
              );
            }
          }
        }
      }
    }

    if (best == null || bestScore < 0.45) return null;
    return best;
  }

  /// Extracts up to [_linesPerSide] distinct peaks from a Hough accumulator.
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

    for (var n = 0; n < _linesPerSide; n++) {
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

      lines.add(
        _HoughLine(
          slope: -_maxSlope + bestS * (2 * _maxSlope / (_slopeBins - 1)),
          intercept: (bestB - offset).toDouble(),
          votes: bestVotes,
        ),
      );

      // Suppress the ridge around this peak so the next pick is a
      // genuinely different edge.
      for (
        var s = math.max(0, bestS - 3);
        s <= math.min(_slopeBins - 1, bestS + 3);
        s++
      ) {
        for (
          var b = math.max(0, bestB - 8);
          b <= math.min(interceptCount - 1, bestB + 8);
          b++
        ) {
          working[s * interceptCount + b] = 0;
        }
      }
    }
    return lines;
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
    if (solidity < 0.62) return null;

    // The blob path has no polarity information, so accept whichever
    // orientation of the border step is the stronger.
    final bright = _signedEdgeSupport(blurred, width, height, corners, true);
    final dark = _signedEdgeSupport(blurred, width, height, corners, false);
    final support = bright.consistency >= dark.consistency ? bright : dark;
    if (support.consistency < 0.45) return null;

    final confidence =
        (0.15 +
                0.40 * support.consistency +
                0.25 * solidity +
                0.10 * math.min(quadAreaRatio * 2.5, 1.0))
            .clamp(0.0, 0.85);

    final normalized = corners
        .map(
          (c) => Offset(
            (c.dx / width).clamp(0.0, 1.0),
            (c.dy / height).clamp(0.0, 1.0),
          ),
        )
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
        final sum =
            src[y0 + x0] +
            src[y0 + x] +
            src[y0 + x2] +
            src[y1 + x0] +
            src[y1 + x] +
            src[y1 + x2] +
            src[y2 + x0] +
            src[y2 + x] +
            src[y2 + x2];
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

  /// Measures the luminance step across each edge of [corners], requiring the
  /// step to run in the direction a page border would.
  ///
  /// This is the check that separates a page border from a line of text: text
  /// has paper on *both* sides, so its "inside" and "outside" samples match.
  _EdgeSupport _signedEdgeSupport(
    Uint8List lum,
    int w,
    int h,
    List<Offset> corners,
    bool pageIsBright,
  ) {
    double lumAt(double x, double y) {
      final xi = x.round().clamp(0, w - 1);
      final yi = y.round().clamp(0, h - 1);
      return lum[yi * w + xi].toDouble();
    }

    // Sampling offset scales with the frame so it clears edge blur without
    // reaching into the next feature.
    final probe = math.max(2.0, math.min(w, h) * 0.02);

    final center = Offset(
      corners.map((c) => c.dx).reduce((a, b) => a + b) / 4,
      corners.map((c) => c.dy).reduce((a, b) => a + b) / 4,
    );

    var weakestEdge = 1.0;
    var supportSum = 0.0;
    var contrastSum = 0.0;
    var edgeCount = 0;
    var sampleCount = 0;

    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final edge = b - a;
      final len = edge.distance;
      if (len < 1) continue;

      var normal = Offset(-edge.dy / len, edge.dx / len);
      // Point the normal outward, away from the quad's centre.
      final mid = a + edge * 0.5;
      if ((mid + normal - center).distance < (mid - normal - center).distance) {
        normal = -normal;
      }

      final steps = math.max(8, len ~/ 3);
      var edgeSupport = 0.0;
      var edgeSamples = 0;

      // Skip the ends: corners are where two edges blur together.
      for (var s = 2; s < steps - 1; s++) {
        final t = s / steps;
        final p = a + edge * t;
        final inside = lumAt(
          p.dx - normal.dx * probe,
          p.dy - normal.dy * probe,
        );
        final outside = lumAt(
          p.dx + normal.dx * probe,
          p.dy + normal.dy * probe,
        );
        final diff = pageIsBright ? inside - outside : outside - inside;

        // Soft ramp rather than a hard cut. A page on a similarly toned desk
        // has a real but shallow border; a fixed cutoff scored it the same as
        // no border at all and the correct quad lost to a sliver of high
        // contrast elsewhere in the frame.
        final graded = diff <= _noiseFloor
            ? 0.0
            : math.min(1.0, (diff - _noiseFloor) / _fullStep);

        edgeSupport += graded;
        contrastSum += diff;
        edgeSamples++;
        sampleCount++;
      }

      if (edgeSamples == 0) continue;
      final normalized = edgeSupport / edgeSamples;
      weakestEdge = math.min(weakestEdge, normalized);
      supportSum += normalized;
      edgeCount++;
    }

    if (edgeCount == 0 || sampleCount == 0) {
      return const _EdgeSupport(consistency: 0, contrast: 0);
    }

    // Weighted toward the *weakest* border. A document is bounded on all four
    // sides; a quad that takes three real edges and runs its fourth off into
    // the background scores well on an average and is exactly the failure this
    // has to reject.
    final mean = supportSum / edgeCount;
    return _EdgeSupport(
      consistency: 0.35 * mean + 0.65 * weakestEdge,
      contrast: contrastSum / sampleCount,
    );
  }
}

class _EdgeSupport {
  const _EdgeSupport({required this.consistency, required this.contrast});

  /// Fraction of perimeter samples showing a step in the expected direction.
  final double consistency;

  /// Mean signed luminance step across the border.
  final double contrast;
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
