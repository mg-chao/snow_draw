import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';
import 'filter_segment.dart';

/// Builds render segments from z-ordered elements.
///
/// Contiguous non-filter elements are collapsed into a single batch segment.
/// Adjacent filters of the same CanvasFilterType are merged into a
/// [MergedFilterSegment] so the renderer can apply them in a single
/// `saveLayer` pass.
class FilterSegmentBuilder {
  const FilterSegmentBuilder();

  static const _batchFingerprintSeed = 17;
  static const _identityFingerprintSeed = 23;
  static const _hashMask = 0x1fffffff;

  /// Builds alternating element-batch and filter segments.
  List<RenderSegment> build(List<ElementState> elements) {
    if (elements.isEmpty) {
      return const <RenderSegment>[];
    }

    final segments = <RenderSegment>[];
    final currentBatch = <ElementState>[];
    var currentBatchFingerprint = _batchFingerprintSeed;
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
      currentBatchFingerprint = _batchFingerprintSeed;
      currentBatchIdentityFingerprint = _identityFingerprintSeed;
    }

    for (final element in elements) {
      final data = element.data;
      if (data is FilterData) {
        flushBatch();
        segments.add(
          FilterSegment(
            filterElement: element,
            filterData: data,
            idFingerprint: _stableElementIdFingerprint(element),
            identityFingerprint: _stableElementIdentityFingerprint(element),
          ),
        );
        continue;
      }
      currentBatch.add(element);
      currentBatchFingerprint =
          _hashMask & ((currentBatchFingerprint * 31) + element.id.hashCode);
      currentBatchIdentityFingerprint =
          _hashMask &
          ((currentBatchIdentityFingerprint * 31) + identityHashCode(element));
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
        var idFingerprint = _batchFingerprintSeed;
        var identityFingerprint = _identityFingerprintSeed;
        for (final filter in pendingFilters) {
          idFingerprint =
              _hashMask &
              ((idFingerprint * 31) + _resolveFilterIdFingerprint(filter));
          identityFingerprint =
              _hashMask &
              ((identityFingerprint * 31) +
                  _resolveFilterIdentityFingerprint(filter));
        }
        merged.add(
          MergedFilterSegment(
            filters: List<FilterSegment>.unmodifiable(pendingFilters),
            idFingerprint: idFingerprint,
            identityFingerprint: identityFingerprint,
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

  int _stableElementIdFingerprint(ElementState element) =>
      _hashMask & ((_batchFingerprintSeed * 31) + element.id.hashCode);

  int _stableElementIdentityFingerprint(ElementState element) =>
      _hashMask & ((_identityFingerprintSeed * 31) + identityHashCode(element));

  int _resolveFilterIdFingerprint(FilterSegment segment) =>
      segment.idFingerprint ??
      _stableElementIdFingerprint(segment.filterElement);

  int _resolveFilterIdentityFingerprint(FilterSegment segment) =>
      segment.identityFingerprint ??
      _stableElementIdentityFingerprint(segment.filterElement);
}
