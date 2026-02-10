import 'package:meta/meta.dart';

import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';
import '../../../draw/types/element_style.dart';

/// A render segment in the filter pipeline.
sealed class RenderSegment {
  const RenderSegment();
}

/// A contiguous batch of non-filter elements.
@immutable
final class ElementBatchSegment extends RenderSegment {
  const ElementBatchSegment(this.elements);

  /// Non-filter elements in z-order.
  final List<ElementState> elements;
}

/// A filter element segment.
@immutable
final class FilterSegment extends RenderSegment {
  const FilterSegment({required this.filterElement, required this.filterData});

  /// Filter element in z-order.
  final ElementState filterElement;

  /// Filter data payload.
  final FilterData filterData;
}

/// A group of adjacent same-type filter elements merged into one pass.
///
/// Reduces `saveLayer` calls by combining clip regions for filters that
/// share the same [CanvasFilterType].
@immutable
final class MergedFilterSegment extends RenderSegment {
  const MergedFilterSegment({required this.filters});

  /// Individual filter entries, all sharing the same [CanvasFilterType].
  final List<FilterSegment> filters;

  /// The common filter type for all entries.
  CanvasFilterType get filterType => filters.first.filterData.type;
}
