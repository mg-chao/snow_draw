import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import '../shared/hit_test_geometry.dart';
import 'arrow_data.dart';

/// Encodes arrow elements into backend-agnostic scene primitives.
final class ArrowSceneEncoder implements ElementSceneEncoder<ArrowData> {
  /// Creates an arrow scene encoder.
  const ArrowSceneEncoder();

  static const _kappa = 0.5522847498307936;

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! ArrowData) {
      throw StateError(
        'ArrowSceneEncoder can only encode ArrowData (got ${data.runtimeType})',
      );
    }

    final strokeColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeVisible = _alphaOf(strokeColorArgb) > 0 && data.strokeWidth > 0;
    if (!strokeVisible) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final basePoints = _resolveCenterLocalPoints(
      rect: element.rect,
      data: data,
    );
    if (basePoints.length < 2) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }
    final insetPoints = _applyInsets(
      points: basePoints,
      startInset: _arrowheadInset(data.startArrowhead, data.strokeWidth),
      endInset: _arrowheadInset(data.endArrowhead, data.strokeWidth),
    );
    if (insetPoints.length < 2) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final shaftPath = _buildShaftPath(
      points: insetPoints,
      arrowType: data.arrowType,
    );
    final arrowheadPath = _buildArrowheadsPath(
      points: insetPoints,
      arrowType: data.arrowType,
      data: data,
    );

    final localScene = SceneBuilder()
      ..addPathStroke(
        path: shaftPath,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: RenderStrokeCap.round,
        strokeJoin: RenderStrokeJoin.round,
        dashPattern: _dashPatternFor(
          strokeStyle: data.strokeStyle,
          strokeWidth: data.strokeWidth,
        ),
      );
    if (arrowheadPath.commands.isNotEmpty) {
      localScene.addPathStroke(
        path: arrowheadPath,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: RenderStrokeCap.round,
        strokeJoin: RenderStrokeJoin.round,
      );
    }

    final builder = SceneBuilder()
      ..addTransform(
        child: localScene.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return builder.build(cullRect: element.rect);
  }

  static int _alphaOf(int argb) => (argb >>> 24) & 0xFF;

  static int _applyElementOpacity({
    required int argb,
    required double elementOpacity,
  }) {
    final baseAlpha = (argb >>> 24) & 0xFF;
    final scaledAlpha = (baseAlpha * elementOpacity.clamp(0.0, 1.0))
        .round()
        .clamp(0, 255);
    return (scaledAlpha << 24) | (argb & 0x00FFFFFF);
  }

  static List<double>? _dashPatternFor({
    required StrokeStyle strokeStyle,
    required double strokeWidth,
  }) => switch (strokeStyle) {
    StrokeStyle.solid => null,
    StrokeStyle.dashed => <double>[strokeWidth * 2, strokeWidth * 2 * 1.2],
    StrokeStyle.dotted => <double>[
      math.max(0.01, strokeWidth * 0.01),
      math.max(strokeWidth * 2, strokeWidth * 0.01),
    ],
  };

  static List<DrawPoint> _resolveCenterLocalPoints({
    required DrawRect rect,
    required ArrowData data,
  }) {
    final width = rect.width;
    final height = rect.height;
    final center = rect.center;
    return data.points
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width - center.x,
            y: rect.minY + point.y * height - center.y,
          ),
        )
        .toList(growable: false);
  }

  static RenderPath _buildShaftPath({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) {
    if (arrowType == ArrowType.curved && points.length > 2) {
      return _curvedPath(points);
    }
    return _polylinePath(points);
  }

  static RenderPath _polylinePath(List<DrawPoint> points) {
    if (points.isEmpty) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
    for (final point in points.skip(1)) {
      commands.add(RenderLineTo(point));
    }
    return RenderPath(commands);
  }

  static RenderPath _curvedPath(List<DrawPoint> points) {
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
    for (var index = 0; index < points.length - 1; index += 1) {
      final segment = buildCatmullRomCubicSegment(points, index);
      commands.add(
        RenderCubicTo(
          control1: segment.control1,
          control2: segment.control2,
          end: segment.end,
        ),
      );
    }
    return RenderPath(commands);
  }

  static RenderPath _buildArrowheadsPath({
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required ArrowData data,
  }) {
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    final commands = <RenderPathCommand>[];
    final startDirection = _resolveStartDirection(
      points: points,
      arrowType: arrowType,
    );
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      commands.addAll(
        _arrowheadCommands(
          tip: points.first,
          direction: startDirection,
          style: data.startArrowhead,
          strokeWidth: data.strokeWidth,
        ),
      );
    }
    final endDirection = _resolveEndDirection(
      points: points,
      arrowType: arrowType,
    );
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      commands.addAll(
        _arrowheadCommands(
          tip: points.last,
          direction: endDirection,
          style: data.endArrowhead,
          strokeWidth: data.strokeWidth,
        ),
      );
    }
    return RenderPath(commands);
  }

  static DrawPoint? _resolveStartDirection({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return null;
    }
    if (arrowType == ArrowType.curved && points.length > 2) {
      final segment = buildCatmullRomCubicSegment(points, 0);
      return _normalize(
        DrawPoint(
          x: segment.control1.x - segment.start.x,
          y: segment.control1.y - segment.start.y,
        ),
      );
    }
    return _normalize(points.first - points[1]);
  }

  static DrawPoint? _resolveEndDirection({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return null;
    }
    if (arrowType == ArrowType.curved && points.length > 2) {
      final segment = buildCatmullRomCubicSegment(points, points.length - 2);
      return _normalize(
        DrawPoint(
          x: segment.end.x - segment.control2.x,
          y: segment.end.y - segment.control2.y,
        ),
      );
    }
    return _normalize(points.last - points[points.length - 2]);
  }

  static List<RenderPathCommand> _arrowheadCommands({
    required DrawPoint tip,
    required DrawPoint direction,
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (strokeWidth <= 0) {
      return const <RenderPathCommand>[];
    }

    final unitDir = _normalize(direction);
    if (unitDir == null) {
      return const <RenderPathCommand>[];
    }

    final length = strokeWidth * 4 + 12;
    final width = length * 0.6;
    final perp = DrawPoint(x: -unitDir.y, y: unitDir.x);

    switch (style) {
      case ArrowheadStyle.none:
        return const <RenderPathCommand>[];
      case ArrowheadStyle.standard:
        return _standardArrowhead(
          tip: tip,
          direction: unitDir,
          perp: perp,
          length: length,
          width: width,
        );
      case ArrowheadStyle.triangle:
        return _triangleArrowhead(
          tip: tip,
          direction: unitDir,
          perp: perp,
          length: length,
          width: width,
        );
      case ArrowheadStyle.square:
        return _squareArrowhead(
          tip: tip,
          direction: unitDir,
          perp: perp,
          length: length,
        );
      case ArrowheadStyle.circle:
        return _circleArrowhead(tip: tip, direction: unitDir, length: length);
      case ArrowheadStyle.diamond:
        return _diamondArrowhead(
          tip: tip,
          direction: unitDir,
          perp: perp,
          length: length,
          width: width,
        );
      case ArrowheadStyle.invertedTriangle:
        return _triangleArrowhead(
          tip: tip,
          direction: -unitDir,
          perp: perp,
          length: length,
          width: width,
        );
      case ArrowheadStyle.verticalLine:
        return _verticalLineArrowhead(tip: tip, perp: perp, width: width);
    }
  }

  static List<RenderPathCommand> _standardArrowhead({
    required DrawPoint tip,
    required DrawPoint direction,
    required DrawPoint perp,
    required double length,
    required double width,
  }) {
    final base = tip - direction * length;
    final left = base + perp * (width / 2);
    final right = base - perp * (width / 2);
    return <RenderPathCommand>[
      RenderMoveTo(tip),
      RenderLineTo(left),
      RenderMoveTo(tip),
      RenderLineTo(right),
    ];
  }

  static List<RenderPathCommand> _triangleArrowhead({
    required DrawPoint tip,
    required DrawPoint direction,
    required DrawPoint perp,
    required double length,
    required double width,
  }) {
    final base = tip - direction * length;
    final left = base + perp * (width / 2);
    final right = base - perp * (width / 2);
    return <RenderPathCommand>[
      RenderMoveTo(tip),
      RenderLineTo(left),
      RenderLineTo(right),
      const RenderClosePath(),
    ];
  }

  static List<RenderPathCommand> _squareArrowhead({
    required DrawPoint tip,
    required DrawPoint direction,
    required DrawPoint perp,
    required double length,
  }) {
    final side = length * 0.6;
    final half = side / 2;
    final center = tip - direction * half;
    final corner1 = center + perp * half + direction * half;
    final corner2 = center - perp * half + direction * half;
    final corner3 = center - perp * half - direction * half;
    final corner4 = center + perp * half - direction * half;
    return <RenderPathCommand>[
      RenderMoveTo(corner1),
      RenderLineTo(corner2),
      RenderLineTo(corner3),
      RenderLineTo(corner4),
      const RenderClosePath(),
    ];
  }

  static List<RenderPathCommand> _circleArrowhead({
    required DrawPoint tip,
    required DrawPoint direction,
    required double length,
  }) {
    final radius = length * 0.3;
    final center = tip - direction * radius;
    final control = radius * _kappa;
    final left = DrawPoint(x: center.x - radius, y: center.y);
    final top = DrawPoint(x: center.x, y: center.y - radius);
    final right = DrawPoint(x: center.x + radius, y: center.y);
    final bottom = DrawPoint(x: center.x, y: center.y + radius);
    return <RenderPathCommand>[
      RenderMoveTo(right),
      RenderCubicTo(
        control1: DrawPoint(x: right.x, y: right.y + control),
        control2: DrawPoint(x: bottom.x + control, y: bottom.y),
        end: bottom,
      ),
      RenderCubicTo(
        control1: DrawPoint(x: bottom.x - control, y: bottom.y),
        control2: DrawPoint(x: left.x, y: left.y + control),
        end: left,
      ),
      RenderCubicTo(
        control1: DrawPoint(x: left.x, y: left.y - control),
        control2: DrawPoint(x: top.x - control, y: top.y),
        end: top,
      ),
      RenderCubicTo(
        control1: DrawPoint(x: top.x + control, y: top.y),
        control2: DrawPoint(x: right.x, y: right.y - control),
        end: right,
      ),
      const RenderClosePath(),
    ];
  }

  static List<RenderPathCommand> _diamondArrowhead({
    required DrawPoint tip,
    required DrawPoint direction,
    required DrawPoint perp,
    required double length,
    required double width,
  }) {
    final base = tip - direction * length;
    final mid = tip - direction * (length / 2);
    final left = mid + perp * (width / 2);
    final right = mid - perp * (width / 2);
    return <RenderPathCommand>[
      RenderMoveTo(tip),
      RenderLineTo(left),
      RenderLineTo(base),
      RenderLineTo(right),
      const RenderClosePath(),
    ];
  }

  static List<RenderPathCommand> _verticalLineArrowhead({
    required DrawPoint tip,
    required DrawPoint perp,
    required double width,
  }) {
    final half = width / 2;
    final left = tip + perp * half;
    final right = tip - perp * half;
    return <RenderPathCommand>[RenderMoveTo(left), RenderLineTo(right)];
  }

  static double _arrowheadInset(ArrowheadStyle style, double strokeWidth) {
    if (strokeWidth <= 0) {
      return 0;
    }
    final length = strokeWidth * 4 + 12;
    switch (style) {
      case ArrowheadStyle.circle:
      case ArrowheadStyle.square:
        return length * 0.6;
      case ArrowheadStyle.triangle:
      case ArrowheadStyle.diamond:
        return length;
      case ArrowheadStyle.none:
      case ArrowheadStyle.standard:
      case ArrowheadStyle.verticalLine:
      case ArrowheadStyle.invertedTriangle:
        return 0;
    }
  }

  static List<DrawPoint> _applyInsets({
    required List<DrawPoint> points,
    required double startInset,
    required double endInset,
  }) {
    if (points.length < 2 || (startInset <= 0 && endInset <= 0)) {
      return points;
    }

    var adjusted = points;
    if (startInset > 0) {
      adjusted = _insetFromStart(adjusted, startInset);
      if (adjusted.length < 2) {
        return adjusted;
      }
    }
    if (endInset > 0) {
      adjusted = _insetFromEnd(adjusted, endInset);
    }
    return adjusted;
  }

  static List<DrawPoint> _insetFromStart(List<DrawPoint> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var index = 0; index < points.length - 1; index += 1) {
      final segment = points[index + 1] - points[index];
      final segmentLength = segment.distance(DrawPoint.zero);
      if (segmentLength <= 0) {
        continue;
      }
      if (remainingInset < segmentLength) {
        final unit = segment / segmentLength;
        final newStart = points[index] + unit * remainingInset;
        return <DrawPoint>[newStart, ...points.sublist(index + 1)];
      }
      remainingInset -= segmentLength;
    }

    return <DrawPoint>[points.last];
  }

  static List<DrawPoint> _insetFromEnd(List<DrawPoint> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var index = points.length - 1; index > 0; index -= 1) {
      final segment = points[index - 1] - points[index];
      final segmentLength = segment.distance(DrawPoint.zero);
      if (segmentLength <= 0) {
        continue;
      }
      if (remainingInset < segmentLength) {
        final unit = segment / segmentLength;
        final newEnd = points[index] + unit * remainingInset;
        return <DrawPoint>[...points.sublist(0, index), newEnd];
      }
      remainingInset -= segmentLength;
    }

    return <DrawPoint>[points.first];
  }

  static DrawPoint? _normalize(DrawPoint vector) {
    final length = vector.distance(DrawPoint.zero);
    if (!length.isFinite || length <= 0) {
      return null;
    }
    return vector / length;
  }
}

extension on DrawPoint {
  DrawPoint operator *(double scalar) =>
      DrawPoint(x: x * scalar, y: y * scalar);

  DrawPoint operator /(double scalar) =>
      DrawPoint(x: x / scalar, y: y / scalar);
}
