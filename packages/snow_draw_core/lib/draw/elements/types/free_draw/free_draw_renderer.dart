import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart'
    show Alignment, GradientRotation, LinearGradient;
import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_renderer.dart';
import 'free_draw_data.dart';
import 'free_draw_visual_cache.dart';

class FreeDrawRenderer extends ElementTypeRenderer {
  const FreeDrawRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _lineShaderCache = LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );

  /// Clears the static shader cache.
  ///
  /// Call when switching documents or under memory pressure.
  static void clearCaches() {
    _lineShaderCache.clear();
  }

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawRenderer can only render FreeDrawData '
        '(got ${data.runtimeType})',
      );
    }
    final _ = scaleFactor;

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 && fillOpacity <= 0) {
      return;
    }

    final cached = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );
    if (cached.pointCount < 2) {
      return;
    }

    // Try to replay a previously recorded Picture for this
    // element. This avoids re-issuing potentially hundreds of
    // draw calls for completed strokes.
    final existingPicture = cached.getCachedPicture(opacity);
    if (existingPicture != null) {
      canvas.save();
      if (element.rotation != 0) {
        canvas
          ..translate(rect.centerX, rect.centerY)
          ..rotate(element.rotation)
          ..translate(-rect.centerX, -rect.centerY);
      }
      canvas
        ..translate(rect.minX, rect.minY)
        ..drawPicture(existingPicture)
        ..restore();
      return;
    }

    // Record draw commands into a Picture for future reuse.
    final recorder = PictureRecorder();
    final recordCanvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, rect.width, rect.height),
    );

    _renderToCanvas(
      canvas: recordCanvas,
      data: data,
      rect: rect,
      cached: cached,
      strokeOpacity: strokeOpacity,
      fillOpacity: fillOpacity,
    );

    final picture = recorder.endRecording();
    cached.setCachedPicture(picture, opacity);

    // Draw the just-recorded picture.
    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas
      ..translate(rect.minX, rect.minY)
      ..drawPicture(picture)
      ..restore();
  }

  /// Issues the actual fill + stroke draw commands.
  ///
  /// Called once to record into a [PictureRecorder]; subsequent
  /// frames replay the recorded [Picture] directly.
  void _renderToCanvas({
    required Canvas canvas,
    required FreeDrawData data,
    required DrawRect rect,
    required FreeDrawVisualEntry cached,
    required double strokeOpacity,
    required double fillOpacity,
  }) {
    final shouldFill =
        fillOpacity > 0 && _isClosed(data, rect) && cached.pointCount > 2;

    if (shouldFill) {
      final fillPath = Path()
        ..addPath(cached.path, Offset.zero)
        ..close();
      if (data.fillStyle == FillStyle.solid) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = data.fillColor.withValues(alpha: fillOpacity)
          ..isAntiAlias = true;
        canvas.drawPath(fillPath, paint);
      } else {
        final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 4.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        final fillColor = data.fillColor.withValues(alpha: fillOpacity);
        final fillPaint = _buildLineFillPaint(
          spacing: spacing,
          lineWidth: fillLineWidth,
          angle: _lineFillAngle,
          color: fillColor,
        );
        canvas.drawPath(fillPath, fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          final crossPaint = _buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: fillColor,
          );
          canvas.drawPath(fillPath, crossPaint);
        }
      }
    }

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      final strokeColor = data.color.withValues(alpha: strokeOpacity);

      if (data.strokeStyle == StrokeStyle.dotted) {
        final dottedPath = cached.dottedPath;
        if (dottedPath != null) {
          final dotPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = strokeColor
            ..isAntiAlias = true;
          canvas.drawPath(dottedPath, dotPaint);
        }
      } else if (data.strokeStyle == StrokeStyle.dashed) {
        final dashedPath = cached.strokePath;
        if (dashedPath != null) {
          final strokePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = data.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor
            ..isAntiAlias = true;
          canvas.drawPath(dashedPath, strokePaint);
        }
      } else {
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = data.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = strokeColor
          ..isAntiAlias = true;
        canvas.drawPath(cached.path, strokePaint);
      }
    }
  }

  bool _isClosed(FreeDrawData data, DrawRect rect) {
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

  Paint _buildLineFillPaint({
    required double spacing,
    required double lineWidth,
    required double angle,
    required Color color,
  }) => Paint()
    ..style = PaintingStyle.fill
    ..shader = _lineShaderCache.getOrCreate(
      _LineShaderKey(spacing: spacing, lineWidth: lineWidth, angle: angle),
      () => _buildLineShader(
        spacing: spacing,
        lineWidth: lineWidth,
        angle: angle,
      ),
    )
    ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
    ..isAntiAlias = true;

  Shader _buildLineShader({
    required double spacing,
    required double lineWidth,
    required double angle,
  }) {
    final safeSpacing = spacing <= 0 ? 1.0 : spacing;
    final lineStop = (lineWidth / safeSpacing).clamp(0.0, 1.0);
    final cosAngle = math.cos(angle).abs();
    final adjustedSpacing = cosAngle > 0.01
        ? safeSpacing / cosAngle
        : safeSpacing;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      tileMode: TileMode.repeated,
      colors: const [
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0.0, lineStop, lineStop, 1.0],
      transform: GradientRotation(angle),
    ).createShader(Rect.fromLTWH(0, 0, adjustedSpacing, adjustedSpacing));
  }
}

@immutable
class _LineShaderKey {
  _LineShaderKey({
    required double spacing,
    required double lineWidth,
    required this.angle,
  }) : spacing = _quantize(spacing),
       lineWidth = _quantize(lineWidth);

  final double spacing;
  final double lineWidth;
  final double angle;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LineShaderKey &&
          other.spacing == spacing &&
          other.lineWidth == lineWidth &&
          other.angle == angle;

  @override
  int get hashCode => Object.hash(spacing, lineWidth, angle);
}
