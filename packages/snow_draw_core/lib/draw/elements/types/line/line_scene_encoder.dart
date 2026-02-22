import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/hit_test_geometry.dart';
import '../shared/scene_encoder_path_utils.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'line_data.dart';

/// Encodes line elements into backend-agnostic scene primitives.
final class LineSceneEncoder extends TypedElementSceneEncoder<LineData> {
  /// Creates a line scene encoder.
  const LineSceneEncoder();
  static const _defaultPoints = <DrawPoint>[
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required LineData data,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
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
      return emptyRenderScene;
    }

    final path = _buildPath(element.rect, data);
    final localBuilder = SceneBuilder();
    if (fillVisible) {
      final closedPath = closeRenderPathIfNeeded(path);
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
          angleRadians: defaultHatchAngleRadians,
          pattern: resolveHatchPattern(data.fillStyle),
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

    return composeElementScene(
      element: element,
      localScene: localBuilder.build(),
    );
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
