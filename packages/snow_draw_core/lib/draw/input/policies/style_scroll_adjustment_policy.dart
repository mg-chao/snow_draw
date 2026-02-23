import '../../elements/core/element_data.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/free_draw/free_draw_data.dart';
import '../../elements/types/line/line_data.dart';
import '../../elements/types/rectangle/rectangle_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';

const _stepEpsilon = 0.01;

/// Returns the next stepped value based on [currentValue] and direction.
double resolveNextSteppedValue(
  double currentValue,
  List<double> steps, {
  required bool decrease,
}) {
  if (steps.isEmpty) {
    return currentValue;
  }

  final candidates = decrease ? steps.reversed : steps;
  final threshold = decrease
      ? currentValue - _stepEpsilon
      : currentValue + _stepEpsilon;
  for (final step in candidates) {
    if (decrease ? step < threshold : step > threshold) {
      return step;
    }
  }
  return decrease ? steps.first : steps.last;
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
    _resolveAverageSelectedMetricForType<RectangleData>(
      state,
      (data) => data.strokeWidth,
    );

double? resolveAverageSelectedArrowStrokeWidth(DrawState state) =>
    _resolveAverageSelectedMetricForType<ArrowData>(
      state,
      (data) => data.strokeWidth,
    );

double? resolveAverageSelectedLineStrokeWidth(DrawState state) =>
    _resolveAverageSelectedMetricForType<LineData>(
      state,
      (data) => data.strokeWidth,
    );

double? resolveAverageSelectedFreeDrawStrokeWidth(DrawState state) =>
    _resolveAverageSelectedMetricForType<FreeDrawData>(
      state,
      (data) => data.strokeWidth,
    );

double? resolveAverageSelectedFontSize(DrawState state) =>
    resolveAverageSelectedMetric(state, _resolveFontSizeMetric);

double? _resolveAverageSelectedMetricForType<T extends ElementData>(
  DrawState state,
  double Function(T data) metricResolver,
) => resolveAverageSelectedMetric(state, (data) {
  if (data is! T) {
    return null;
  }
  return metricResolver(data);
});

double? _resolveFontSizeMetric(ElementData data) {
  if (data
      case TextData(:final fontSize) || SerialNumberData(:final fontSize)) {
    return fontSize;
  }
  return null;
}
