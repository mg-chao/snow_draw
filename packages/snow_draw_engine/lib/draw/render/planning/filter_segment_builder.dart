import '../../elements/types/filter/filter_data.dart';
import '../../models/element_state.dart';
import 'filter_segments.dart';

/// Builds render segments from z-ordered elements.
///
/// Contiguous non-filter elements are collapsed into a single batch segment.
/// Adjacent filters of the same CanvasFilterType are merged into a
/// [MergedFilterSegment] so the renderer can apply them in a single
/// `saveLayer` pass.
class FilterSegmentBuilder {
  const FilterSegmentBuilder();

  static const _idFingerprintSeed = 17;
  static const _identityFingerprintSeed = 23;
  static const _hashMask = 0x1fffffff;

  /// Builds alternating element-batch and filter segments.
  List<RenderSegment> build(List<ElementState> elements) {
    if (elements.isEmpty) {
      return const <RenderSegment>[];
    }

    final segments = <RenderSegment>[];
    final currentBatch = <ElementState>[];
    var currentBatchFingerprint = _idFingerprintSeed;
    var currentBatchIdentityFingerprint = _identityFingerprintSeed;

    void flushBatch() {
      if (currentBatch.isEmpty) {
        return;
      }
      segments.add(
        ElementBatchSegment(
          List<ElementState>.unmodifiable(currentBatch),
          idFingerprint: currentBatchFingerprint,
          identityFingerprint: currentBatchIdentityFingerprint,
        ),
      );
      currentBatch.clear();
      currentBatchFingerprint = _idFingerprintSeed;
      currentBatchIdentityFingerprint = _identityFingerprintSeed;
    }

    for (final element in elements) {
      final data = element.data;
      if (data is! FilterData) {
        currentBatch.add(element);
        currentBatchFingerprint = _appendFingerprint(
          currentBatchFingerprint,
          element.id.hashCode,
        );
        currentBatchIdentityFingerprint = _appendFingerprint(
          currentBatchIdentityFingerprint,
          identityHashCode(element),
        );
        continue;
      }

      flushBatch();
      segments.add(FilterSegment(filterElement: element, filterData: data));
    }

    flushBatch();
    return _mergeAdjacentFilters(segments);
  }

  /// Collapses runs of adjacent [FilterSegment]s that share the same
  /// CanvasFilterType into a single [MergedFilterSegment].
  List<RenderSegment> _mergeAdjacentFilters(List<RenderSegment> segments) {
    if (segments.length < 2) {
      return segments;
    }

    final merged = <RenderSegment>[];
    final pendingFilters = <FilterSegment>[];

    void flushFilters() {
      if (pendingFilters.isEmpty) {
        return;
      }
      if (pendingFilters.length == 1) {
        merged.add(pendingFilters.first);
      } else {
        merged.add(
          MergedFilterSegment(
            filters: List<FilterSegment>.unmodifiable(pendingFilters),
          ),
        );
      }
      pendingFilters.clear();
    }

    for (final segment in segments) {
      if (segment is FilterSegment) {
        if (pendingFilters.isNotEmpty &&
            pendingFilters.last.filterData.type != segment.filterData.type) {
          flushFilters();
        }
        pendingFilters.add(segment);
        continue;
      }
      flushFilters();
      merged.add(segment);
    }

    flushFilters();
    return merged;
  }

  int _appendFingerprint(int current, int value) =>
      _hashMask & ((current * 31) + value);
}
