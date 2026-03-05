import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_like_data.dart';

class ArrowGeometry {
  const ArrowGeometry._();

  static const _defaultPoints = <DrawPoint>[
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  static List<DrawPoint> resolveLocalPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map((point) => DrawPoint(x: point.x * width, y: point.y * height))
        .toList(growable: false);
  }

  static List<DrawPoint> resolveWorldPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width,
            y: rect.minY + point.y * height,
          ),
        )
        .toList(growable: false);
  }

  static List<DrawPoint> normalizePoints({
    required List<DrawPoint> worldPoints,
    required DrawRect rect,
  }) {
    final points = _ensureMinPoints(worldPoints);
    final width = rect.width;
    final height = rect.height;
    return List<DrawPoint>.unmodifiable(
      points.map((point) {
        final x = width == 0 ? 0.0 : (point.x - rect.minX) / width;
        final y = height == 0 ? 0.0 : (point.y - rect.minY) / height;
        return DrawPoint(
          x: _clamp01(x),
          y: _clamp01(y),
          pressure: point.pressure,
        );
      }),
    );
  }

  /// Generates a rounded elbow SVG path from [points] using arrow-core.
  static String generateElbowPathData({
    required List<DrawPoint> points,
    double radius = 16,
  }) {
    final safeRadius = (radius.isFinite && radius > 0) ? radius : 0.0;
    return core.generateElbowArrowPath(_toCorePoints(points), safeRadius);
  }

  static double calculateShaftLength({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) => core.calculateArrowShaftLength(
    points: _toCorePoints(points),
    curved: arrowType == ArrowType.curved,
  );

  static DrawPoint? resolveStartDirection(
    List<DrawPoint> points,
    ArrowType arrowType, {
    double startInset = 0,
    double endInset = 0,
    double directionOffset = 0,
  }) {
    final direction = core.resolveArrowStartDirection(
      points: _toCorePoints(points),
      curved: arrowType == ArrowType.curved,
      startInset: startInset,
      endInset: endInset,
      directionOffset: directionOffset,
    );
    return _toDrawPointOrNull(direction);
  }

  static DrawPoint? resolveEndDirection(
    List<DrawPoint> points,
    ArrowType arrowType, {
    double startInset = 0,
    double endInset = 0,
    double directionOffset = 0,
  }) {
    final direction = core.resolveArrowEndDirection(
      points: _toCorePoints(points),
      curved: arrowType == ArrowType.curved,
      startInset: startInset,
      endInset: endInset,
      directionOffset: directionOffset,
    );
    return _toDrawPointOrNull(direction);
  }

  /// Calculates a point on the curved path using [DrawPoint] inputs.
  static DrawPoint? calculateCurveDrawPoint({
    required List<DrawPoint> points,
    required int segmentIndex,
    required double t,
  }) {
    final point = core.calculateCurvePoint(
      points: _toCorePoints(points),
      segmentIndex: segmentIndex,
      t: t,
    );
    return _toDrawPointOrNull(point);
  }

  static double calculateArrowheadInset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) => core.calculateArrowheadInset(
    arrowhead: _toCoreArrowhead(style),
    strokeWidth: strokeWidth,
  );

  static double calculateArrowheadDirectionOffset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) => core.calculateArrowheadDirectionOffset(
    arrowhead: _toCoreArrowhead(style),
    strokeWidth: strokeWidth,
  );

  /// Resolves canonical arrowhead length from [strokeWidth].
  static double resolveArrowheadLength(double strokeWidth) =>
      core.resolveArrowheadLength(strokeWidth);

  static DrawRect calculatePathBounds({
    required List<DrawPoint> worldPoints,
    required ArrowType arrowType,
  }) {
    final bounds = core.calculateArrowPathBounds(
      points: _toCorePoints(worldPoints),
      curved: arrowType == ArrowType.curved,
    );
    return DrawRect(
      minX: bounds[0],
      minY: bounds[1],
      maxX: bounds[2],
      maxY: bounds[3],
    );
  }

  static List<DrawPoint> applyInsets({
    required List<DrawPoint> points,
    required double startInset,
    required double endInset,
  }) => _toDrawPoints(
    core.applyArrowEndpointInsets(
      points: _toCorePoints(points),
      startInset: startInset,
      endInset: endInset,
    ),
  );

  static List<DrawPoint> _ensureMinPoints(List<DrawPoint> points) {
    if (points.length >= 2) {
      return points;
    }
    if (points.isEmpty) {
      return _defaultPoints;
    }
    return [points.first, points.first];
  }

  static double _clamp01(double value) {
    if (!value.isFinite) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}

class ArrowGeometryDescriptor {
  ArrowGeometryDescriptor({required this.data, required this.rect});

  final ArrowLikeData data;
  final DrawRect rect;

  List<DrawPoint>? _localDrawPoints;
  List<DrawPoint>? _insetDrawPoints;
  DrawPoint? _startDirectionPoint;
  DrawPoint? _endDirectionPoint;
  double? _startInset;
  double? _endInset;
  double? _startDirectionOffset;
  double? _endDirectionOffset;

  List<DrawPoint> get localDrawPoints =>
      _localDrawPoints ??= ArrowGeometry.resolveLocalPoints(
        rect: rect,
        normalizedPoints: data.points,
      );

  double get startInset =>
      _startInset ??= ArrowGeometry.calculateArrowheadInset(
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get endInset => _endInset ??= ArrowGeometry.calculateArrowheadInset(
    style: data.endArrowhead,
    strokeWidth: data.strokeWidth,
  );

  double get startDirectionOffset =>
      _startDirectionOffset ??= ArrowGeometry.calculateArrowheadDirectionOffset(
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get endDirectionOffset =>
      _endDirectionOffset ??= ArrowGeometry.calculateArrowheadDirectionOffset(
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
      );

  List<DrawPoint> get insetDrawPoints {
    final cached = _insetDrawPoints;
    if (cached != null) {
      return cached;
    }
    final applied = (startInset <= 0 && endInset <= 0)
        ? localDrawPoints
        : ArrowGeometry.applyInsets(
            points: localDrawPoints,
            startInset: startInset,
            endInset: endInset,
          );
    _insetDrawPoints = applied;
    return applied;
  }

  DrawPoint? get startDirectionPoint =>
      _startDirectionPoint ??= ArrowGeometry.resolveStartDirection(
        localDrawPoints,
        data.arrowType,
        startInset: startInset,
        endInset: endInset,
        directionOffset: startDirectionOffset,
      );

  DrawPoint? get endDirectionPoint =>
      _endDirectionPoint ??= ArrowGeometry.resolveEndDirection(
        localDrawPoints,
        data.arrowType,
        startInset: startInset,
        endInset: endInset,
        directionOffset: endDirectionOffset,
      );
}

core.Arrowhead? _toCoreArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.none:
      return null;
    case ArrowheadStyle.standard:
      return 'arrow';
    case ArrowheadStyle.triangle:
      return 'triangle';
    case ArrowheadStyle.triangleOutline:
      return 'triangle_outline';
    case ArrowheadStyle.square:
      return 'square';
    case ArrowheadStyle.dot:
      return 'dot';
    case ArrowheadStyle.circle:
      return 'circle';
    case ArrowheadStyle.circleOutline:
      return 'circle_outline';
    case ArrowheadStyle.diamond:
      return 'diamond';
    case ArrowheadStyle.diamondOutline:
      return 'diamond_outline';
    case ArrowheadStyle.crowfootOne:
      return 'crowfoot_one';
    case ArrowheadStyle.crowfootMany:
      return 'crowfoot_many';
    case ArrowheadStyle.crowfootOneOrMany:
      return 'crowfoot_one_or_many';
    case ArrowheadStyle.invertedTriangle:
      return 'inverted_triangle';
    case ArrowheadStyle.verticalLine:
      return 'bar';
  }
}

List<core.Point> _toCorePoints(List<DrawPoint> points) => List<core.Point>.of(
  points.map((point) => <double>[point.x, point.y]),
  growable: false,
);

List<DrawPoint> _toDrawPoints(List<core.Point> points) =>
    List<DrawPoint>.unmodifiable(
      points
          .map((point) => DrawPoint(x: point[0], y: point[1]))
          .toList(growable: false),
    );

DrawPoint? _toDrawPointOrNull(core.Point? point) =>
    point == null ? null : DrawPoint(x: point[0], y: point[1]);
