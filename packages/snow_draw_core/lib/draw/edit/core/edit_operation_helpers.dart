import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/selection_derived_data.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../preview/edit_preview.dart';
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

Map<String, ElementMoveSnapshot> buildMoveSnapshots(
  Iterable<ElementState> elements,
) => {
  for (final e in elements) e.id: ElementMoveSnapshot(center: e.rect.center),
};

Map<String, ElementResizeSnapshot> buildResizeSnapshots(
  Iterable<ElementState> elements,
) => {
  for (final e in elements)
    e.id: ElementResizeSnapshot(rect: e.rect, rotation: e.rotation),
};

Map<String, ElementRotateSnapshot> buildRotateSnapshots(
  Iterable<ElementState> elements,
) => {
  for (final e in elements)
    e.id: ElementRotateSnapshot(center: e.rect.center, rotation: e.rotation),
};

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
