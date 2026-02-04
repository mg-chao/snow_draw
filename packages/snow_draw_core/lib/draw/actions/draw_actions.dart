import 'dart:ui' show Color;

import '../edit/core/edit_cancel_reason.dart';
import '../edit/core/edit_modifiers.dart';
import '../edit/core/edit_operation_params.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_type_id.dart';
import '../history/history_metadata.dart';
import '../history/recordable.dart';
import '../models/interaction_state.dart';
import '../types/draw_point.dart';
import '../types/edit_operation_id.dart';
import '../types/element_style.dart';
import '../utils/edit_intent_detector.dart';
import 'history_policy.dart';

enum ActionCriticality { critical, important, optional }

/// Base class for reducer actions.
///
/// Actions are immutable data objects that describe state transition intents.
abstract class DrawAction with HistoryPolicyProvider {
  const DrawAction();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.none;

  @override
  bool get requiresPreActionSnapshot => false;

  ActionCriticality get criticality => ActionCriticality.important;

  /// Whether this action should cancel an active edit session.
  bool get conflictsWithEditing => false;

  @override
  String toString() => runtimeType.toString();
}

// ============================================================================
// Selection actions
// ============================================================================

class SelectElement extends DrawAction {
  const SelectElement({
    required this.elementId,
    required this.position,
    this.addToSelection = false,
  });
  final String elementId;
  final bool addToSelection;
  final DrawPoint position;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() =>
      'SelectElement(id: $elementId, addToSelection: $addToSelection)';
}

class ClearSelection extends DrawAction {
  const ClearSelection();

  @override
  bool get conflictsWithEditing => true;
}

class SelectAll extends DrawAction {
  const SelectAll();

  @override
  bool get conflictsWithEditing => true;
}

// ============================================================================
// Element actions
// ============================================================================

class CreateElement extends DrawAction {
  const CreateElement({
    required this.typeId,
    required this.position,
    this.initialData,
    this.maintainAspectRatio = false,
    this.createFromCenter = false,
    this.snapOverride = false,
  });

  /// Element type identifier (e.g. `"rectangle"`).
  final ElementTypeId<ElementData> typeId;

  /// Optional initial data payload for the element.
  ///
  /// If omitted, the element definition's default factory is used.
  final ElementData? initialData;

  final DrawPoint position;
  final bool maintainAspectRatio;
  final bool createFromCenter;
  final bool snapOverride;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() =>
      'CreateElement(typeId: $typeId, position: $position, '
      'snapOverride: $snapOverride)';
}

class UpdateCreatingElement extends DrawAction {
  const UpdateCreatingElement({
    required this.currentPosition,
    this.maintainAspectRatio = false,
    this.createFromCenter = false,
    this.snapOverride = false,
  });
  final DrawPoint currentPosition;
  final bool maintainAspectRatio;
  final bool createFromCenter;
  final bool snapOverride;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() =>
      'UpdateCreatingElement(position: $currentPosition, '
      'snapOverride: $snapOverride)';
}

class AddArrowPoint extends DrawAction implements NonRecordable {
  const AddArrowPoint({required this.position, this.snapOverride = false});

  final DrawPoint position;
  final bool snapOverride;

  @override
  bool get conflictsWithEditing => true;

  @override
  String get nonRecordableReason =>
      'AddArrowPoint is an intermediate create state.';

  @override
  String toString() =>
      'AddArrowPoint(position: $position, snapOverride: $snapOverride)';
}

class FinishCreateElement extends DrawAction {
  const FinishCreateElement();

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String toString() => 'FinishCreateElement()';
}

class CancelCreateElement extends DrawAction {
  const CancelCreateElement();

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() => 'CancelCreateElement()';
}

class DeleteElements extends DrawAction {
  const DeleteElements({required this.elementIds});
  final List<String> elementIds;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  String toString() => 'DeleteElements(ids: $elementIds)';
}

class DuplicateElements extends DrawAction {
  const DuplicateElements({
    required this.elementIds,
    this.offsetX = 10.0,
    this.offsetY = 10.0,
  });
  final List<String> elementIds;
  final double offsetX;
  final double offsetY;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  String toString() =>
      'DuplicateElements(ids: $elementIds, offset: ($offsetX, $offsetY))';
}

class ChangeElementZIndex extends DrawAction {
  const ChangeElementZIndex({required this.elementId, required this.operation});
  final String elementId;
  final ZIndexOperation operation;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  String toString() =>
      'ChangeElementZIndex(id: $elementId, operation: $operation)';
}

class ChangeElementsZIndex extends DrawAction {
  const ChangeElementsZIndex({
    required this.elementIds,
    required this.operation,
  });
  final List<String> elementIds;
  final ZIndexOperation operation;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String toString() =>
      'ChangeElementsZIndex(ids: $elementIds, operation: $operation)';
}

enum ZIndexOperation { bringToFront, sendToBack, bringForward, sendBackward }

class UpdateElementsStyle extends DrawAction {
  const UpdateElementsStyle({
    required this.elementIds,
    this.color,
    this.fillColor,
    this.strokeWidth,
    this.strokeStyle,
    this.fillStyle,
    this.cornerRadius,
    this.arrowType,
    this.startArrowhead,
    this.endArrowhead,
    this.fontSize,
    this.fontFamily,
    this.textAlign,
    this.verticalAlign,
    this.opacity,
    this.textStrokeColor,
    this.textStrokeWidth,
    this.serialNumber,
  });

  final List<String> elementIds;
  final Color? color;
  final Color? fillColor;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final FillStyle? fillStyle;
  final double? cornerRadius;
  final ArrowType? arrowType;
  final ArrowheadStyle? startArrowhead;
  final ArrowheadStyle? endArrowhead;
  final double? fontSize;
  final String? fontFamily;
  final TextHorizontalAlign? textAlign;
  final TextVerticalAlign? verticalAlign;
  final double? opacity;
  final Color? textStrokeColor;
  final double? textStrokeWidth;
  final int? serialNumber;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String toString() =>
      'UpdateElementsStyle(ids: $elementIds, opacity: $opacity)';
}

class CreateSerialNumberTextElements extends DrawAction implements Recordable {
  const CreateSerialNumberTextElements({required this.elementIds});

  final List<String> elementIds;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String get historyDescription => 'Create serial number text';

  @override
  HistoryRecordType get recordType => HistoryRecordType.create;

  @override
  String toString() => 'CreateSerialNumberTextElements(ids: $elementIds)';
}

class StartTextEdit extends DrawAction implements NonRecordable {
  const StartTextEdit({required this.position, this.elementId});

  /// Element id to edit. If null, a new text element is created.
  final String? elementId;
  final DrawPoint position;

  @override
  bool get conflictsWithEditing => true;

  @override
  String get nonRecordableReason =>
      'StartTextEdit starts a text editing session.';

  @override
  String toString() =>
      'StartTextEdit(elementId: $elementId, position: $position)';
}

class UpdateTextEdit extends DrawAction implements NonRecordable {
  const UpdateTextEdit({required this.text});

  final String text;

  @override
  String get nonRecordableReason =>
      'UpdateTextEdit is an intermediate edit state.';

  @override
  String toString() => 'UpdateTextEdit(textLength: ${text.length})';
}

class FinishTextEdit extends DrawAction implements Recordable {
  const FinishTextEdit({
    required this.elementId,
    required this.text,
    required this.isNew,
  });

  final String elementId;
  final String text;
  final bool isNew;

  @override
  bool get conflictsWithEditing => true;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String get historyDescription {
    final trimmed = text.trim();
    if (trimmed.isEmpty && !isNew) {
      return 'Delete text';
    }
    return isNew ? 'Create text' : 'Edit text';
  }

  @override
  HistoryRecordType get recordType {
    final trimmed = text.trim();
    if (trimmed.isEmpty && !isNew) {
      return HistoryRecordType.delete;
    }
    return isNew ? HistoryRecordType.create : HistoryRecordType.edit;
  }

  @override
  String toString() => 'FinishTextEdit(elementId: $elementId, isNew: $isNew)';
}

class CancelTextEdit extends DrawAction implements NonRecordable {
  const CancelTextEdit();

  @override
  bool get conflictsWithEditing => true;

  @override
  String get nonRecordableReason =>
      'CancelTextEdit aborts a text editing session.';
}

// ============================================================================
// Edit actions
// ============================================================================

class StartEdit extends DrawAction implements NonRecordable {
  const StartEdit({
    required this.operationId,
    required this.position,
    required this.params,
  });
  final EditOperationId operationId;
  final DrawPoint position;
  final EditOperationParams params;

  @override
  String get nonRecordableReason =>
      'StartEdit represents an intermediate edit session state.';

  @override
  String toString() => 'StartEdit(id: $operationId, position: $position)';
}

class UpdateEdit extends DrawAction implements NonRecordable {
  const UpdateEdit({
    required this.currentPosition,
    this.modifiers = const EditModifiers(),
  });

  /// Current pointer position (world coordinates).
  final DrawPoint currentPosition;

  /// Modifier state captured by input layer.
  final EditModifiers modifiers;

  @override
  String get nonRecordableReason =>
      'UpdateEdit represents an intermediate edit session state.';

  @override
  String toString() => 'UpdateEdit(currentPosition: $currentPosition)';
}

class FinishEdit extends DrawAction implements Recordable {
  const FinishEdit({this.metadata});
  final HistoryMetadata? metadata;

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;

  @override
  bool get requiresPreActionSnapshot => true;

  @override
  String get historyDescription => metadata?.description ?? 'Edit operation';

  @override
  HistoryRecordType get recordType =>
      metadata?.recordType ?? HistoryRecordType.edit;
}

class CancelEdit extends DrawAction implements NonRecordable {
  const CancelEdit({this.reason = EditCancelReason.userCancelled});
  final EditCancelReason reason;

  @override
  String get nonRecordableReason =>
      'CancelEdit indicates the session was aborted.';

  @override
  String toString() => 'CancelEdit(reason: $reason)';
}

class EditIntentAction extends DrawAction {
  const EditIntentAction({
    required this.intent,
    required this.position,
    this.modifiers = const EditModifiers(),
  });
  final EditIntent intent;
  final DrawPoint position;
  final EditModifiers modifiers;

  @override
  String toString() => 'EditIntentAction(intent: $intent, position: $position)';
}

class SetDragPending extends DrawAction {
  const SetDragPending({
    required this.pointerDownPosition,
    required this.intent,
  });
  final DrawPoint pointerDownPosition;
  final PendingIntent intent;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() =>
      'SetDragPending(position: $pointerDownPosition, intent: $intent)';
}

class ClearDragPending extends DrawAction {
  const ClearDragPending();

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() => 'ClearDragPending()';
}

// ============================================================================
// Box select actions
// ============================================================================

class StartBoxSelect extends DrawAction {
  const StartBoxSelect({required this.startPosition});
  final DrawPoint startPosition;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() => 'StartBoxSelect(start: $startPosition)';
}

class UpdateBoxSelect extends DrawAction {
  const UpdateBoxSelect({required this.currentPosition});
  final DrawPoint currentPosition;

  @override
  bool get conflictsWithEditing => true;

  @override
  String toString() => 'UpdateBoxSelect(current: $currentPosition)';
}

class FinishBoxSelect extends DrawAction {
  const FinishBoxSelect();

  @override
  bool get conflictsWithEditing => true;
}

class CancelBoxSelect extends DrawAction {
  const CancelBoxSelect();

  @override
  bool get conflictsWithEditing => true;
}

// ============================================================================
// Camera actions
// ============================================================================

class MoveCamera extends DrawAction {
  const MoveCamera({required this.dx, required this.dy});
  final double dx;
  final double dy;

  @override
  String toString() => 'MoveCamera(dx: $dx, dy: $dy)';
}

class ZoomCamera extends DrawAction {
  const ZoomCamera({required this.scale, this.center});
  final double scale;
  final DrawPoint? center;

  @override
  String toString() => 'ZoomCamera(scale: $scale)';
}

// ============================================================================
// History actions
// ============================================================================

class Undo extends DrawAction {
  const Undo();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.skip;

  @override
  ActionCriticality get criticality => ActionCriticality.critical;
}

class Redo extends DrawAction {
  const Redo();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.skip;

  @override
  ActionCriticality get criticality => ActionCriticality.critical;
}

class ClearHistory extends DrawAction {
  const ClearHistory();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.skip;

  @override
  ActionCriticality get criticality => ActionCriticality.critical;
}
