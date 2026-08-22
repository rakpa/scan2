import 'package:flutter/widgets.dart';

/// Press-motion tokens for Scanella's tap language.
///
/// Visual design lives in [Brand]; this file only describes how far a control
/// travels and how quickly it springs back.
class Tactile {
  const Tactile._();

  /// Cards, tiles, chips, list rows.
  static const pressScaleCard = 0.94;

  /// Primary buttons (Save, View in Documents).
  static const pressScalePrimary = 0.92;

  /// Raised camera FAB — heavier than a pastel tile.
  static const pressScaleFab = 0.90;

  /// Header icons, tool tiles, compact icon buttons.
  static const pressScaleIcon = 0.92;

  /// Reduce Motion: keep a hint of travel without a large spring.
  static const pressScaleReduce = 0.99;

  /// Dim while the finger is down. 7% was invisible on pastel cards.
  static const pressOverlay = 0.16;

  static const pressInDuration = Duration(milliseconds: 40);

  /// Finger has left the control (or started a scroll) past this distance.
  static const slideCancelSlop = 24.0;

  static const minHitSize = 44.0;

  static const SpringDescription spring = SpringDescription(
    mass: 0.4,
    stiffness: 400,
    damping: 22,
  );

  static Color overlayColor({double opacity = pressOverlay}) =>
      Color.fromRGBO(0, 0, 0, opacity);
}
