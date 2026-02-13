import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/selection_derived_data.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../move/move_operation.dart' show MoveOperation;
import '../preview/edit_preview.dart';
import '../resize/resize_operation.dart' show ResizeOperation;
import '../rotate/rotate_operation.dart' show RotateOperation;
import 'edit_errors.dart';
import 'edit_operation_params.dart';

List<ElementState> snapshotSelectedElements(DrawState state) {
  final document = state.domain.document;
  final selectedElements = <ElementState>[];
  for (final id in state.domain.selection.selectedIds) {
    final element = document.getElementById(id);
    if (element != null) {
      selectedElements.add(element);
    }
  }
  return selectedElements;
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
  if (bounds == null) {
    throw EditMissingDataError(
      dataName: 'selection bounds',
      operationName: operationName,
    );
  }
  return bounds;
}

EditPreview buildEditPreview({
  required DrawState state,
  required EditContext context,
  required Map<String, ElementState> previewElementsById,
  DrawRect? multiSelectBounds,
  double? multiSelectRotation,
}) {
  final selectionPreview = buildSelectionPreview(
    state: state,
    context: context,
    previewElementsById: previewElementsById,
    multiSelectBounds: multiSelectBounds,
    multiSelectRotation: multiSelectRotation,
  );

  return EditPreview(
    previewElementsById: previewElementsById,
    selectionPreview: selectionPreview,
  );
}

/// Builds a snapshot map from selected elements.
///
/// Each element is mapped to a lean snapshot via [toSnapshot], keyed by
/// element id. This generic helper replaces the three near-identical
/// `buildMoveSnapshots`, `buildResizeSnapshots`, and
/// `buildRotateSnapshots` functions.
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
  if (context is! C) {
    throw EditContextTypeMismatchError(
      expected: C,
      actual: context.runtimeType,
      operationName: operationName,
      additionalInfo:
          'startPosition=${context.startPosition}, '
          'selectedIds=${context.selectedIdsAtStart.length}',
    );
  }
  return context;
}

T requireTransform<T extends EditTransform>(
  EditTransform transform, {
  required String operationName,
}) {
  if (transform is! T) {
    throw EditTransformTypeMismatchError(
      expected: T,
      actual: transform.runtimeType,
      operationName: operationName,
    );
  }
  return transform;
}

P requireParams<P extends EditOperationParams>(
  EditOperationParams params, {
  String? operationName,
}) {
  if (params is! P) {
    throw EditParamsTypeMismatchError(
      expected: P,
      actual: params.runtimeType,
      operationName: operationName ?? 'EditOperation',
    );
  }
  return params;
}

/// Returns visible elements that are not in [selectedIds].
///
/// Shared by move and resize operations for object-snap reference
/// resolution, eliminating the duplicated private helpers.
List<ElementState> resolveReferenceElements(
  DrawState state,
  Set<String> selectedIds,
) => state.domain.document.elements
    .where(
      (element) => element.opacity > 0 && !selectedIds.contains(element.id),
    )
    .toList();

/// Common context-creation data shared by standard operations.
///
/// Captures selection bounds, selected IDs, element snapshots, and
/// version numbers in one call, eliminating the repeated boilerplate
/// in [MoveOperation], [ResizeOperation], and [RotateOperation].
class StandardContextData<S> {
  const StandardContextData({
    required this.startBounds,
    required this.selectedIds,
    required this.selectionVersion,
    required this.elementsVersion,
    required this.elementSnapshots,
  });

  final DrawRect startBounds;
  final Set<String> selectedIds;
  final int selectionVersion;
  final int elementsVersion;
  final Map<String, S> elementSnapshots;
}

/// Gathers the common context-creation data for standard operations.
StandardContextData<S> gatherStandardContextData<S>({
  required DrawState state,
  required String operationName,
  required S Function(ElementState) toSnapshot,
  DrawRect? initialSelectionBounds,
}) {
  final selectionData = SelectionDataComputer.compute(state);
  final startBounds = requireSelectionBounds(
    selectionData: selectionData,
    initialSelectionBounds: initialSelectionBounds,
    operationName: operationName,
  );
  final selectedIds = {...state.domain.selection.selectedIds};
  final elements = snapshotSelectedElements(state);
  final snapshots = buildSnapshots(elements, toSnapshot);

  return StandardContextData<S>(
    startBounds: startBounds,
    selectedIds: selectedIds,
    selectionVersion: state.domain.selection.selectionVersion,
    elementsVersion: state.domain.document.elementsVersion,
    elementSnapshots: snapshots,
  );
}
