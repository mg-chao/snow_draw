import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../shared/hit_test_geometry.dart';
import 'arrow_core_codec.dart';
import 'arrow_core_geometry_adapter.dart' as core_geometry_adapter;
import 'arrow_like_data.dart';

class ArrowGeometry {
  const ArrowGeometry._();

  static List<DrawPoint> resolveLocalPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) => core_geometry_adapter.resolveArrowLocalPoints(
    rect: rect,
    normalizedPoints: normalizedPoints,
  );

  static List<DrawPoint> resolveWorldPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) => core_geometry_adapter.resolveArrowWorldPoints(
    rect: rect,
    normalizedPoints: normalizedPoints,
  );

  static List<DrawPoint> normalizePoints({
    required List<DrawPoint> worldPoints,
    required DrawRect rect,
  }) => core_geometry_adapter.normalizeArrowPoints(
    worldPoints: worldPoints,
    rect: rect,
  );

  /// Generates a rounded elbow SVG path from [points] using arrow-core.
  static String generateElbowPathData({
    required List<DrawPoint> points,
    double radius = 16,
  }) {
    final safeRadius = (radius.isFinite && radius > 0) ? radius : 0.0;
    return core.generateElbowArrowPath(
      encodeArrowCorePoints(points),
      safeRadius,
    );
  }

  static double calculateShaftLength({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) => core.calculateArrowShaftLength(
    points: encodeArrowCorePoints(points),
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
      points: encodeArrowCorePoints(points),
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
      points: encodeArrowCorePoints(points),
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
      points: encodeArrowCorePoints(points),
      segmentIndex: segmentIndex,
      t: t,
    );
    return _toDrawPointOrNull(point);
  }

  static double calculateArrowheadInset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) => core.calculateArrowheadInset(
    arrowhead: encodeArrowCoreArrowhead(style),
    strokeWidth: strokeWidth,
  );

  static double calculateArrowheadDirectionOffset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) => core.calculateArrowheadDirectionOffset(
    arrowhead: encodeArrowCoreArrowhead(style),
    strokeWidth: strokeWidth,
  );

  /// Resolves canonical arrowhead length from [strokeWidth].
  static double resolveArrowheadLength(double strokeWidth) =>
      core.resolveArrowheadLength(strokeWidth);

  static DrawRect calculatePathBounds({
    required List<DrawPoint> worldPoints,
    required ArrowType arrowType,
  }) => core_geometry_adapter.calculateArrowPathBoundsViaCore(
    worldPoints: worldPoints,
    arrowType: arrowType,
  );

  static List<DrawPoint> applyInsets({
    required List<DrawPoint> points,
    required double startInset,
    required double endInset,
  }) => decodeArrowCorePoints(
    core.applyArrowEndpointInsets(
      points: encodeArrowCorePoints(points),
      startInset: startInset,
      endInset: endInset,
    ),
  );

  /// Samples a render-aligned shaft polyline for arrow hit testing.
  ///
  /// The returned points track the visible shaft geometry:
  /// - curved arrows are flattened from Catmull-Rom control points;
  /// - elbow arrows are sampled from arrow-core rounded path commands;
  /// - straight arrows are returned unchanged.
  static List<DrawPoint> sampleShaftForHitTest({
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required double strokeWidth,
  }) {
    if (points.length < 2) {
      return points;
    }

    if (arrowType == ArrowType.curved && points.length > 2) {
      return flattenCatmullRomDrawPoints(
        points: points,
        strokeWidth: strokeWidth,
      );
    }

    if (arrowType == ArrowType.elbow && points.length > 2) {
      return decodeArrowCorePoints(
        core.sampleElbowPathForHitTest(
          points: encodeArrowCorePoints(points),
          strokeWidth: strokeWidth,
        ),
      );
    }

    return points;
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

DrawPoint? _toDrawPointOrNull(core.Point? point) =>
    point == null ? null : decodeArrowCorePoint(point);
