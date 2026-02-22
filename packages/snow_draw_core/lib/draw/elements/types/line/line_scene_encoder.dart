import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import '../shared/hit_test_geometry.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'line_data.dart';

/// Encodes line elements into backend-agnostic scene primitives.
final class LineSceneEncoder implements ElementSceneEncoder<LineData> {
  /// Creates a line scene encoder.
  const LineSceneEncoder();
  static const double _lineFillAngle = -math.pi / 4;
  static const _defaultPoints = <DrawPoint>[
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! LineData) {
      throw StateError(
        'LineSceneEncoder can only encode LineData (got ${data.runtimeType})',
      );
    }

    final strokeColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final fillColorArgb = applyElementOpacityToArgb(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeVisible =
        isArgbVisible(strokeColorArgb) && data.strokeWidth > 0;
    final fillVisible = isArgbVisible(fillColorArgb) && _isClosed(data);
    if (!strokeVisible && !fillVisible) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final path = _buildPath(element.rect, data);
    final localBuilder = SceneBuilder();
    if (fillVisible) {
      final closedPath = _closePathIfNeeded(path);
      if (data.fillStyle == FillStyle.solid) {
        localBuilder.addPathFill(path: closedPath, colorArgb: fillColorArgb);
      } else {
        final hatch = resolveStrokeHatchStyle(strokeWidth: data.strokeWidth);
        localBuilder.addHatchPathFill(
          path: closedPath,
          clipBounds: resolveCenteredLocalClipBounds(element.rect),
          colorArgb: fillColorArgb,
          lineWidth: hatch.lineWidth,
          spacing: hatch.spacing,
          angleRadians: _lineFillAngle,
          pattern: data.fillStyle == FillStyle.crossLine
              ? RenderHatchPattern.crossLine
              : RenderHatchPattern.line,
        );
      }
    }
    if (strokeVisible) {
      localBuilder.addPathStroke(
        path: path,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: RenderStrokeCap.round,
        strokeJoin: RenderStrokeJoin.round,
        dashPattern: resolveStrokeDashPattern(
          strokeStyle: data.strokeStyle,
          strokeWidth: data.strokeWidth,
        ),
      );
    }

    final sceneBuilder = SceneBuilder()
      ..addTransform(
        child: localBuilder.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return sceneBuilder.build(cullRect: element.rect);
  }

  static bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;

  static RenderPath _buildPath(DrawRect rect, LineData data) {
    final points = _resolveCenterLocalPoints(rect: rect, data: data);
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }

    final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
    if (data.arrowType == ArrowType.curved && points.length > 2) {
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

    for (final point in points.skip(1)) {
      commands.add(RenderLineTo(point));
    }
    return RenderPath(commands);
  }

  static RenderPath _closePathIfNeeded(RenderPath path) {
    if (path.commands.isEmpty || path.commands.last is RenderClosePath) {
      return path;
    }
    return RenderPath(<RenderPathCommand>[
      ...path.commands,
      const RenderClosePath(),
    ]);
  }

  static List<DrawPoint> _resolveCenterLocalPoints({
    required DrawRect rect,
    required LineData data,
  }) {
    final source = data.points.length >= 2 ? data.points : _defaultPoints;
    final width = rect.width;
    final height = rect.height;
    final center = rect.center;
    return source
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width - center.x,
            y: rect.minY + point.y * height - center.y,
          ),
        )
        .toList(growable: false);
  }
}
