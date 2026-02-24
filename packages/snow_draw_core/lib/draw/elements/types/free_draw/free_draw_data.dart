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
import '../shared/element_data_codec.dart';

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
    color: DrawColor(json['color'] as int),
    fillColor: DrawColor(json['fillColor'] as int),
    strokeWidth: (json['strokeWidth'] as num).toDouble(),
    strokeStyle: ElementDataCodec.decodeEnumByName(
      values: StrokeStyle.values,
      raw: json['strokeStyle'],
      fieldName: 'strokeStyle',
    ),
    fillStyle: ElementDataCodec.decodeEnumByName(
      values: FillStyle.values,
      raw: json['fillStyle'],
      fieldName: 'fillStyle',
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
    color: update.color,
    fillColor: update.fillColor,
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
      throw const FormatException('Free draw points must be a JSON array');
    }

    final points = <DrawPoint>[];
    for (final rawPoint in rawPoints) {
      points.add(_decodePoint(rawPoint));
    }

    if (points.length < 2) {
      throw const FormatException(
        'Free draw payload must include at least two points',
      );
    }

    return List<DrawPoint>.unmodifiable(points);
  }

  static DrawPoint _decodePoint(Object? rawPoint) {
    final pointMap = ElementDataCodec.asJsonMap(
      rawPoint,
      fieldName: 'free draw point',
    );
    final x = pointMap['x'];
    final y = pointMap['y'];
    if (x is! num || y is! num) {
      throw const FormatException(
        'Free draw point entries must provide numeric x/y',
      );
    }
    final pressureValue = pointMap['p'];
    if (pressureValue != null && pressureValue is! num) {
      throw const FormatException(
        'Free draw point pressure must be numeric when provided',
      );
    }
    return DrawPoint(
      x: x.toDouble(),
      y: y.toDouble(),
      pressure: (pressureValue as num?)?.toDouble() ?? 0.0,
    );
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
}
