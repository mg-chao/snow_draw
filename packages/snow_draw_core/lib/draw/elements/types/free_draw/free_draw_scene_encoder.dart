import 'dart:math' as math;

import '../../../config/draw_config.dart';
import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'free_draw_data.dart';

/// Encodes free-draw elements into backend-agnostic scene primitives.
final class FreeDrawSceneEncoder implements ElementSceneEncoder<FreeDrawData> {
  /// Creates a free-draw scene encoder.
  const FreeDrawSceneEncoder();
  static const double _lineFillAngle = -math.pi / 4;
  static const _lineToSpacingRatio = 4.0;

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
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawSceneEncoder can only encode FreeDrawData '
        '(got ${data.runtimeType})',
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
    final fillVisible = _alphaOf(fillColorArgb) > 0;
    final shouldFill =
        fillVisible &&
        _isClosed(data: data, rect: element.rect) &&
        data.points.length > 2;

    if (!strokeVisible && !shouldFill) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final points = _resolveCenterLocalPoints(rect: element.rect, data: data);
    if (points.length < 2) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final path = _buildSmoothPath(points);
    final localScene = SceneBuilder();
    if (shouldFill) {
      final closedPath = _closedPath(path);
      if (data.fillStyle == FillStyle.solid) {
        localScene.addPathFill(path: closedPath, colorArgb: fillColorArgb);
      } else {
        final hatch = _resolveHatchStyle(strokeWidth: data.strokeWidth);
        localScene.addHatchPathFill(
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
      localScene.addPathStroke(
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
    required FreeDrawData data,
  }) {
    final width = rect.width;
    final height = rect.height;
    final center = rect.center;
    return data.points
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width - center.x,
            y: rect.minY + point.y * height - center.y,
            pressure: point.pressure,
          ),
        )
        .toList(growable: false);
  }

  static RenderPath _buildSmoothPath(List<DrawPoint> points) {
    if (points.length < 2) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    if (points.length == 2) {
      return RenderPath(<RenderPathCommand>[
        RenderMoveTo(points.first),
        RenderLineTo(points.last),
      ]);
    }

    final closed = _sameLocation(points.first, points.last);
    final source = closed ? points.sublist(0, points.length - 1) : points;
    final smoothed = _smoothPoints(source, closed: closed);
    if (smoothed.isEmpty) {
      return const RenderPath(<RenderPathCommand>[]);
    }

    final commands = <RenderPathCommand>[RenderMoveTo(smoothed.first)];
    if (closed) {
      _addClosedSegments(commands: commands, points: smoothed);
      commands.add(const RenderClosePath());
      return RenderPath(commands);
    }
    _addOpenSegments(commands: commands, points: smoothed);
    return RenderPath(commands);
  }

  static List<DrawPoint> _smoothPoints(
    List<DrawPoint> points, {
    required bool closed,
  }) {
    if (points.length < 3) {
      return points;
    }

    const iterations = 3;
    final count = points.length;
    final lastIndex = count - 1;

    var src = List<DrawPoint>.of(points);
    var dst = List<DrawPoint>.filled(count, DrawPoint.zero);

    for (var iteration = 0; iteration < iterations; iteration += 1) {
      if (closed) {
        for (var index = 0; index <= lastIndex; index += 1) {
          final prev = src[(index - 1 + count) % count];
          final current = src[index];
          final next = src[(index + 1) % count];
          dst[index] = DrawPoint(
            x: (prev.x + current.x * 2 + next.x) * 0.25,
            y: (prev.y + current.y * 2 + next.y) * 0.25,
          );
        }
      } else {
        dst[0] = src[0];
        dst[lastIndex] = src[lastIndex];
        for (var index = 1; index < lastIndex; index += 1) {
          final prev = src[index - 1];
          final current = src[index];
          final next = src[index + 1];
          dst[index] = DrawPoint(
            x: (prev.x + current.x * 2 + next.x) * 0.25,
            y: (prev.y + current.y * 2 + next.y) * 0.25,
          );
        }
      }

      final temp = src;
      src = dst;
      dst = temp;
    }

    return src;
  }

  static void _addOpenSegments({
    required List<RenderPathCommand> commands,
    required List<DrawPoint> points,
  }) {
    const tension = 0.5;
    final count = points.length;
    if (count < 2) {
      return;
    }

    final phantomFirst = points[0] + (points[0] - points[1]);
    final phantomLast =
        points[count - 1] + (points[count - 1] - points[count - 2]);

    for (var index = 0; index < count - 1; index += 1) {
      final p0 = index == 0 ? phantomFirst : points[index - 1];
      final p1 = points[index];
      final p2 = points[index + 1];
      final p3 = index + 2 < count ? points[index + 2] : phantomLast;
      commands.add(
        RenderCubicTo(
          control1: p1 + (p2 - p0) * (tension / 6),
          control2: p2 - (p3 - p1) * (tension / 6),
          end: p2,
        ),
      );
    }
  }

  static void _addClosedSegments({
    required List<RenderPathCommand> commands,
    required List<DrawPoint> points,
  }) {
    const tension = 0.5;
    final count = points.length;
    for (var index = 0; index < count; index += 1) {
      final p0 = points[(index - 1 + count) % count];
      final p1 = points[index];
      final p2 = points[(index + 1) % count];
      final p3 = points[(index + 2) % count];
      commands.add(
        RenderCubicTo(
          control1: p1 + (p2 - p0) * (tension / 6),
          control2: p2 - (p3 - p1) * (tension / 6),
          end: p2,
        ),
      );
    }
  }

  static RenderPath _closedPath(RenderPath path) {
    if (path.commands.isEmpty || path.commands.last is RenderClosePath) {
      return path;
    }
    return RenderPath(<RenderPathCommand>[
      ...path.commands,
      const RenderClosePath(),
    ]);
  }

  static bool _sameLocation(DrawPoint a, DrawPoint b) =>
      a.x == b.x && a.y == b.y;

  static bool _isClosed({required FreeDrawData data, required DrawRect rect}) {
    if (data.points.length < 3) {
      return false;
    }

    final first = data.points.first;
    final last = data.points.last;
    if (first == last) {
      return true;
    }

    const tolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= tolerance * tolerance;
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

extension on DrawPoint {
  DrawPoint operator *(double scalar) =>
      DrawPoint(x: x * scalar, y: y * scalar);
}
