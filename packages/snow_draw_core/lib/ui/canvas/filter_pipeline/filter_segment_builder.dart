import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';
import 'filter_segment.dart';

/// Builds render segments from z-ordered elements.
///
/// Contiguous non-filter elements are collapsed into a single batch segment.
class FilterSegmentBuilder {
  const FilterSegmentBuilder();

  /// Builds alternating element-batch and filter segments.
  List<RenderSegment> build(List<ElementState> elements) {
    if (elements.isEmpty) {
      return const <RenderSegment>[];
    }

    final segments = <RenderSegment>[];
    final currentBatch = <ElementState>[];

    void flushBatch() {
      if (currentBatch.isEmpty) {
        return;
      }
      segments.add(
        ElementBatchSegment(List<ElementState>.unmodifiable(currentBatch)),
      );
      currentBatch.clear();
    }

    for (final element in elements) {
      final data = element.data;
      if (data is FilterData) {
        flushBatch();
        segments.add(FilterSegment(filterElement: element, filterData: data));
        continue;
      }
      currentBatch.add(element);
    }

    flushBatch();
    return segments;
  }
}
