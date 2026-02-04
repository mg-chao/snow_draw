import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/selection_calculator.dart';
import '../text/text_data.dart';
import '../text/text_layout.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

const _defaultTextGap = 18;
const _gapStrokeMultiplier = 2;

@immutable
class SerialNumberTextConnection {
  const SerialNumberTextConnection({
    required this.start,
    required this.end,
    this.textBaselineStart,
    this.textBaselineEnd,
  });

  final DrawPoint start;
  final DrawPoint end;
  final DrawPoint? textBaselineStart;
  final DrawPoint? textBaselineEnd;
}

DrawRect resolveSerialNumberBoundTextRect({
  required ElementState serialElement,
  required SerialNumberData serialData,
  required TextData textData,
  double? gap,
}) {
  final layout = layoutText(data: textData, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final width = layout.size.width + horizontalPadding * 2;
  final height = math.max(layout.size.height, layout.lineHeight);
  final strokeWidth = resolveSerialNumberStrokeWidth(data: serialData);
  final resolvedGap =
      gap ??
      math.max(_defaultTextGap, strokeWidth * _gapStrokeMultiplier).toDouble();

  final rect = serialElement.rect;
  final minX = rect.maxX + resolvedGap;
  final minY = rect.centerY - height / 2;

  return DrawRect(
    minX: minX,
    minY: minY,
    maxX: minX + width,
    maxY: minY + height,
  );
}

SerialNumberTextConnection? resolveSerialNumberTextConnection({
  required ElementState serialElement,
  required ElementState textElement,
  required double lineWidth,
}) {
  if (lineWidth <= 0) {
    return null;
  }

  final serialRect = serialElement.rect;
  if (serialRect.width <= 0 || serialRect.height <= 0) {
    return null;
  }

  final textRect = SelectionCalculator.computeElementWorldAabb(textElement);
  if (textRect.width <= 0 || textRect.height <= 0) {
    return null;
  }

  final attachment = _resolveTextAttachment(
    serialRect: serialRect,
    textRect: textRect,
  );
  final center = serialRect.center;
  final anchor = attachment.anchor;

  final dx = anchor.x - center.x;
  final dy = anchor.y - center.y;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance <= 0) {
    return null;
  }

  final radius = math.min(serialRect.width, serialRect.height) / 2;
  final totalOffset = radius + lineWidth;
  if (distance <= totalOffset) {
    return null;
  }

  final ux = dx / distance;
  final uy = dy / distance;
  final start = DrawPoint(
    x: center.x + ux * (radius + lineWidth / 2),
    y: center.y + uy * (radius + lineWidth / 2),
  );
  final end = DrawPoint(
    x: anchor.x - ux * (lineWidth / 2),
    y: anchor.y - uy * (lineWidth / 2),
  );

  return SerialNumberTextConnection(
    start: start,
    end: end,
    textBaselineStart: attachment.textBaselineStart,
    textBaselineEnd: attachment.textBaselineEnd,
  );
}

_TextAttachment _resolveTextAttachment({
  required DrawRect serialRect,
  required DrawRect textRect,
}) {
  final centerX = serialRect.centerX;
  final isAbove = textRect.maxY < serialRect.minY;
  final isBelow = textRect.minY > serialRect.maxY;
  final centeredHorizontally =
      centerX >= textRect.minX && centerX <= textRect.maxX;

  if ((isAbove || isBelow) && centeredHorizontally) {
    return _TextAttachment(
      anchor: DrawPoint(x: centerX, y: isAbove ? textRect.maxY : textRect.minY),
    );
  }

  final anchorX = centerX.clamp(textRect.minX, textRect.maxX);
  final baselineY = textRect.maxY;
  return _TextAttachment(
    anchor: DrawPoint(x: anchorX, y: baselineY),
    textBaselineStart: DrawPoint(x: textRect.minX, y: baselineY),
    textBaselineEnd: DrawPoint(x: textRect.maxX, y: baselineY),
  );
}

@immutable
class _TextAttachment {
  const _TextAttachment({
    required this.anchor,
    this.textBaselineStart,
    this.textBaselineEnd,
  });

  final DrawPoint anchor;
  final DrawPoint? textBaselineStart;
  final DrawPoint? textBaselineEnd;
}
