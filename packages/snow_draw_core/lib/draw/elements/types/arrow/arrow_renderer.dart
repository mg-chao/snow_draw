import 'dart:math' as math;
import 'dart:ui';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowRenderer extends ElementTypeRenderer {
  const ArrowRenderer();

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      throw StateError(
        'ArrowRenderer can only render ArrowData (got ${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 || data.strokeWidth <= 0) {
      return;
    }

    final localPoints = ArrowGeometry.resolveLocalPoints(
      rect: rect,
      normalizedPoints: data.points,
    );
    if (localPoints.length < 2) {
      return;
    }

    // Calculate insets to prevent shaft from penetrating closed arrowheads
    final startInset = ArrowGeometry.calculateArrowheadInset(
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final endInset = ArrowGeometry.calculateArrowheadInset(
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final startDirectionOffset =
        ArrowGeometry.calculateArrowheadDirectionOffset(
          style: data.startArrowhead,
          strokeWidth: data.strokeWidth,
        );
    final endDirectionOffset = ArrowGeometry.calculateArrowheadDirectionOffset(
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );

    final shaftPath = ArrowGeometry.buildShaftPath(
      points: localPoints,
      arrowType: data.arrowType,
      startInset: startInset,
      endInset: endInset,
    );

    // Build arrowhead paths
    final arrowheadPaths = _buildArrowheadPaths(
      localPoints,
      data,
      startInset: startInset,
      endInset: endInset,
      startDirectionOffset: startDirectionOffset,
      endDirectionOffset: endDirectionOffset,
    );

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = data.color.withValues(alpha: strokeOpacity)
      ..isAntiAlias = true;

    // Combine shaft and arrowheads into a single path to prevent transparency
    // overlap
    _drawCombinedArrow(
      canvas,
      shaftPath,
      arrowheadPaths,
      strokePaint,
      data.strokeStyle,
      data,
    );

    canvas.restore();
  }

  void _drawCombinedArrow(
    Canvas canvas,
    Path shaftPath,
    List<Path> arrowheadPaths,
    Paint strokePaint,
    StrokeStyle strokeStyle,
    ArrowData data,
  ) {
    // Combine all paths into one to prevent transparency overlap issues
    final combinedPath = Path();

    if (strokeStyle == StrokeStyle.solid) {
      combinedPath.addPath(shaftPath, Offset.zero);
      for (final arrowheadPath in arrowheadPaths) {
        combinedPath.addPath(arrowheadPath, Offset.zero);
      }
      canvas.drawPath(combinedPath, strokePaint);
      return;
    }

    if (strokeStyle == StrokeStyle.dashed) {
      final dashLength = (8 + data.strokeWidth * 1.5).clamp(6.0, 16.0);
      final gapLength = (5 + data.strokeWidth * 1).clamp(4.0, 10.0);
      final dashedShaft = _buildDashedPath(shaftPath, dashLength, gapLength);
      combinedPath.addPath(dashedShaft, Offset.zero);
      for (final arrowheadPath in arrowheadPaths) {
        combinedPath.addPath(arrowheadPath, Offset.zero);
      }
      canvas.drawPath(combinedPath, strokePaint);
      return;
    }

    // Dotted style - dots are filled circles, so we need different paint
    final dotSpacing = math.max(4, data.strokeWidth * 2.5).toDouble();
    final dotRadius = math.max(1, data.strokeWidth / 2).toDouble();
    final dottedShaft = _buildDottedPath(shaftPath, dotSpacing, dotRadius);
    combinedPath.addPath(dottedShaft, Offset.zero);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokePaint.color
      ..isAntiAlias = true;
    canvas.drawPath(combinedPath, dotPaint);

    // Draw arrowheads with stroke paint for dotted style
    for (final arrowheadPath in arrowheadPaths) {
      canvas.drawPath(arrowheadPath, strokePaint);
    }
  }

  List<Path> _buildArrowheadPaths(
    List<Offset> points,
    ArrowData data, {
    required double startInset,
    required double endInset,
    required double startDirectionOffset,
    required double endDirectionOffset,
  }) {
    final paths = <Path>[];

    if (points.length < 2 || data.strokeWidth <= 0) {
      return paths;
    }

    final startDirection = ArrowGeometry.resolveStartDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: startDirectionOffset,
    );
    if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
      final path = ArrowGeometry.buildArrowheadPath(
        tip: points.first,
        direction: startDirection,
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );
      paths.add(path);
    }

    final endDirection = ArrowGeometry.resolveEndDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: endDirectionOffset,
    );
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      final path = ArrowGeometry.buildArrowheadPath(
        tip: points.last,
        direction: endDirection,
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
      );
      paths.add(path);
    }

    return paths;
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
}
