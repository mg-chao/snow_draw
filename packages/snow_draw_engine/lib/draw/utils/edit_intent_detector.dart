import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry.dart';
import '../elements/core/element_type_id.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/arrow/arrow_points.dart';
import '../models/draw_state_view.dart';
import '../types/draw_point.dart';
import '../types/resize_mode.dart';
import 'arrow_point_metrics.dart';
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
    required SelectionConfig config,
    required DefaultElementRegistry registry,
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

    if (hitResult.isHandleHit) {
      return _getHandleIntent(
        handleType: hitResult.handleType!,
        selectionPadding: config.padding,
      );
    }

    final elementId = hitResult.elementId;
    if (elementId != null) {
      return _detectElementIntent(
        stateView: stateView,
        elementId: elementId,
        isShiftPressed: isShiftPressed,
        isSelectionPaddingHit: hitResult.isSelectionPaddingHit,
        isInSelectionPadding: hitResult.isInSelectionPadding,
      );
    }

    return isShiftPressed ? null : BoxSelectIntent(startPosition: position);
  }

  EditIntent? _detectElementIntent({
    required DrawStateView stateView,
    required String elementId,
    required bool isShiftPressed,
    required bool isSelectionPaddingHit,
    required bool isInSelectionPadding,
  }) {
    final state = stateView.state;
    if (state.domain.document.getElementById(elementId) == null) {
      return null;
    }

    final selectedIds = state.domain.selection.selectedIds;
    final isSelected = selectedIds.contains(elementId);
    if (isSelected) {
      if (isShiftPressed) {
        return isSelectionPaddingHit
            ? null
            : SelectIntent(elementId: elementId, addToSelection: true);
      }
      return StartMoveIntent(elementId: elementId, addToSelection: false);
    }

    final deferSelectionForDrag =
        !isShiftPressed && selectedIds.length > 1 && isInSelectionPadding;
    return SelectIntent(
      elementId: elementId,
      addToSelection: isShiftPressed,
      deferSelectionForDrag: deferSelectionForDrag,
    );
  }

  EditIntent _getHandleIntent({
    required HandleType handleType,
    required double selectionPadding,
  }) => switch (handleType) {
    HandleType.rotate => const StartRotateIntent(),
    HandleType.topLeft => StartResizeIntent(
      mode: ResizeMode.topLeft,
      selectionPadding: selectionPadding,
    ),
    HandleType.top => StartResizeIntent(
      mode: ResizeMode.top,
      selectionPadding: selectionPadding,
    ),
    HandleType.topRight => StartResizeIntent(
      mode: ResizeMode.topRight,
      selectionPadding: selectionPadding,
    ),
    HandleType.right => StartResizeIntent(
      mode: ResizeMode.right,
      selectionPadding: selectionPadding,
    ),
    HandleType.bottomRight => StartResizeIntent(
      mode: ResizeMode.bottomRight,
      selectionPadding: selectionPadding,
    ),
    HandleType.bottom => StartResizeIntent(
      mode: ResizeMode.bottom,
      selectionPadding: selectionPadding,
    ),
    HandleType.bottomLeft => StartResizeIntent(
      mode: ResizeMode.bottomLeft,
      selectionPadding: selectionPadding,
    ),
    HandleType.left => StartResizeIntent(
      mode: ResizeMode.left,
      selectionPadding: selectionPadding,
    ),
  };

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
    final handleSize = resolveArrowPointHandleSize(
      config.render.controlPointSize,
    );
    final loopThreshold = resolveArrowPointLoopThreshold(hitRadius);
    final handle = ArrowPointUtils.hitTest(
      element: stateView.effectiveElement(element),
      position: position,
      hitRadius: hitRadius,
      loopThreshold: loopThreshold,
      handleSize: handleSize,
      elements: stateView.elements,
      zoom: stateView.state.application.view.camera.zoom,
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
  const StartResizeIntent({required this.mode, required this.selectionPadding});
  final ResizeMode mode;
  final double selectionPadding;

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
