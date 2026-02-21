import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_color.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/list_equality.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class FreeDrawData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  static const typeIdToken = ElementTypeId<FreeDrawData>('free_draw');
  static const List<DrawPoint> _defaultPoints = [
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  const FreeDrawData({
    this.points = _defaultPoints,
    this.color = ConfigDefaults.defaultColor,
    this.fillColor = ConfigDefaults.defaultFillColor,
    this.fillStyle = ConfigDefaults.defaultFillStyle,
    this.strokeWidth = ConfigDefaults.defaultStrokeWidth,
    this.strokeStyle = ConfigDefaults.defaultStrokeStyle,
  });

  factory FreeDrawData.fromJson(Map<String, dynamic> json) => FreeDrawData(
    points: _decodePoints(json['points']),
    color: DrawColor(
      (json['color'] as int?) ?? ConfigDefaults.defaultColor.toARGB32(),
    ),
    fillColor: DrawColor(
      (json['fillColor'] as int?) ?? ConfigDefaults.defaultFillColor.toARGB32(),
    ),
    strokeWidth:
        (json['strokeWidth'] as num?)?.toDouble() ??
        ConfigDefaults.defaultStrokeWidth,
    strokeStyle: StrokeStyle.values.firstWhere(
      (style) => style.name == json['strokeStyle'],
      orElse: () => ConfigDefaults.defaultStrokeStyle,
    ),
    fillStyle: FillStyle.values.firstWhere(
      (style) => style.name == json['fillStyle'],
      orElse: () => ConfigDefaults.defaultFillStyle,
    ),
  );

  /// Normalized path points in element-local space (0..1).
  final List<DrawPoint> points;
  final DrawColor color;
  final DrawColor fillColor;
  final FillStyle fillStyle;
  final double strokeWidth;
  final StrokeStyle strokeStyle;

  @override
  ElementTypeId<FreeDrawData> get typeId => FreeDrawData.typeIdToken;

  FreeDrawData copyWith({
    List<DrawPoint>? points,
    DrawColor? color,
    DrawColor? fillColor,
    FillStyle? fillStyle,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
  }) => FreeDrawData(
    points: points != null ? List<DrawPoint>.unmodifiable(points) : this.points,
    color: color ?? this.color,
    fillColor: fillColor ?? this.fillColor,
    fillStyle: fillStyle ?? this.fillStyle,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) => copyWith(
    color: style.color,
    fillColor: style.fillColor,
    fillStyle: style.fillStyle,
    strokeWidth: style.strokeWidth,
    strokeStyle: style.strokeStyle,
  );

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    color: _resolveColor(update.color, color),
    fillColor: _resolveColor(update.fillColor, fillColor),
    fillStyle: update.fillStyle ?? fillStyle,
    strokeWidth: update.strokeWidth ?? strokeWidth,
    strokeStyle: update.strokeStyle ?? strokeStyle,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'points': points
        .map(
          (point) => {
            'x': point.x,
            'y': point.y,
            if (point.hasPressure) 'p': point.pressure,
          },
        )
        .toList(),
    'color': color.toARGB32(),
    'fillColor': fillColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'fillStyle': fillStyle.name,
  };

  static List<DrawPoint> _decodePoints(Object? rawPoints) {
    if (rawPoints is! List) {
      return _defaultPoints;
    }

    final points = <DrawPoint>[];
    for (final entry in rawPoints.whereType<Map<Object?, Object?>>()) {
      final point = _decodePoint(entry);
      if (point != null) {
        points.add(point);
      }
    }

    if (points.length < 2) {
      return _defaultPoints;
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static DrawPoint? _decodePoint(Map<Object?, Object?> pointMap) {
    final x = (pointMap['x'] as num?)?.toDouble();
    final y = (pointMap['y'] as num?)?.toDouble();
    if (x == null || y == null) {
      return null;
    }
    final pressure = (pointMap['p'] as num?)?.toDouble() ?? 0.0;
    return DrawPoint(x: x, y: y, pressure: pressure);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeDrawData &&
          pointListEquals(other.points, points) &&
          other.color == color &&
          other.fillColor == fillColor &&
          other.fillStyle == fillStyle &&
          other.strokeWidth == strokeWidth &&
          other.strokeStyle == strokeStyle;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    color,
    fillColor,
    fillStyle,
    strokeWidth,
    strokeStyle,
  );

  static DrawColor _resolveColor(DrawColor? next, DrawColor fallback) =>
      next ?? fallback;
}
