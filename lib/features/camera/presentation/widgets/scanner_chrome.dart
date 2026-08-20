import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/scan_mode.dart';

/// Flash cycle on the scanner: Off → On → Auto.
enum ScannerFlash { off, on, auto }

extension ScannerFlashX on ScannerFlash {
  ScannerFlash get next => switch (this) {
    ScannerFlash.off => ScannerFlash.on,
    ScannerFlash.on => ScannerFlash.auto,
    ScannerFlash.auto => ScannerFlash.off,
  };

  IconData get icon => switch (this) {
    ScannerFlash.off => Icons.flash_off_rounded,
    ScannerFlash.on => Icons.flash_on_rounded,
    ScannerFlash.auto => Icons.flash_auto_rounded,
  };

  String get tooltip => switch (this) {
    ScannerFlash.off => 'Flash off',
    ScannerFlash.on => 'Flash on',
    ScannerFlash.auto => 'Flash auto',
  };
}

class ScannerTopBar extends StatelessWidget {
  const ScannerTopBar({
    super.key,
    required this.flash,
    required this.onClose,
    required this.onToggleFlash,
  });

  final ScannerFlash flash;
  final VoidCallback onClose;
  final VoidCallback onToggleFlash;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
              const Expanded(
                child: Text(
                  'Scan Document',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: flash.tooltip,
                onPressed: onToggleFlash,
                icon: Icon(flash.icon, color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AutoDetectPill extends StatelessWidget {
  const AutoDetectPill({
    super.key,
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Auto-detect',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Text(
              '  •  ',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              enabled ? 'On' : 'Off',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? const Color(0xFF3DDC84) : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlignHint extends StatelessWidget {
  const AlignHint({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Align document within the frame',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class ScanModeSelector extends StatelessWidget {
  const ScanModeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ScanMode selected;
  final ValueChanged<ScanMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mode in ScanMode.values)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelected(mode),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  mode.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mode == selected ? Brand.blue : Colors.white,
                    fontWeight: mode == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ScannerBottomBar extends StatelessWidget {
  const ScannerBottomBar({
    super.key,
    required this.mode,
    required this.autoCapture,
    required this.capturing,
    required this.holdProgress,
    required this.onModeSelected,
    required this.onGallery,
    required this.onShutter,
    required this.onToggleAuto,
  });

  final ScanMode mode;
  final bool autoCapture;
  final bool capturing;
  final double holdProgress;
  final ValueChanged<ScanMode> onModeSelected;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onToggleAuto;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScanModeSelector(selected: mode, onSelected: onModeSelected),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _LabeledIcon(
                      icon: const Icon(Icons.photo_outlined, size: 28),
                      label: 'Gallery',
                      onTap: onGallery,
                    ),
                  ),
                  ScannerShutter(
                    progress: holdProgress,
                    enabled: !capturing,
                    onPressed: onShutter,
                  ),
                  Expanded(
                    child: _LabeledIcon(
                      icon: const _DashedSquareIcon(),
                      label: 'Auto',
                      active: autoCapture,
                      onTap: onToggleAuto,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerShutter extends StatelessWidget {
  const ScannerShutter({
    super.key,
    required this.progress,
    required this.enabled,
    required this.onPressed,
  });

  final double progress;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: SizedBox(
        width: 82,
        height: 82,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Brand.blue, width: 5),
              ),
            ),
            SizedBox(
              width: 78,
              height: 78,
              child: CircularProgressIndicator(
                value: progress <= 0.01 ? 0 : progress,
                strokeWidth: 5,
                color: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledIcon extends StatelessWidget {
  const _LabeledIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Brand.blue : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: color, size: 26),
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedSquareIcon extends StatelessWidget {
  const _DashedSquareIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _DashedSquarePainter(color)),
    );
  }
}

class _DashedSquarePainter extends CustomPainter {
  _DashedSquarePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
      const Radius.circular(4),
    );
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      const dash = 3.2;
      const gap = 2.2;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedSquarePainter oldDelegate) =>
      oldDelegate.color != color;
}
