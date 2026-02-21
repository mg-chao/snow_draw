import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'line_data.dart';

/// Encodes line elements into backend-agnostic scene primitives.
final class LineSceneEncoder implements ElementSceneEncoder<LineData> {
  /// Creates a line scene encoder.
  const LineSceneEncoder();
  static const double _lineFillAngle = -math.pi / 4;
  static const _lineToSpacingRatio = 4.0;

  static const _defaultPoints = <DrawPoint>[
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

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
    if (data is! LineData) {
      throw StateError(
        'LineSceneEncoder can only encode LineData (got ${data.runtimeType})',
      );
    }

    final strokeColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final fillColorArgb = _applyElementOpacity(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeVisible = _alphaOf(strokeColorArgb) > 0 && data.strokeWidth > 0;
    final fillVisible = _alphaOf(fillColorArgb) > 0 && _isClosed(data);
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
        final hatch = _resolveHatchStyle(strokeWidth: data.strokeWidth);
        localBuilder.addHatchPathFill(
          path: closedPath,
          clipBounds: _localClipBounds(element.rect),
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
        dashPattern: _dashPatternFor(
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

  static bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;

  static List<double>? _dashPatternFor({
    required StrokeStyle strokeStyle,
    required double strokeWidth,
  }) => switch (strokeStyle) {
    StrokeStyle.solid => null,
    StrokeStyle.dashed => <double>[strokeWidth * 2.0, strokeWidth * 2.0 * 1.2],
    StrokeStyle.dotted => <double>[
      (strokeWidth * 0.01).clamp(0.01, double.infinity),
      (strokeWidth * 2.0).clamp(0.01, double.infinity),
    ],
  };

  static RenderPath _buildPath(DrawRect rect, LineData data) {
    final points = _resolveCenterLocalPoints(rect: rect, data: data);
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }

    final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
    if (data.arrowType == ArrowType.curved && points.length > 2) {
      for (var index = 0; index < points.length - 1; index += 1) {
        final segment = _buildCubicSegment(points, index);
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

  static _CubicSegment _buildCubicSegment(List<DrawPoint> points, int index) {
    final p0 = index == 0 ? points[index] : points[index - 1];
    final p1 = points[index];
    final p2 = points[index + 1];
    final p3 = index + 2 < points.length
        ? points[index + 2]
        : points[index + 1];

    const tension = 1.0;
    final control1 = DrawPoint(
      x: p1.x + (p2.x - p0.x) * (tension / 6),
      y: p1.y + (p2.y - p0.y) * (tension / 6),
    );
    final control2 = DrawPoint(
      x: p2.x - (p3.x - p1.x) * (tension / 6),
      y: p2.y - (p3.y - p1.y) * (tension / 6),
    );
    return _CubicSegment(control1: control1, control2: control2, end: p2);
  }

  static DrawRect _localClipBounds(DrawRect rect) => DrawRect(
    minX: -rect.width / 2,
    minY: -rect.height / 2,
    maxX: rect.width / 2,
    maxY: rect.height / 2,
  );

  static ({double lineWidth, double spacing}) _resolveHatchStyle({
    required double strokeWidth,
  }) {
    final lineWidth = (1 + (strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    final spacing = (lineWidth * _lineToSpacingRatio).clamp(3.0, 18.0);
    return (lineWidth: lineWidth, spacing: spacing);
  }
}

final class _CubicSegment {
  const _CubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final DrawPoint control1;
  final DrawPoint control2;
  final DrawPoint end;
}
