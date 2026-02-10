import 'package:meta/meta.dart';

import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';

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
