import 'dart:ui' show Color;

import 'package:snow_draw_core/snow_draw_engine.dart';

/// Flutter/UI conversions for core [DrawColor] values.
extension DrawColorToFlutterColor on DrawColor {
  /// Converts a core [DrawColor] to Flutter [Color].
  Color toFlutterColor() => Color(argb32);
}

/// Flutter/UI conversions for core [DrawColor] values.
extension FlutterColorToDrawColor on Color {
  /// Converts a Flutter [Color] to core [DrawColor].
  DrawColor toDrawColor() => DrawColor(toARGB32());
}
