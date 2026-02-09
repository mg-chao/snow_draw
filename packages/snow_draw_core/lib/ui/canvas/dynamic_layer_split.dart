import '../../draw/elements/types/highlight/highlight_data.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/interaction_state.dart';

/// Resolves the first document index rendered on the dynamic canvas layer.
///
/// Returns `null` when no split is needed. Returns `0` when all document
/// elements should be lifted to the dynamic layer to preserve blend behavior
/// for in-progress overlays such as highlight creation.
int? resolveDynamicLayerStartIndex(DrawStateView view) {
  final interaction = view.state.application.interaction;

  if (interaction is TextEditingState && interaction.isNew) {
    return 0;
  }

  if (interaction is CreatingState &&
      interaction.elementData is HighlightData) {
    return 0;
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
    }
  }

  if (minIndex == null) {
    return null;
  }

  for (var i = minIndex; i < document.elements.length; i++) {
    final element = document.elements[i];
    if (element.data is HighlightData) {
      return 0;
    }
  }

  return minIndex;
}
