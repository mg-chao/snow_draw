import 'package:snow_draw_core/snow_draw_core.dart';

/// Resolves the first document index rendered on the dynamic canvas layer.
///
/// Returns `null` when no split is needed. Returns `0` when all document
/// elements should be lifted to the dynamic layer to preserve filter
/// compositing behavior.
int? resolveDynamicLayerStartIndex(DrawStateView view) {
  switch (view.state.application.interaction) {
    case TextEditingState(isNew: true):
    case CreatingState(elementData: HighlightData()):
      return null;
    case CreatingState(elementData: FilterData()):
      return 0;
    default:
      break;
  }

  final selectedIds = view.selectedIds;
  if (selectedIds.isEmpty) {
    return null;
  }

  final document = view.state.domain.document;
  int? minIndex;
  for (final id in selectedIds) {
    final orderIndex = document.getOrderIndex(id);
    if (orderIndex == null) {
      continue;
    }
    if (minIndex == null || orderIndex < minIndex) {
      minIndex = orderIndex;
      if (minIndex == 0) {
        break;
      }
    }
  }
  if (minIndex == null) {
    return null;
  }

  return document.hasFilterElementFromOrderIndex(
        minIndex,
        includeTransparent: false,
      )
      ? 0
      : minIndex;
}
