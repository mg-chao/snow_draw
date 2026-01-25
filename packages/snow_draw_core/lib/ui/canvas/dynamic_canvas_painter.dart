import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../draw/elements/types/arrow/arrow_data.dart';
import '../../draw/elements/types/arrow/arrow_points.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/render/element_renderer.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/edit_transform.dart';
import '../../draw/types/snap_guides.dart';
import '../../draw/utils/selection_calculator.dart';
import 'render_keys.dart';

/// Dynamic canvas painter.
///
/// Renders top-layer elements and interaction overlays.
/// This layer updates frequently during user interaction.
@immutable
class DynamicCanvasPainter extends CustomPainter {
  const DynamicCanvasPainter({
    required this.renderKey,
    required this.stateView,
  });

  /// Render key for precise repaint decisions.
  final DynamicCanvasRenderKey renderKey;

  /// Precomputed effective state view (needed for paint).
  final DrawStateView stateView;

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    final camera = state.application.view.camera;
    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    // Draw elements at or above the selected element to preserve z-order.
    _drawDynamicElements(canvas: canvas, size: size, scale: scale);

    // Draw creating element preview above the static layer.
    final creatingElement = renderKey.creatingElement;
    if (creatingElement != null) {
      final previewElement = creatingElement.element.copyWith(
        rect: creatingElement.currentRect,
      );
      elementRenderer.renderElement(
        canvas: canvas,
        element: previewElement,
        scaleFactor: scale,
        registry: renderKey.elementRegistry,
        locale: renderKey.locale,
      );
    }

    // Draw snapping guides.
    final snapGuides = renderKey.snapGuides;
    if (snapGuides.isNotEmpty && renderKey.snapConfig.showGuides) {
      _drawSnapGuides(
        canvas: canvas,
        guides: snapGuides,
        scale: scale,
      );
    }

    // Draw hover outline when selection is possible.
    final hoveredElementId = renderKey.hoveredElementId;
    if (hoveredElementId != null &&
        !renderKey.selectedIds.contains(hoveredElementId)) {
      final hoveredElement = state.domain.document.getElementById(
        hoveredElementId,
      );
      if (hoveredElement != null) {
        final effectiveElement = stateView.effectiveElement(hoveredElement);
        elementRenderer.renderSelectionOutline(
          canvas: canvas,
          bounds: effectiveElement.rect,
          scaleFactor: scale,
          config: renderKey.hoverSelectionConfig,
          rotation: effectiveElement.rotation,
          rotationCenter: effectiveElement.center,
          dashed: false,
        );
      }
    }

    // Draw selection overlay.
    final effectiveSelection = renderKey.effectiveSelection;
    if (effectiveSelection.hasSelection) {
      final bounds = effectiveSelection.bounds;
      if (bounds != null) {
        final rotationCenter = effectiveSelection.center ?? bounds.center;

        // Multi-select: render a per-element outline first (no control points).
        final selectedIds = renderKey.selectedIds;
        if (selectedIds.length > 1) {
          for (final element in stateView.selectedElements) {
            final effectiveElement = stateView.effectiveElement(element);
            elementRenderer.renderSelectionOutline(
              canvas: canvas,
              bounds: effectiveElement.rect,
              scaleFactor: scale,
              config: renderKey.selectionConfig,
              rotation: effectiveElement.rotation,
              rotationCenter: effectiveElement.center,
              dashed: false,
            );
          }
        }

        elementRenderer
          ..renderSelection(
            canvas: canvas,
            bounds: bounds,
            scaleFactor: scale,
            config: renderKey.selectionConfig,
            rotation: effectiveSelection.rotation,
            rotationCenter: rotationCenter,
            dashed: selectedIds.length > 1,
          )
          // Draw rotation handle.
          ..renderRotationHandle(
            canvas: canvas,
            bounds: bounds,
            scaleFactor: scale,
            config: renderKey.selectionConfig,
            rotation: effectiveSelection.rotation,
            rotationCenter: rotationCenter,
          );
      }
    }

    _drawArrowPointOverlay(canvas: canvas, scale: scale);

    // Draw dashed border for a single selected text element.
    if (renderKey.selectedIds.length == 1) {
      final selectedId = renderKey.selectedIds.first;
      final element = state.domain.document.getElementById(selectedId);
      if (element?.data is TextData) {
        final effectiveElement = stateView.effectiveElement(element!);
        elementRenderer.renderSelectionOutline(
          canvas: canvas,
          bounds: effectiveElement.rect,
          scaleFactor: scale,
          config: renderKey.hoverSelectionConfig,
          rotation: effectiveElement.rotation,
          rotationCenter: effectiveElement.center,
        );
      }
    }

    // Draw box-selection overlay.
    final boxSelectionBounds = renderKey.boxSelectionBounds;
    if (boxSelectionBounds != null) {
      // Draw preview borders for elements that would be selected
      _drawBoxSelectionPreview(canvas, boxSelectionBounds, scale);
      // Draw the marquee box
      _drawBoxSelection(canvas, boxSelectionBounds, scale);
    }

    canvas.restore();
  }

  void _drawDynamicElements({
    required Canvas canvas,
    required Size size,
    required double scale,
  }) {
    final dynamicLayerStartIndex = renderKey.dynamicLayerStartIndex;
    if (dynamicLayerStartIndex == null) {
      return;
    }

    final state = stateView.state;
    final document = state.domain.document;
    final camera = renderKey.camera;
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    final visibleElements = document.getElementsInRect(viewportRect)
    ..removeWhere((element) {
      final orderIndex = document.getOrderIndex(element.id) ?? -1;
      return orderIndex < dynamicLayerStartIndex;
    });

    final previewElements = renderKey.previewElementsById;
    if (previewElements.isNotEmpty) {
      final visibleIds = {for (final element in visibleElements) element.id};
      for (final preview in previewElements.values) {
        if (visibleIds.contains(preview.id)) {
          continue;
        }
        final aabb = SelectionCalculator.computeElementWorldAabb(preview);
        if (_rectsIntersect(aabb, viewportRect)) {
          visibleElements.add(preview);
          visibleIds.add(preview.id);
        }
      }
    }

    visibleElements.sort((a, b) {
      final indexA = document.getOrderIndex(a.id) ?? -1;
      final indexB = document.getOrderIndex(b.id) ?? -1;
      return indexA.compareTo(indexB);
    });

    if (previewElements.isEmpty) {
      for (final element in visibleElements) {
        elementRenderer.renderElement(
          canvas: canvas,
          element: element,
          scaleFactor: scale,
          registry: renderKey.elementRegistry,
          locale: renderKey.locale,
        );
      }
      return;
    }

    for (final element in visibleElements) {
      final preview = previewElements[element.id];
      final effectiveElement = preview ?? element;
      if (preview != null) {
        final aabb = SelectionCalculator.computeElementWorldAabb(
          effectiveElement,
        );
        if (!_rectsIntersect(aabb, viewportRect)) {
          continue;
        }
      }
      elementRenderer.renderElement(
        canvas: canvas,
        element: effectiveElement,
        scaleFactor: scale,
        registry: renderKey.elementRegistry,
        locale: renderKey.locale,
      );
    }
  }

  void _drawArrowPointOverlay({
    required Canvas canvas,
    required double scale,
  }) {
    if (renderKey.selectedIds.length != 1) {
      return;
    }
    final selectedId = renderKey.selectedIds.first;
    final element = stateView.state.domain.document.getElementById(selectedId);
    if (element == null || element.data is! ArrowData) {
      return;
    }

    final effectiveElement = stateView.effectiveElement(element);
    final selectionConfig = renderKey.selectionConfig;
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final handleTolerance =
        selectionConfig.interaction.handleTolerance / effectiveScale;
    final loopThreshold = handleTolerance * 1.5;
    final overlay = ArrowPointUtils.buildOverlay(
      element: effectiveElement,
      loopThreshold: loopThreshold,
    );
    if (overlay.turningPoints.isEmpty &&
        overlay.addablePoints.isEmpty &&
        overlay.loopPoints.isEmpty) {
      return;
    }

    final handleSize = selectionConfig.render.controlPointSize / effectiveScale;
    final strokeWidth =
        selectionConfig.render.strokeWidth / effectiveScale;
    final fillColor = selectionConfig.render.cornerFillColor;
    final strokeColor = selectionConfig.render.strokeColor;
    final highlightFill = strokeColor.withValues(alpha: 0.18);
    final highlightStroke = strokeColor.withValues(alpha: 0.95);

    final hoveredHandle = renderKey.hoveredArrowHandle;
    final activeHandle = renderKey.activeArrowHandle;
    final shouldDelete = _shouldShowDeleteIndicator();
    final deletePosition =
        activeHandle == null || !shouldDelete
            ? null
            : _resolveHandlePosition(overlay, activeHandle);

    canvas.save();
    if (effectiveElement.rotation != 0) {
      canvas
        ..translate(effectiveElement.rect.centerX, effectiveElement.rect.centerY)
        ..rotate(effectiveElement.rotation)
        ..translate(-effectiveElement.rect.centerX, -effectiveElement.rect.centerY);
    }
    canvas.translate(effectiveElement.rect.minX, effectiveElement.rect.minY);

    final addableRadius = handleSize * 0.5;
    final turnRadius = handleSize * 0.5;
    final loopOuterRadius = handleSize * 1.0;
    final loopInnerRadius = handleSize * 0.5;
    final hoverOuterRadius = loopOuterRadius;

    final addableStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor.withValues(alpha: 0.35)
      ..isAntiAlias = true;
    final addableFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor.withValues(alpha: 0.18)
      ..isAntiAlias = true;
    final addableStrokePaintHighlighted = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor.withValues(alpha: 0.85)
      ..isAntiAlias = true;
    final addableFillPaintHighlighted = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor.withValues(alpha: 0.55)
      ..isAntiAlias = true;
    final turningFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor.withValues(alpha: 0.90)
      ..isAntiAlias = true;
    final turningStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor
      ..isAntiAlias = true;
    final hoverOuterFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor.withValues(alpha: 0.25)
      ..isAntiAlias = true;

    for (final handle in overlay.addablePoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, hoverOuterFillPaint);
      }
      final fillPaint = isHighlighted ? addableFillPaintHighlighted : addableFillPaint;
      final strokePaint = isHighlighted ? addableStrokePaintHighlighted : addableStrokePaint;
      canvas
        ..drawCircle(center, addableRadius, fillPaint)
        ..drawCircle(center, addableRadius, strokePaint);
    }

    for (final handle in overlay.turningPoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, hoverOuterFillPaint);
      }
      final fillPaint = turningFillPaint;
      final strokePaint = isHighlighted
          ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..color = highlightStroke
            ..isAntiAlias = true)
          : turningStrokePaint;
      canvas
        ..drawCircle(center, turnRadius, fillPaint)
        ..drawCircle(center, turnRadius, strokePaint);
    }

    for (final handle in overlay.loopPoints) {
      final center = _localOffset(effectiveElement.rect, handle.position);
      final isHighlighted = handle == hoveredHandle || handle == activeHandle;
      if (isHighlighted) {
        canvas.drawCircle(center, hoverOuterRadius, hoverOuterFillPaint);
      }
      final radius = handle.kind == ArrowPointKind.loopEnd
          ? loopOuterRadius
          : loopInnerRadius;
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = isHighlighted ? highlightStroke : strokeColor
        ..isAntiAlias = true;

      // Inner loop point (loopStart) has filled style like bend points
      if (handle.kind == ArrowPointKind.loopStart) {
        canvas.drawCircle(center, radius, turningFillPaint);
      }
      canvas.drawCircle(center, radius, strokePaint);
    }

    if (deletePosition != null) {
      final center = _localOffset(effectiveElement.rect, deletePosition);
      final deletePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.4
        ..color = Colors.redAccent
        ..isAntiAlias = true;
      canvas.drawCircle(center, turnRadius * 1.35, deletePaint);
    }

    canvas.restore();
  }

  bool _shouldShowDeleteIndicator() {
    final interaction = stateView.state.application.interaction;
    if (interaction is! EditingState) {
      return false;
    }
    final transform = interaction.currentTransform;
    return transform is ArrowPointTransform && transform.shouldDelete;
  }

  DrawPoint? _resolveHandlePosition(
    ArrowPointOverlay overlay,
    ArrowPointHandle handle,
  ) {
    for (final candidate in overlay.turningPoints) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    for (final candidate in overlay.addablePoints) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    for (final candidate in overlay.loopPoints) {
      if (candidate == handle) {
        return candidate.position;
      }
    }
    return null;
  }

  Offset _localOffset(DrawRect rect, DrawPoint point) =>
      Offset(point.x - rect.minX, point.y - rect.minY);

  /// Draw box-selection overlay.
  void _drawBoxSelection(Canvas canvas, DrawRect bounds, double scale) {
    final boxSelectionConfig = renderKey.boxSelectionConfig;

    // Draw translucent fill.
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = boxSelectionConfig.fillColor.withValues(
        alpha: boxSelectionConfig.fillOpacity,
      );

    // Draw stroke.
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          boxSelectionConfig.strokeWidth / (scale == 0 ? 1.0 : scale)
      ..color = boxSelectionConfig.strokeColor
      ..isAntiAlias = true;
    canvas
      ..save()
      ..drawRect(
        Rect.fromLTWH(bounds.minX, bounds.minY, bounds.width, bounds.height),
        fillPaint,
      )
      ..drawRect(
        Rect.fromLTWH(bounds.minX, bounds.minY, bounds.width, bounds.height),
        strokePaint,
      )
      ..restore();
  }

  void _drawSnapGuides({
    required Canvas canvas,
    required List<SnapGuide> guides,
    required double scale,
  }) {
    final config = renderKey.snapConfig;
    final effectiveScale = scale == 0 ? 1.0 : scale;
    final invScale = 1.0 / effectiveScale;
    final strokeWidth = config.lineWidth * invScale;
    final markerSize = config.markerSize * invScale;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = config.lineColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final drawMarkers = markerSize > 0;

    for (final guide in guides) {
      final start = guide.start;
      final end = guide.end;
      if (start == end) {
        continue;
      }
      final isGap = guide.kind == SnapGuideKind.gap;
      if (isGap) {
        _drawGapGuideLine(
          canvas: canvas,
          guide: guide,
          markerSize: markerSize,
          paint: paint,
        );
      } else {
        canvas.drawLine(
          Offset(start.x, start.y),
          Offset(end.x, end.y),
          paint,
        );
      }

      if (isGap && drawMarkers) {
        _drawGapCenterTicks(
          canvas: canvas,
          guide: guide,
          size: markerSize,
          paint: paint,
        );
      }

      if (drawMarkers) {
        if (guide.markers.isEmpty) {
          if (isGap) {
            _drawTick(
              canvas: canvas,
              point: start,
              axis: guide.axis,
              size: markerSize * 1.5,
              paint: paint,
            );
            _drawTick(
              canvas: canvas,
              point: end,
              axis: guide.axis,
              size: markerSize * 1.5,
              paint: paint,
            );
          } else {
            _drawCross(
              canvas: canvas,
              point: start,
              size: markerSize,
              paint: paint,
            );
            _drawCross(
              canvas: canvas,
              point: end,
              size: markerSize,
              paint: paint,
            );
          }
        } else {
          for (final marker in guide.markers) {
            if (isGap) {
              final isEndMarker = marker == start || marker == end;
              _drawTick(
                canvas: canvas,
                point: marker,
                axis: guide.axis,
                size: isEndMarker ? markerSize * 1.5 : markerSize,
                paint: paint,
              );
            } else {
              _drawCross(
                canvas: canvas,
                point: marker,
                size: markerSize,
                paint: paint,
              );
            }
          }
        }
      }

      if (isGap && config.showGapSize && guide.label != null) {
        _drawGapLabel(
          canvas: canvas,
          guide: guide,
          scale: effectiveScale,
          color: config.lineColor,
        );
      }
    }
  }

  void _drawGapCenterTicks({
    required Canvas canvas,
    required SnapGuide guide,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final start = guide.start;
    final end = guide.end;
    final midX = (start.x + end.x) / 2;
    final midY = (start.y + end.y) / 2;
    final separation = size * 0.6;
    if (guide.axis == SnapGuideAxis.horizontal) {
      _drawTick(
        canvas: canvas,
        point: DrawPoint(x: midX - separation / 2, y: midY),
        axis: guide.axis,
        size: size,
        paint: paint,
      );
      _drawTick(
        canvas: canvas,
        point: DrawPoint(x: midX + separation / 2, y: midY),
        axis: guide.axis,
        size: size,
        paint: paint,
      );
      return;
    }
    _drawTick(
      canvas: canvas,
      point: DrawPoint(x: midX, y: midY - separation / 2),
      axis: guide.axis,
      size: size,
      paint: paint,
    );
    _drawTick(
      canvas: canvas,
      point: DrawPoint(x: midX, y: midY + separation / 2),
      axis: guide.axis,
      size: size,
      paint: paint,
    );
  }

  void _drawGapGuideLine({
    required Canvas canvas,
    required SnapGuide guide,
    required double markerSize,
    required Paint paint,
  }) {
    final start = guide.start;
    final end = guide.end;
    if (guide.axis == SnapGuideAxis.horizontal) {
      final y = (start.y + end.y) / 2;
      final minX = math.min(start.x, end.x);
      final maxX = math.max(start.x, end.x);
      if (markerSize > 0) {
        final midX = (minX + maxX) / 2;
        final separation = markerSize * 0.6;
        final gapPadding = math.max(paint.strokeWidth, markerSize * 0.15);
        final gapStart = midX - separation / 2 - gapPadding;
        final gapEnd = midX + separation / 2 + gapPadding;
        if (gapStart > minX) {
          canvas.drawLine(Offset(minX, y), Offset(gapStart, y), paint);
        }
        if (gapEnd < maxX) {
          canvas.drawLine(Offset(gapEnd, y), Offset(maxX, y), paint);
        }
        return;
      }
      canvas.drawLine(Offset(minX, y), Offset(maxX, y), paint);
      return;
    }

    final x = (start.x + end.x) / 2;
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    if (markerSize > 0) {
      final midY = (minY + maxY) / 2;
      final separation = markerSize * 0.6;
      final gapPadding = math.max(paint.strokeWidth, markerSize * 0.15);
      final gapStart = midY - separation / 2 - gapPadding;
      final gapEnd = midY + separation / 2 + gapPadding;
      if (gapStart > minY) {
        canvas.drawLine(Offset(x, minY), Offset(x, gapStart), paint);
      }
      if (gapEnd < maxY) {
        canvas.drawLine(Offset(x, gapEnd), Offset(x, maxY), paint);
      }
      return;
    }
    canvas.drawLine(Offset(x, minY), Offset(x, maxY), paint);
  }

  void _drawCross({
    required Canvas canvas,
    required DrawPoint point,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final half = size * 0.35;
    final x = point.x;
    final y = point.y;
    canvas
      ..drawLine(Offset(x - half, y - half), Offset(x + half, y + half), paint)
      ..drawLine(Offset(x - half, y + half), Offset(x + half, y - half), paint);
  }

  void _drawTick({
    required Canvas canvas,
    required DrawPoint point,
    required SnapGuideAxis axis,
    required double size,
    required Paint paint,
  }) {
    if (size <= 0) {
      return;
    }
    final half = size / 2;
    if (axis == SnapGuideAxis.horizontal) {
      canvas.drawLine(
        Offset(point.x, point.y - half),
        Offset(point.x, point.y + half),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(point.x - half, point.y),
        Offset(point.x + half, point.y),
        paint,
      );
    }
  }

  void _drawGapLabel({
    required Canvas canvas,
    required SnapGuide guide,
    required double scale,
    required Color color,
  }) {
    final label = guide.label;
    if (label == null) {
      return;
    }
    final textPainter = TextPainter(
      text: TextSpan(
        text: label.toStringAsFixed(0),
        style: TextStyle(
          color: color,
          fontSize: 10 / (scale == 0 ? 1.0 : scale),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final mid = DrawPoint(
      x: (guide.start.x + guide.end.x) / 2,
      y: (guide.start.y + guide.end.y) / 2,
    );
    final offset = Offset(
      mid.x - textPainter.width / 2,
      mid.y - textPainter.height - (4 / (scale == 0 ? 1.0 : scale)),
    );
    textPainter.paint(canvas, offset);
  }

  /// Draw preview borders for elements that would be selected.
  void _drawBoxSelectionPreview(Canvas canvas, DrawRect bounds, double scale) {
    final state = stateView.state;
    final document = state.domain.document;
    final candidates = document.getElementsInRect(bounds);

    for (final element in candidates) {
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      // Only show preview for elements that are completely within bounds.
      if (bounds.minX <= aabb.minX &&
          bounds.maxX >= aabb.maxX &&
          bounds.minY <= aabb.minY &&
          bounds.maxY >= aabb.maxY) {
        // Draw preview border using same style as multi-select outlines
        final effectiveElement = stateView.effectiveElement(element);
        elementRenderer.renderSelectionOutline(
          canvas: canvas,
          bounds: effectiveElement.rect,
          scaleFactor: scale,
          config: renderKey.selectionConfig,
          rotation: effectiveElement.rotation,
          rotationCenter: effectiveElement.center,
          dashed: false,
        );
      }
    }
  }

  bool _rectsIntersect(DrawRect a, DrawRect b) =>
      a.minX <= b.maxX &&
      a.maxX >= b.minX &&
      a.minY <= b.maxY &&
      a.maxY >= b.minY;

  @override
  bool shouldRepaint(covariant DynamicCanvasPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicCanvasPainter && other.renderKey == renderKey;

  @override
  int get hashCode => renderKey.hashCode;
}
