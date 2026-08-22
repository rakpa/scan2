import 'package:flutter/widgets.dart';

/// Press-motion tokens for Scanella's tap language.
///
/// Visual design lives in [Brand]; this file only describes how far a control
/// travels and how quickly it springs back.
class Tactile {
  const Tactile._();

  /// Cards, tiles, chips, list rows.
  static const pressScaleCard = 0.97;

  /// Primary buttons (Save, View in Documents).
  static const pressScalePrimary = 0.95;

  /// Raised camera FAB — slightly heavier than a pastel tile.
  static const pressScaleFab = 0.94;

  /// Header icons, tool tiles, compact icon buttons.
  static const pressScaleIcon = 0.96;

  /// Reduce Motion: keep a hint of travel without a large spring.
  static const pressScaleReduce = 0.99;

  /// 7% black overlay while the finger is down.
  static const pressOverlay = 0.07;

  /// Touch-down scale tween. Stay inside 40–70ms; never a 300ms ease.
  static const pressInDuration = Duration(milliseconds: 55);

  /// Wait this long after down before buzzing so a scroll can cancel.
  static const hapticDelay = Duration(milliseconds: 40);

  /// Finger has left the control (or started a scroll) past this distance.
  static const slideCancelSlop = 18.0;

  static const minHitSize = 44.0;

  static const SpringDescription spring = SpringDescription(
    mass: 0.4,
    stiffness: 300,
    damping: 20,
  );

  static Color overlayColor({double opacity = pressOverlay}) =>
      Color.fromRGBO(0, 0, 0, opacity);
}
