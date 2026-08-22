import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:scan2/core/haptics/app_haptics.dart';
import 'package:scan2/core/theme/tactile.dart';

/// Instant down-state + snappy spring release for tappable controls.
///
/// Scale and overlay snap on pointer-down (not after [onPressed], and not
/// tweened in). Sliding off springs back and does not fire the action.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.haptic = AppHaptic.selection,
    this.scale = Tactile.pressScaleCard,
    this.enabled = true,
    this.overlay = true,
    this.hapticOnDown = true,
    this.borderRadius,
    this.minSize = Tactile.minHitSize,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final AppHaptic haptic;
  final double scale;
  final bool enabled;
  final bool overlay;

  /// When false, haptic waits for a confirmed tap. Use inside scroll views
  /// that have competing child buttons.
  final bool hapticOnDown;
  final BorderRadius? borderRadius;
  final double minSize;
  final String? tooltip;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _held = false;
  bool _cancelled = false;
  bool _hapticPlayed = false;
  Offset? _downGlobal;

  bool get _canPress => widget.enabled && widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _pressedScale(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Tactile.pressScaleReduce;
    }
    return widget.scale;
  }

  void _snapPressed() {
    _controller.stop();
    _controller.value = _pressedScale(context);
  }

  void _springBack() {
    _controller.stop();
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    _controller.animateWith(
      SpringSimulation(
        Tactile.spring,
        _controller.value,
        1,
        _controller.velocity,
      ),
    );
  }

  void _playHaptic() {
    if (_hapticPlayed || widget.haptic == AppHaptic.none) return;
    _hapticPlayed = true;
    AppHaptics.play(widget.haptic);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_canPress) return;
    _held = true;
    _cancelled = false;
    _hapticPlayed = false;
    _downGlobal = event.position;
    _snapPressed();
    if (widget.hapticOnDown) _playHaptic();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_held || _cancelled) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    final inside = (Offset.zero & box.size).inflate(4);
    final moved = _downGlobal == null
        ? 0.0
        : (event.position - _downGlobal!).distance;
    if (moved > Tactile.slideCancelSlop || !inside.contains(local)) {
      _cancelHold();
    }
  }

  void _cancelHold() {
    if (_cancelled && !_held) return;
    _cancelled = true;
    _held = false;
    _springBack();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_held) return;
    _held = false;
    _springBack();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelHold();
  }

  void _onTap() {
    if (!_canPress || _cancelled) return;
    _playHaptic();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _controller.value;
        Widget painted = child!;
        if (widget.overlay) {
          final travel = (1 - widget.scale).clamp(0.001, 1.0);
          final t = ((1 - scale) / travel).clamp(0.0, 1.0);
          painted = Stack(
            fit: StackFit.passthrough,
            children: [
              painted,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: widget.borderRadius ?? BorderRadius.zero,
                    child: ColoredBox(
                      color: Tactile.overlayColor(
                        opacity: Tactile.pressOverlay * t,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Transform.scale(
          key: const ValueKey('scanella-press-scale'),
          scale: scale,
          filterQuality: FilterQuality.low,
          transformHitTests: false,
          child: painted,
        );
      },
      child: widget.child,
    );

    child = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minSize,
        minHeight: widget.minSize,
      ),
      child: child,
    );

    child = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _canPress ? _onTap : null,
        child: child,
      ),
    );

    child = Semantics(
      button: true,
      enabled: _canPress,
      child: child,
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// 44×44 icon control with selection haptic and a pressed scale.
class TactileIconButton extends StatelessWidget {
  const TactileIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 24,
    this.haptic = AppHaptic.selection,
    this.scale = Tactile.pressScaleIcon,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final AppHaptic haptic;
  final double scale;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: onPressed,
      enabled: enabled && onPressed != null,
      haptic: haptic,
      scale: scale,
      overlay: true,
      borderRadius: BorderRadius.circular(22),
      tooltip: tooltip,
      child: SizedBox(
        width: Tactile.minHitSize,
        height: Tactile.minHitSize,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

/// Text/link control (Done, View All, Change) with selection haptic.
class TactileTextButton extends StatelessWidget {
  const TactileTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style,
    this.haptic = AppHaptic.selection,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  final String label;
  final VoidCallback? onPressed;
  final TextStyle? style;
  final AppHaptic haptic;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: onPressed,
      haptic: haptic,
      scale: Tactile.pressScaleIcon,
      overlay: true,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: padding,
        child: Text(label, style: style),
      ),
    );
  }
}
