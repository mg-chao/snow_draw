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
import 'free_draw_path_utils.dart';

class FreeDrawRenderer extends ElementTypeRenderer {
  const FreeDrawRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _lineShaderCache = LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );
  static final _visualCache = _FreeDrawVisualCache(maxEntries: 256);

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

    final cached = _visualCache.resolve(element: element, data: data);
    if (cached.pointCount < 2) {
      return;
    }

    final shouldFill =
        fillOpacity > 0 && _isClosed(data, rect) && cached.pointCount > 2;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

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
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = data.color.withValues(alpha: strokeOpacity)
        ..isAntiAlias = true;

      if (data.strokeStyle == StrokeStyle.dotted) {
        final dottedPath = cached.dottedPath;
        if (dottedPath != null) {
          final dotPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = strokePaint.color
            ..isAntiAlias = true;
          canvas.drawPath(dottedPath, dotPaint);
        }
      } else {
        final combinedPath = cached.strokePath;
        if (combinedPath != null) {
          canvas.drawPath(combinedPath, strokePaint);
        }
      }
    }

    canvas.restore();
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

class _FreeDrawVisualCacheEntry {
  _FreeDrawVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.path,
    required this.strokePath,
    required this.dottedPath,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final int pointCount;
  final Path path;
  final Path? strokePath;
  final Path? dottedPath;

  bool matches(FreeDrawData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}

class _FreeDrawVisualCache {
  _FreeDrawVisualCache({required int maxEntries})
    : _entries = LruCache<String, _FreeDrawVisualCacheEntry>(
        maxEntries: maxEntries,
      );

  final LruCache<String, _FreeDrawVisualCacheEntry> _entries;

  _FreeDrawVisualCacheEntry resolve({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries.get(id);
    if (existing != null && existing.matches(data, width, height)) {
      return existing;
    }

    final entry = _buildEntry(element: element, data: data);
    _entries.put(id, entry);
    return entry;
  }

  _FreeDrawVisualCacheEntry _buildEntry({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final rect = element.rect;
    final localPoints = resolveFreeDrawLocalPoints(
      rect: rect,
      points: data.points,
    );
    if (localPoints.length < 2) {
      return _FreeDrawVisualCacheEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        pointCount: localPoints.length,
        path: Path(),
        strokePath: null,
        dottedPath: null,
      );
    }

    final basePath = buildFreeDrawSmoothPath(localPoints);

    Path? strokePath;
    Path? dottedPath;

    if (data.strokeWidth > 0) {
      switch (data.strokeStyle) {
        case StrokeStyle.solid:
          strokePath = basePath;
        case StrokeStyle.dashed:
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          strokePath = _buildDashedPath(basePath, dashLength, gapLength);
        case StrokeStyle.dotted:
          final dotSpacing = data.strokeWidth * 2.0;
          final dotRadius = data.strokeWidth * 0.5;
          dottedPath = _buildDottedPath(basePath, dotSpacing, dotRadius);
      }
    }

    return _FreeDrawVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      pointCount: localPoints.length,
      path: basePath,
      strokePath: strokePath,
      dottedPath: dottedPath,
    );
  }
}

Path _buildDashedPath(Path basePath, double dashLength, double gapLength) {
  final dashed = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dashLength, metric.length);
      dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next + gapLength;
    }
  }
  return dashed;
}

Path _buildDottedPath(Path basePath, double dotSpacing, double dotRadius) {
  final dotted = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        dotted.addOval(
          Rect.fromCircle(center: tangent.position, radius: dotRadius),
        );
      }
      distance += dotSpacing;
    }
  }
  return dotted;
}
