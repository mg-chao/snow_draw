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
  const ElementBatchSegment(
    this.elements, {
    this.idFingerprint,
    this.identityFingerprint,
  });

  /// Non-filter elements in z-order.
  final List<ElementState> elements;

  /// Optional fingerprint of [elements] based on stable element ids.
  ///
  /// When provided by the segment builder, the renderer can skip recomputing
  /// an id hash for cache lookups on every frame.
  final int? idFingerprint;

  /// Optional fingerprint of [elements] based on element object identity.
  ///
  /// This helps cache keys distinguish same-id batches whose element objects
  /// changed (for example due to style updates).
  final int? identityFingerprint;
}

/// A filter element segment.
@immutable
final class FilterSegment extends RenderSegment {
  const FilterSegment({
    required this.filterElement,
    required this.filterData,
    this.idFingerprint,
    this.identityFingerprint,
  });

  /// Filter element in z-order.
  final ElementState filterElement;

  /// Filter data payload.
  final FilterData filterData;

  /// Optional stable-id fingerprint for this filter element.
  final int? idFingerprint;

  /// Optional identity fingerprint for this filter element.
  final int? identityFingerprint;
}

/// A group of adjacent same-type filter elements merged into one pass.
///
/// Reduces `saveLayer` calls by combining clip regions for filters that
/// share the same [CanvasFilterType].
@immutable
final class MergedFilterSegment extends RenderSegment {
  const MergedFilterSegment({
    required this.filters,
    this.idFingerprint,
    this.identityFingerprint,
  });

  /// Individual filter entries, all sharing the same [CanvasFilterType].
  final List<FilterSegment> filters;

  /// The common filter type for all entries.
  CanvasFilterType get filterType => filters.first.filterData.type;

  /// Optional aggregated stable-id fingerprint for [filters].
  final int? idFingerprint;

  /// Optional aggregated identity fingerprint for [filters].
  final int? identityFingerprint;
}
