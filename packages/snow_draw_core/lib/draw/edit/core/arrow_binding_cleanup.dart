import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/elbow/elbow_editing.dart';
import '../../elements/types/line/line_data.dart';
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
  for (final entry in transformedElements.entries) {
    final transformed = entry.value;
    final data = transformed.data;
    if (data is! ArrowLikeData) {
      continue;
    }

    final hasBinding = data.startBinding != null || data.endBinding != null;
    final hasSpecialFlags =
        data.startIsSpecial != null || data.endIsSpecial != null;
    if (!hasBinding && !hasSpecialFlags) {
      continue;
    }

    final updated = _unbindArrowElement(
      element: transformed,
      data: data,
      lookup: lookup,
    );
    if (updated == null || updated == transformed) {
      continue;
    }
    updates[transformed.id] = updated;
  }
  return updates;
}

ElementState? _unbindArrowElement({
  required ElementState element,
  required ArrowLikeData data,
  required CombinedElementLookup lookup,
}) {
  if (data is ArrowData && data.arrowType == ArrowType.elbow) {
    final unboundElbow = computeElbowEdit(
      element: element,
      data: data,
      lookup: lookup,
      startBindingOverrideIsSet: true,
      endBindingOverrideIsSet: true,
      finalize: true,
    );
    final rectAndPoints = computeArrowRectAndPoints(
      localPoints: unboundElbow.localPoints,
      oldRect: element.rect,
      rotation: element.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: unboundElbow.fixedSegments,
      oldRect: element.rect,
      newRect: rectAndPoints.rect,
      rotation: element.rotation,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: rectAndPoints.localPoints,
      rect: rectAndPoints.rect,
    );
    final updatedData = data.copyWith(
      points: normalized,
      startBinding: null,
      endBinding: null,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: null,
      endIsSpecial: null,
    );
    return element.copyWith(rect: rectAndPoints.rect, data: updatedData);
  }

  final updatedData = switch (data) {
    final ArrowData value => value.copyWith(
      startBinding: null,
      endBinding: null,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    ),
    final LineData value => value.copyWith(
      startBinding: null,
      endBinding: null,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    ),
    _ => data.copyWith(),
  };
  return element.copyWith(data: updatedData);
}
