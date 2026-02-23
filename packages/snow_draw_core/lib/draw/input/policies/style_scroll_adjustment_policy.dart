import '../../models/draw_state.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/free_draw/free_draw_data.dart';
import '../../elements/types/line/line_data.dart';
import '../../elements/types/rectangle/rectangle_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/core/element_data.dart';

/// Returns the next stepped value based on [currentValue] and direction.
double resolveNextSteppedValue(
  double currentValue,
  List<double> steps, {
  required bool decrease,
}) {
  if (steps.isEmpty) {
    return currentValue;
  }

  if (decrease) {
    for (var i = steps.length - 1; i >= 0; i -= 1) {
      if (steps[i] < currentValue - 0.01) {
        return steps[i];
      }
    }
    return steps.first;
  }

  for (var i = 0; i < steps.length; i += 1) {
    if (steps[i] > currentValue + 0.01) {
      return steps[i];
    }
  }
  return steps.last;
}

/// Resolves the average selected metric computed by [metricResolver].
double? resolveAverageSelectedMetric(
  DrawState state,
  double? Function(ElementData data) metricResolver,
) {
  final selectedIds = state.domain.selection.selectedIds;
  if (selectedIds.isEmpty) {
    return null;
  }

  final document = state.domain.document;
  var count = 0;
  var total = 0.0;
  for (final id in selectedIds) {
    final data = document.getElementById(id)?.data;
    if (data == null) {
      continue;
    }
    final metric = metricResolver(data);
    if (metric == null) {
      continue;
    }
    total += metric;
    count += 1;
  }
  if (count == 0) {
    return null;
  }
  return total / count;
}

double? resolveAverageSelectedRectangleStrokeWidth(DrawState state) =>
    resolveAverageSelectedMetric(state, (data) {
      if (data is RectangleData) {
        return data.strokeWidth;
      }
      return null;
    });

double? resolveAverageSelectedArrowStrokeWidth(DrawState state) =>
    resolveAverageSelectedMetric(state, (data) {
      if (data is ArrowData) {
        return data.strokeWidth;
      }
      return null;
    });

double? resolveAverageSelectedLineStrokeWidth(DrawState state) =>
    resolveAverageSelectedMetric(state, (data) {
      if (data is LineData) {
        return data.strokeWidth;
      }
      return null;
    });

double? resolveAverageSelectedFreeDrawStrokeWidth(DrawState state) =>
    resolveAverageSelectedMetric(state, (data) {
      if (data is FreeDrawData) {
        return data.strokeWidth;
      }
      return null;
    });

double? resolveAverageSelectedFontSize(DrawState state) =>
    resolveAverageSelectedMetric(state, (data) {
      if (data is TextData) {
        return data.fontSize;
      }
      if (data is SerialNumberData) {
        return data.fontSize;
      }
      return null;
    });
