import 'dart:ui' show Color;

import 'package:snow_draw_core/snow_draw_engine.dart';

/// Flutter/UI conversions for engine [DrawColor] values.
extension DrawColorToFlutterColor on DrawColor {
  /// Converts an engine [DrawColor] to Flutter [Color].
  Color toFlutterColor() => Color(argb32);
}

/// Flutter/UI conversions for engine [DrawColor] values.
extension FlutterColorToDrawColor on Color {
  /// Converts a Flutter [Color] to engine [DrawColor].
  DrawColor toDrawColor() => DrawColor(toARGB32());
}
