import 'package:meta/meta.dart';

import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/element_state.dart';

/// Diff result for a filter-style-only document mutation.
@immutable
class FilterStyleMutation {
  FilterStyleMutation({required Set<String> changedFilterElementIds})
    : changedFilterElementIds = Set<String>.unmodifiable(
        changedFilterElementIds,
      );

  /// Filter element ids whose style changed in the mutation.
  final Set<String> changedFilterElementIds;
}

/// Returns a filter-style-only mutation diff between [previous] and [next].
///
/// The mutation is considered filter-style-only when:
/// - interaction/view/selection state is unchanged,
/// - document topology (element order/count) is unchanged,
/// - and every changed element is a filter element whose style changed
///   (filter payload and/or opacity) without geometry or z-order changes.
FilterStyleMutation? resolveFilterStyleMutation({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next)) {
    return null;
  }

  final previousApplication = previous.application;
  final nextApplication = next.application;
  if (previousApplication.view != nextApplication.view ||
      previousApplication.interaction != nextApplication.interaction ||
      previousApplication.selectionOverlay !=
          nextApplication.selectionOverlay) {
    return null;
  }

  final previousDomain = previous.domain;
  final nextDomain = next.domain;
  if (previousDomain.selection != nextDomain.selection) {
    return null;
  }

  final previousDocument = previousDomain.document;
  final nextDocument = nextDomain.document;
  if (previousDocument.globalElements != nextDocument.globalElements) {
    return null;
  }

  final previousElements = previousDocument.elements;
  final nextElements = nextDocument.elements;
  if (previousElements.length != nextElements.length) {
    return null;
  }

  final changedFilterElementIds = <String>{};
  for (var index = 0; index < previousElements.length; index++) {
    final previousElement = previousElements[index];
    final nextElement = nextElements[index];
    if (previousElement.id != nextElement.id) {
      return null;
    }
    if (identical(previousElement, nextElement) ||
        previousElement == nextElement) {
      continue;
    }
    if (!_isFilterStyleOnlyElementChange(
      previousElement: previousElement,
      nextElement: nextElement,
    )) {
      return null;
    }
    changedFilterElementIds.add(nextElement.id);
  }

  if (changedFilterElementIds.isEmpty) {
    return null;
  }
  return FilterStyleMutation(changedFilterElementIds: changedFilterElementIds);
}

bool _isFilterStyleOnlyElementChange({
  required ElementState previousElement,
  required ElementState nextElement,
}) {
  final previousData = previousElement.data;
  final nextData = nextElement.data;
  if (previousData is! FilterData || nextData is! FilterData) {
    return false;
  }
  if (previousElement.rect != nextElement.rect ||
      previousElement.rotation != nextElement.rotation ||
      previousElement.zIndex != nextElement.zIndex) {
    return false;
  }

  final filterDataChanged = previousData != nextData;
  final opacityChanged = previousElement.opacity != nextElement.opacity;
  return filterDataChanged || opacityChanged;
}
