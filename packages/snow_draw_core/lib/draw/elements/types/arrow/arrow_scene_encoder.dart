import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/hit_test_geometry.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

/// Encodes arrow elements into backend-agnostic scene primitives.
final class ArrowSceneEncoder extends TypedElementSceneEncoder<ArrowData> {
  /// Creates an arrow scene encoder.
  const ArrowSceneEncoder();

  static const _kappa = 0.5522847498307936;

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required ArrowData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    final strokeColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeVisible =
        isArgbVisible(strokeColorArgb) && data.strokeWidth > 0;
    if (!strokeVisible) {
      return emptyRenderScene;
    }

    final geometry = ArrowGeometryDescriptor(data: data, rect: element.rect);
    final insetPoints = _toCenterLocalPoints(
      points: geometry.insetDrawPoints,
      rect: element.rect,
    );
    if (insetPoints.length < 2) {
      return emptyRenderScene;
    }

    final shaftPath = _buildShaftPath(
      points: insetPoints,
      arrowType: data.arrowType,
    );
    final arrowheadPath = _buildArrowheadsPath(
      points: insetPoints,
      startDirection: geometry.startDirectionPoint,
      endDirection: geometry.endDirectionPoint,
      data: data,
    );

    final localScene = SceneBuilder()
      ..addPathStroke(
        path: shaftPath,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: RenderStrokeCap.round,
        strokeJoin: RenderStrokeJoin.round,
        dashPattern: resolveStrokeDashPattern(
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

    return composeElementScene(
      element: element,
      localScene: localScene.build(),
    );
  }

  static List<DrawPoint> _toCenterLocalPoints({
    required List<DrawPoint> points,
    required DrawRect rect,
  }) {
    final offsetX = rect.width / 2;
    final offsetY = rect.height / 2;
    return points
        .map((point) => DrawPoint(x: point.x - offsetX, y: point.y - offsetY))
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
    required DrawPoint? startDirection,
    required DrawPoint? endDirection,
    required ArrowData data,
  }) {
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    final commands = <RenderPathCommand>[];
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

  static DrawPoint? _normalize(DrawPoint vector) {
    final length = vector.distance(DrawPoint.zero);
    if (!length.isFinite || length <= 0) {
      return null;
    }
    return vector / length;
  }
}
