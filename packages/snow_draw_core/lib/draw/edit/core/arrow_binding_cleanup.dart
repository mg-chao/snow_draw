import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/elbow/elbow_editing.dart';
import '../../models/element_state.dart';
import '../../types/element_style.dart';
import '../../utils/combined_element_lookup.dart';

/// Clears bindings for transformed arrow-like elements.
///
/// Use this after applying geometry transforms (move/resize/rotate) so arrows
/// no longer stay attached to old targets.
Map<String, ElementState> unbindArrowLikeElements({
  required Map<String, ElementState> transformedElements,
  required Map<String, ElementState> baseElements,
}) {
  final lookup = CombinedElementLookup(
    base: baseElements,
    overlay: transformedElements,
  );
  final updates = <String, ElementState>{};
  for (final element in transformedElements.values) {
    final data = element.data;
    if (data is! ArrowLikeData || !_hasBindingState(data)) {
      continue;
    }

    updates[element.id] = _unbindArrowElement(
      element: element,
      data: data,
      lookup: lookup,
    );
  }
  return updates;
}

bool _hasBindingState(ArrowLikeData data) =>
    data.startBinding != null ||
    data.endBinding != null ||
    data.startIsSpecial != null ||
    data.endIsSpecial != null;

ElementState _unbindArrowElement({
  required ElementState element,
  required ArrowLikeData data,
  required CombinedElementLookup lookup,
}) {
  if (data is ArrowData && data.arrowType == ArrowType.elbow) {
    final unboundElbow = computeElbowEdit(
      element: element,
      data: data,
      lookup: lookup,
      startBindingOverride: null,
      endBindingOverride: null,
      finalize: true,
    );
    final geometry = resolveArrowGeometryUpdate(
      localPoints: unboundElbow.localPoints,
      oldRect: element.rect,
      rotation: element.rotation,
      arrowType: data.arrowType,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: unboundElbow.fixedSegments,
      oldRect: element.rect,
      newRect: geometry.rect,
      rotation: element.rotation,
    );
    final updatedData = data.copyWith(
      points: geometry.normalizedPoints,
      startBinding: null,
      endBinding: null,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: null,
      endIsSpecial: null,
    );
    return element.copyWith(rect: geometry.rect, data: updatedData);
  }

  final updatedData = _clearBindings(data);
  return element.copyWith(data: updatedData);
}

ArrowLikeData _clearBindings(ArrowLikeData data) => data.copyWith(
  startBinding: null,
  endBinding: null,
  fixedSegments: null,
  startIsSpecial: null,
  endIsSpecial: null,
);
