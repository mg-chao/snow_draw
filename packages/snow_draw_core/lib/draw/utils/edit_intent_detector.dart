import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/element_type_id.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/arrow/arrow_points.dart';
import '../models/draw_state_view.dart';
import '../models/edit_enums.dart';
import '../types/draw_point.dart';
import 'hit_test.dart';

/// Edit intent detector.
///
/// Determines user intent (select / start-move / start-resize /
/// start-rotate ...)
/// based on hit-testing and modifier keys.
///
/// Note: this belongs to the input layer. Do not confuse it with edit-domain
/// operations (move/resize/rotate implementations).
class EditIntentDetector {
  const EditIntentDetector();

  /// Determines the intent from hit test results and modifiers.
  ///
  /// If [filterTypeId] is provided, only elements matching that type will
  /// be considered.
  EditIntent? detectIntent({
    required DrawStateView stateView,
    required DrawPoint position,
    required bool isShiftPressed,
    required bool isAltPressed,
    required SelectionConfig config,
    required ElementRegistry registry,
    ElementTypeId<ElementData>? filterTypeId,
  }) {
    final arrowPointIntent = _detectArrowPointIntent(
      stateView: stateView,
      position: position,
      config: config,
    );
    if (arrowPointIntent != null) {
      return arrowPointIntent;
    }

    final hitResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: config,
      registry: registry,
      filterTypeId: filterTypeId,
    );

    final state = stateView.state;
    final selectedIds = state.domain.selection.selectedIds;

    // 1. Handle hit -> resize/rotate.
    if (hitResult.isHandleHit) {
      return _getHandleIntent(hitResult.handleType!, config.padding);
    }

    // 2. Element hit -> select or start move.
    if (hitResult.elementId != null) {
      final element = state.domain.document.getElementById(
        hitResult.elementId!,
      );
      if (element != null) {
        final addToSelection = isShiftPressed;
        if (selectedIds.contains(hitResult.elementId)) {
          if (addToSelection) {
            if (hitResult.isSelectionPaddingHit) {
              return null;
            }
            return SelectIntent(
              elementId: hitResult.elementId!,
              addToSelection: true,
            );
          }
          return StartMoveIntent(
            elementId: hitResult.elementId!,
            addToSelection: false,
          );
        } else {
          final deferSelectionForDrag =
              !addToSelection &&
              selectedIds.length > 1 &&
              hitResult.isInSelectionPadding;
          return SelectIntent(
            elementId: hitResult.elementId!,
            addToSelection: addToSelection,
            deferSelectionForDrag: deferSelectionForDrag,
          );
        }
      }
    }

    // 3. Clicked blank area.
    if (!isShiftPressed) {
      return BoxSelectIntent(startPosition: position);
    }

    return null;
  }

  EditIntent _getHandleIntent(HandleType handleType, double selectionPadding) {
    switch (handleType) {
      case HandleType.rotate:
        return const StartRotateIntent();
      case HandleType.topLeft:
      case HandleType.top:
      case HandleType.topRight:
      case HandleType.right:
      case HandleType.bottomRight:
      case HandleType.bottom:
      case HandleType.bottomLeft:
      case HandleType.left:
        final resizeMode = hitTest.getResizeModeForHandle(handleType);
        return StartResizeIntent(
          mode: resizeMode!,
          selectionPadding: selectionPadding,
        );
    }
  }

  /// Returns a create intent if the app is currently creating.
  CreateIntent? detectCreateIntent({
    required ElementTypeId<ElementData> elementTypeId,
    required bool isCreating,
  }) {
    if (!isCreating) {
      return null;
    }
    return CreateIntent(typeId: elementTypeId);
  }

  EditIntent? _detectArrowPointIntent({
    required DrawStateView stateView,
    required DrawPoint position,
    required SelectionConfig config,
  }) {
    final selectedIds = stateView.state.domain.selection.selectedIds;
    if (selectedIds.length != 1) {
      return null;
    }
    final element = stateView.state.domain.document.getElementById(
      selectedIds.first,
    );
    if (element == null || element.data is! ArrowLikeData) {
      return null;
    }

    final hitRadius = config.interaction.handleTolerance;
    // Apply multiplier for arrow point handles to make them larger
    final handleSize =
        config.render.controlPointSize *
        ConfigDefaults.arrowPointSizeMultiplier;
    final loopThreshold = hitRadius * 1.5;
    final handle = ArrowPointUtils.hitTest(
      element: stateView.effectiveElement(element),
      position: position,
      hitRadius: hitRadius,
      loopThreshold: loopThreshold,
      handleSize: handleSize,
    );
    if (handle == null) {
      return null;
    }

    return StartArrowPointIntent(
      elementId: handle.elementId,
      pointKind: handle.kind,
      pointIndex: handle.index,
    );
  }
}

/// Shared edit intent detector instance.
const editIntentDetector = EditIntentDetector();

/// Input-layer edit intent.
sealed class EditIntent {
  const EditIntent();
}

final class SelectIntent extends EditIntent {
  const SelectIntent({
    required this.elementId,
    required this.addToSelection,
    this.deferSelectionForDrag = false,
  });
  final String elementId;
  final bool addToSelection;
  final bool deferSelectionForDrag;

  @override
  String toString() =>
      'SelectIntent(id: $elementId, addToSelection: $addToSelection, '
      'deferSelectionForDrag: $deferSelectionForDrag)';
}

final class StartMoveIntent extends EditIntent {
  const StartMoveIntent({
    required this.elementId,
    required this.addToSelection,
  });
  final String elementId;
  final bool addToSelection;

  @override
  String toString() =>
      'StartMoveIntent(id: $elementId, addToSelection: $addToSelection)';
}

final class StartResizeIntent extends EditIntent {
  const StartResizeIntent({required this.mode, this.selectionPadding});
  final ResizeMode mode;
  final double? selectionPadding;

  @override
  String toString() =>
      'StartResizeIntent(mode: $mode, selectionPadding: $selectionPadding)';
}

final class StartRotateIntent extends EditIntent {
  const StartRotateIntent();

  @override
  String toString() => 'StartRotateIntent()';
}

final class StartArrowPointIntent extends EditIntent {
  const StartArrowPointIntent({
    required this.elementId,
    required this.pointKind,
    required this.pointIndex,
    this.isDoubleClick = false,
  });

  final String elementId;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final bool isDoubleClick;

  @override
  String toString() =>
      'StartArrowPointIntent(id: $elementId, kind: $pointKind, '
      'index: $pointIndex, doubleClick: $isDoubleClick)';
}

final class BoxSelectIntent extends EditIntent {
  const BoxSelectIntent({required this.startPosition});
  final DrawPoint startPosition;

  @override
  String toString() => 'BoxSelectIntent(start: $startPosition)';
}

final class ClearSelectionIntent extends EditIntent {
  const ClearSelectionIntent();

  @override
  String toString() => 'ClearSelectionIntent()';
}

final class CreateIntent {
  const CreateIntent({required this.typeId});
  final ElementTypeId<ElementData> typeId;

  @override
  String toString() => 'CreateIntent(typeId: $typeId)';
}
