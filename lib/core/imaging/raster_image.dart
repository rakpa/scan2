import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:scan2/core/imaging/raster.dart';

/// Uploads a [Raster] straight to a GPU-backed [ui.Image].
///
/// The alternative — encode to JPEG, hand the bytes to `Image.memory`, let
/// Flutter decode them again — costs an encode and a decode per preview
/// frame, which is most of the latency budget for something the user is
/// dragging a slider against.
Future<ui.Image> rasterToImage(Raster raster) {
  final rgba = Uint8List(raster.length * 4);
  var src = 0;
  var dst = 0;
  for (var i = 0; i < raster.length; i++) {
    rgba[dst] = raster.pixels[src];
    rgba[dst + 1] = raster.pixels[src + 1];
    rgba[dst + 2] = raster.pixels[src + 2];
    rgba[dst + 3] = 255;
    src += 3;
    dst += 4;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    raster.width,
    raster.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// The rectangle a [BoxFit.contain] image of [imageSize] occupies inside
/// [container], which is where crop handles must be positioned.
ui.Rect containedImageRect(ui.Size container, ui.Size imageSize) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      container.width <= 0 ||
      container.height <= 0) {
    return ui.Rect.fromLTWH(0, 0, container.width, container.height);
  }

  // Contain: whichever axis runs out first sets the scale.
  final scale = math.min(
    container.width / imageSize.width,
    container.height / imageSize.height,
  );
  final width = imageSize.width * scale;
  final height = imageSize.height * scale;
  return ui.Rect.fromLTWH(
    (container.width - width) / 2,
    (container.height - height) / 2,
    width,
    height,
  );
}
