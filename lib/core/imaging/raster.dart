import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A tightly packed 8-bit RGB raster.
///
/// All scan processing runs on this rather than on `package:image` filter
/// helpers: the math is explicit, allocation-free per pixel, and identical on
/// every platform, which matters because the same code path renders the crop
/// preview and the saved full-resolution page.
class Raster {
  Raster(this.width, this.height) : pixels = Uint8List(width * height * 3);

  Raster.fromPixels(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height * 3);

  final int width;
  final int height;
  final Uint8List pixels;

  int get length => width * height;

  /// Bulk channel copy. Going through [img.Image.getPixel] instead would
  /// allocate a Pixel per pixel — seconds of garbage on a 12MP frame.
  static Raster fromImage(img.Image image) {
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    return Raster.fromPixels(image.width, image.height, bytes);
  }

  img.Image toImage() {
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      bytesOffset: pixels.offsetInBytes,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );
  }

  Raster clone() =>
      Raster.fromPixels(width, height, Uint8List.fromList(pixels));

  /// Rec. 601 luma, the channel weighting scanners threshold on.
  Uint8List toLuma() {
    final out = Uint8List(length);
    var i = 0;
    for (var p = 0; p < out.length; p++) {
      out[p] = (pixels[i] * 77 + pixels[i + 1] * 150 + pixels[i + 2] * 29) >> 8;
      i += 3;
    }
    return out;
  }

  /// Longest-edge downscale with box averaging, used for preview rasters.
  Raster downscaledTo(int maxEdge) {
    final longest = math.max(width, height);
    if (longest <= maxEdge) return this;

    final scale = maxEdge / longest;
    final dw = math.max(1, (width * scale).round());
    final dh = math.max(1, (height * scale).round());
    final out = Raster(dw, dh);

    // Box filter: average every source pixel that maps into the target cell,
    // which avoids the aliasing a nearest-neighbour resize would leave on text.
    for (var y = 0; y < dh; y++) {
      final sy0 = (y * height / dh).floor();
      final sy1 = math.max(sy0 + 1, ((y + 1) * height / dh).floor());
      for (var x = 0; x < dw; x++) {
        final sx0 = (x * width / dw).floor();
        final sx1 = math.max(sx0 + 1, ((x + 1) * width / dw).floor());

        var r = 0, g = 0, b = 0, n = 0;
        for (var sy = sy0; sy < sy1 && sy < height; sy++) {
          var i = (sy * width + sx0) * 3;
          for (var sx = sx0; sx < sx1 && sx < width; sx++) {
            r += pixels[i];
            g += pixels[i + 1];
            b += pixels[i + 2];
            i += 3;
            n++;
          }
        }
        if (n == 0) n = 1;
        final o = (y * dw + x) * 3;
        out.pixels[o] = r ~/ n;
        out.pixels[o + 1] = g ~/ n;
        out.pixels[o + 2] = b ~/ n;
      }
    }
    return out;
  }
}

/// Separable box blur repeated three times, which approximates a Gaussian
/// closely enough for unsharp masking and background estimation while staying
/// O(pixels) regardless of radius.
Uint8List blurLuma(Uint8List src, int width, int height, int radius) {
  if (radius < 1) return Uint8List.fromList(src);
  var buffer = Uint8List.fromList(src);
  final scratch = Uint8List(src.length);
  for (var pass = 0; pass < 3; pass++) {
    _boxBlurH(buffer, scratch, width, height, radius);
    _boxBlurV(scratch, buffer, width, height, radius);
  }
  return buffer;
}

// Both passes split the span into head / middle / tail so the hot middle loop
// carries no bounds arithmetic at all. Clamping inside the inner loop costs
// more than the blur itself at the radii the Auto filter uses.

void _boxBlurH(Uint8List src, Uint8List dst, int w, int h, int r) {
  final window = 2 * r + 1;
  final last = w - 1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final first = src[row];
    final edge = src[row + last];

    var sum = first * (r + 1);
    for (var i = 1; i <= r; i++) {
      sum += src[row + (i <= last ? i : last)];
    }

    var x = 0;
    final headEnd = math.min(r + 1, w);
    for (; x < headEnd; x++) {
      dst[row + x] = sum ~/ window;
      sum += src[row + (x + r + 1 <= last ? x + r + 1 : last)] - first;
    }
    final midEnd = math.min(w - r - 1, w);
    for (; x < midEnd; x++) {
      dst[row + x] = sum ~/ window;
      sum += src[row + x + r + 1] - src[row + x - r];
    }
    for (; x < w; x++) {
      dst[row + x] = sum ~/ window;
      sum += edge - src[row + (x - r >= 0 ? x - r : 0)];
    }
  }
}

void _boxBlurV(Uint8List src, Uint8List dst, int w, int h, int r) {
  final window = 2 * r + 1;
  final last = h - 1;
  for (var x = 0; x < w; x++) {
    final first = src[x];
    final edge = src[last * w + x];

    var sum = first * (r + 1);
    for (var i = 1; i <= r; i++) {
      sum += src[(i <= last ? i : last) * w + x];
    }

    var y = 0;
    final headEnd = math.min(r + 1, h);
    for (; y < headEnd; y++) {
      dst[y * w + x] = sum ~/ window;
      sum += src[(y + r + 1 <= last ? y + r + 1 : last) * w + x] - first;
    }
    final midEnd = math.min(h - r - 1, h);
    for (; y < midEnd; y++) {
      dst[y * w + x] = sum ~/ window;
      sum += src[(y + r + 1) * w + x] - src[(y - r) * w + x];
    }
    for (; y < h; y++) {
      dst[y * w + x] = sum ~/ window;
      sum += edge - src[(y - r >= 0 ? y - r : 0) * w + x];
    }
  }
}

/// Local mean of [src] over a window of `radius`, computed on a downsampled
/// copy and bilinearly upsampled back.
///
/// The Auto and B&W filters need a blur radius measured in tens of pixels.
/// Running that directly is dominated by cache misses in the vertical pass,
/// and it is wasted precision: a blur that wide has no detail left to lose.
/// Estimating it small and stretching it back is visually identical and about
/// an order of magnitude faster.
Uint8List localMeanLuma(Uint8List src, int width, int height, int radius) {
  if (radius < 1) return Uint8List.fromList(src);

  // Shrink until the equivalent radius is small enough to blur cheaply.
  const targetRadius = 6;
  var factor = radius ~/ targetRadius;
  if (factor < 2) return blurLuma(src, width, height, radius);

  final sw = math.max(8, width ~/ factor);
  final sh = math.max(8, height ~/ factor);
  // Recover the real factor after integer rounding so the radius matches.
  factor = math.max(1, math.min(width ~/ sw, height ~/ sh));

  final small = _downsampleLuma(src, width, height, sw, sh);
  final smallRadius = math.max(1, radius ~/ factor);
  final blurred = blurLuma(small, sw, sh, smallRadius);
  return _upsampleLuma(blurred, sw, sh, width, height);
}

Uint8List _downsampleLuma(Uint8List src, int w, int h, int dw, int dh) {
  final out = Uint8List(dw * dh);
  for (var y = 0; y < dh; y++) {
    final sy0 = (y * h / dh).floor();
    final sy1 = math.max(sy0 + 1, ((y + 1) * h / dh).floor());
    for (var x = 0; x < dw; x++) {
      final sx0 = (x * w / dw).floor();
      final sx1 = math.max(sx0 + 1, ((x + 1) * w / dw).floor());
      var sum = 0;
      var n = 0;
      for (var sy = sy0; sy < sy1 && sy < h; sy++) {
        final row = sy * w;
        for (var sx = sx0; sx < sx1 && sx < w; sx++) {
          sum += src[row + sx];
          n++;
        }
      }
      out[y * dw + x] = n == 0 ? src[0] : sum ~/ n;
    }
  }
  return out;
}

Uint8List _upsampleLuma(Uint8List src, int sw, int sh, int dw, int dh) {
  final out = Uint8List(dw * dh);
  final xScale = sw / dw;
  final yScale = sh / dh;
  for (var y = 0; y < dh; y++) {
    final fy = ((y + 0.5) * yScale - 0.5).clamp(0.0, sh - 1.0);
    final y0 = fy.floor();
    final y1 = math.min(y0 + 1, sh - 1);
    final ty = fy - y0;
    final row0 = y0 * sw;
    final row1 = y1 * sw;
    final dstRow = y * dw;
    for (var x = 0; x < dw; x++) {
      final fx = ((x + 0.5) * xScale - 0.5).clamp(0.0, sw - 1.0);
      final x0 = fx.floor();
      final x1 = math.min(x0 + 1, sw - 1);
      final tx = fx - x0;

      final top = src[row0 + x0] * (1 - tx) + src[row0 + x1] * tx;
      final bottom = src[row1 + x0] * (1 - tx) + src[row1 + x1] * tx;
      out[dstRow + x] = (top * (1 - ty) + bottom * ty).round().clamp(0, 255);
    }
  }
  return out;
}
