# Scan2

An offline document scanner for iOS and Android, built with Flutter.

Point the camera at a page: Scan2 tracks the edges live, releases the shutter
once the page is framed and the phone is steady, straightens the page with a
perspective correction and cleans it up — then keeps the original so every
edit stays reversible. Nothing leaves the device.

## How it works

### Edge detection

`DocumentQuadDetector` is a pure-Dart, line-based detector — no OpenCV, no ML
model, no native code to keep in sync across two platforms:

1. Blur, then Sobel gradients.
2. Strong gradient pixels vote in a Hough space for near-vertical and
   near-horizontal lines, in four accumulators **split by gradient polarity**.
3. Candidate quads are built from those lines and scored on whether real
   luminance steps of the expected direction run along their perimeter.

Steps 2 and 3 are what make it work on real pages. Picking the highest-voted
pair of lines — the obvious approach — locks onto printed text instead of the
page border: body text is high-contrast, dead straight, and there is a lot of
it. Splitting votes by polarity means a light page's left border (dark→light)
and its right border (light→dark) land in different accumulators, and a line
of text, which has paper on both sides, cannot supply a consistent pair.

Accuracy is measured, not assumed. `test/unit/document_detection_accuracy_test.dart`
renders synthetic scenes with a known ground-truth quad — tilted, in
perspective, on textured desks, under uneven light, with dense text — and
asserts mean corner error stays under 1.5% of the image diagonal.

Detection runs on a persistent background isolate (`DetectionWorker`), about
8ms per frame. Frames that arrive while one is in flight are dropped rather
than queued: a stale detection is worse than a lower analysis rate.

### Auto-capture

`DocumentEdgeTracker` keys the shutter off **motion**, not confidence alone.
Confidence says a page was found; it says nothing about whether the phone is
still. The page must be recognised *and* essentially motionless for 900ms, and
progress toward that is published so the shutter ring can fill — the capture
is never a surprise. A cooldown and a duplicate check stop the sheet still
sitting under the camera from being scanned twice.

### Perspective correction and filters

Cropping uses a real projective homography (Heckbert's square-to-quad closed
form) with bilinear sampling. Interpolating bilinearly between the four
corners — the intuitive approach — maps the *border* correctly but leaves the
interior distorted; `test/unit/scan_pipeline_test.dart` prints registration
marks at known page-local positions and asserts they land where they should
after correction, which that approach misses by 8%.

Filters are explicit raster kernels in `lib/core/imaging/` and
`image_processor.dart`, so the crop preview and the saved page run identical
code at different resolutions:

| Filter | What it does |
| --- | --- |
| Original | Untouched |
| Auto | Divides out a blurred estimate of the lighting, stretches levels onto a clean white point, sharpens lightly |
| Grayscale | Rec. 601 luma |
| B&W | Adaptive local threshold — a global cutoff loses either the ink or the paper on an unevenly lit page |
| Sharpness | Unsharp mask driven by the luma channel |

Interactive previews run on a decoded, downscaled raster held in memory
(`scan_preview.dart`); only Save touches full resolution. Filtering a 12MP
frame per tap takes several seconds, which is indistinguishable from the
filter doing nothing.

### Storage

Pages live under `<appDocuments>/documents/<docId>/` with a JSON manifest
recording titles, page order, crop quads and filter settings. Paths are stored
**relative** to the documents root: iOS reassigns the application container
path between installs, so absolute paths written today dangle after the next
build.

Each page keeps the untouched capture beside the finished image, so reopening
the editor re-derives from the original rather than re-processing an
already-processed JPEG.

## Layout

```
lib/
  core/imaging/          raster type, blur, filter primitives
  features/
    camera/              detector, tracker, detection isolate, capture UI
    crop/                homography, filters, preview pipeline, editor UI
    library/             document store, model, PDF export
    settings/ onboarding/ shared/
test/
  support/scene_builder.dart   synthetic scenes with ground-truth geometry
  unit/                        detector accuracy, pipeline, store, tracker
```

## Running

```bash
flutter pub get
flutter run                 # a device or simulator — scanning needs a camera
flutter test
flutter analyze
```

`flutter run -d chrome` builds, but the browser has no camera or file system:
the library is in-memory and scanning is unavailable. Use it for UI work only.

## Releasing to TestFlight

See `ios/README.md`. In short: bump `version:` in `pubspec.yaml` — the `+N` is
the CFBundleVersion and must exceed the last successful upload — and push to
`main` with `[testflight]` in the commit message.
