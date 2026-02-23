import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/selection_derived_data.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../../utils/visible_elements.dart';
import '../preview/edit_preview.dart';
import 'edit_errors.dart';
import 'edit_operation_params.dart';

List<ElementState> snapshotSelectedElements(DrawState state) {
  final document = state.domain.document;
  return state.domain.selection.selectedIds
      .map(document.getElementById)
      .whereType<ElementState>()
      .toList();
}

DrawRect requireSelectionBounds({
  required SelectionDerivedData selectionData,
  required String operationName,
  DrawRect? initialSelectionBounds,
}) {
  final bounds =
      initialSelectionBounds ??
      selectionData.overlayBounds ??
      selectionData.selectionBounds;
  if (bounds != null) {
    return bounds;
  }
  throw EditMissingDataError(
    dataName: 'selection bounds',
    operationName: operationName,
  );
}

EditPreview buildEditPreview({
  required DrawState state,
  required EditContext context,
  required Map<String, ElementState> previewElementsById,
  DrawRect? multiSelectBounds,
  double? multiSelectRotation,
}) => EditPreview(
  previewElementsById: previewElementsById,
  selectionPreview: buildSelectionPreview(
    state: state,
    context: context,
    previewElementsById: previewElementsById,
    multiSelectBounds: multiSelectBounds,
    multiSelectRotation: multiSelectRotation,
  ),
);

/// Builds snapshots keyed by element id.
///
/// Each element is mapped through [toSnapshot].
Map<String, S> buildSnapshots<S>(
  Iterable<ElementState> elements,
  S Function(ElementState) toSnapshot,
) => {for (final e in elements) e.id: toSnapshot(e)};

Map<String, ElementMoveSnapshot> buildMoveSnapshots(
  Iterable<ElementState> elements,
) =>
    buildSnapshots(elements, (e) => ElementMoveSnapshot(center: e.rect.center));

Map<String, ElementResizeSnapshot> buildResizeSnapshots(
  Iterable<ElementState> elements,
) => buildSnapshots(
  elements,
  (e) => ElementResizeSnapshot(rect: e.rect, rotation: e.rotation),
);

Map<String, ElementRotateSnapshot> buildRotateSnapshots(
  Iterable<ElementState> elements,
) => buildSnapshots(
  elements,
  (e) => ElementRotateSnapshot(center: e.rect.center, rotation: e.rotation),
);

C requireContext<C extends EditContext>(
  EditContext context, {
  required String operationName,
}) {
  if (context is C) {
    return context;
  }
  throw EditContextTypeMismatchError(
    expected: C,
    actual: context.runtimeType,
    operationName: operationName,
    additionalInfo:
        'startPosition=${context.startPosition}, '
        'selectedIds=${context.selectedIdsAtStart.length}',
  );
}

T requireTransform<T extends EditTransform>(
  EditTransform transform, {
  required String operationName,
}) {
  if (transform is T) {
    return transform;
  }
  throw EditTransformTypeMismatchError(
    expected: T,
    actual: transform.runtimeType,
    operationName: operationName,
  );
}

P requireParams<P extends EditOperationParams>(
  EditOperationParams params, {
  required String operationName,
}) {
  if (params is P) {
    return params;
  }
  throw EditParamsTypeMismatchError(
    expected: P,
    actual: params.runtimeType,
    operationName: operationName,
  );
}

/// Returns visible elements that are not in [selectedIds].
///
/// Shared by move and resize operations for object-snap reference
/// resolution, eliminating the duplicated private helpers.
List<ElementState> resolveReferenceElements(
  DrawState state,
  Set<String> selectedIds,
) => resolveVisibleElements(
  state.domain.document.elements,
  excludedIds: selectedIds,
);

/// Common context-creation data shared by standard operations.
///
/// Captures selection bounds, selected IDs, element snapshots, and
/// version numbers in one call, eliminating the repeated boilerplate
/// in move/resize/rotate operations.
class StandardContextData<S> {
  const StandardContextData({
    required this.startBounds,
    required this.selectedIds,
    required this.selectionVersion,
    required this.elementsVersion,
    required this.selectedElements,
    required this.elementSnapshots,
  });

  final DrawRect startBounds;
  final Set<String> selectedIds;
  final int selectionVersion;
  final int elementsVersion;
  final List<ElementState> selectedElements;
  final Map<String, S> elementSnapshots;
}

/// Gathers the common context-creation data for standard operations.
StandardContextData<S> gatherStandardContextData<S>({
  required DrawState state,
  required String operationName,
  required S Function(ElementState) toSnapshot,
  DrawRect? initialSelectionBounds,
  SelectionDerivedData? selectionData,
}) {
  final resolvedSelectionData =
      selectionData ?? SelectionDataComputer.compute(state);
  final selectedElements = snapshotSelectedElements(state);
  final selection = state.domain.selection;
  return StandardContextData<S>(
    startBounds: requireSelectionBounds(
      selectionData: resolvedSelectionData,
      initialSelectionBounds: initialSelectionBounds,
      operationName: operationName,
    ),
    selectedIds: {...selection.selectedIds},
    selectionVersion: selection.selectionVersion,
    elementsVersion: state.domain.document.elementsVersion,
    selectedElements: List<ElementState>.unmodifiable(selectedElements),
    elementSnapshots: buildSnapshots(selectedElements, toSnapshot),
  );
}
