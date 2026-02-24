import '../config/draw_config.dart';
import '../edit/core/edit_cancel_reason.dart';
import '../edit/core/edit_modifiers.dart';
import '../edit/core/edit_operation_params.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_type_id.dart';
import '../history/history_metadata.dart';
import '../history/recordable.dart';
import '../models/interaction_state.dart';
import '../types/draw_color.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/edit_operation_id.dart';
import '../types/element_style.dart';
import 'history_coalescing.dart';
import 'history_policy.dart';

enum ActionCriticality { critical, important, optional }

/// Base class for reducer actions.
///
/// Actions are immutable data objects that describe state transition intents.
abstract class DrawAction
    with HistoryPolicyProvider, HistoryCoalescingProvider {
  const DrawAction();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.none;

  ActionCriticality get criticality => ActionCriticality.important;

  /// Whether this action should cancel an active edit session.
  bool get conflictsWithEditing => false;

  @override
  String toString() => runtimeType.toString();
}

/// Base action that always conflicts with active editing.
abstract class EditingConflictAction extends DrawAction {
  const EditingConflictAction();

  @override
  bool get conflictsWithEditing => true;
}

/// Base action that is always recorded in history.
abstract class HistoryRecordingAction extends DrawAction {
  const HistoryRecordingAction();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;
}

/// Base action that both conflicts with editing and records history.
abstract class EditingConflictHistoryRecordingAction
    extends EditingConflictAction {
  const EditingConflictHistoryRecordingAction();

  @override
  HistoryPolicy get historyPolicy => HistoryPolicy.record;
}

List<T> _freezeList<T>(List<T> values) => List<T>.unmodifiable(values);

// ============================================================================
// Selection actions
// ============================================================================

class SelectElement extends EditingConflictAction {
  const SelectElement({
    required this.elementId,
    required this.position,
    this.addToSelection = false,
  });
  final String elementId;
  final bool addToSelection;
  final DrawPoint position;

  @override
  String toString() =>
      'SelectElement(id: $elementId, addToSelection: $addToSelection)';
}

class ClearSelection extends EditingConflictAction {
  const ClearSelection();
}

class SelectAll extends EditingConflictAction {
  const SelectAll();
}

// ============================================================================
// Element actions
// ============================================================================

class CreateElement extends EditingConflictAction {
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
  String toString() =>
      'CreateElement(typeId: $typeId, position: $position, '
      'snapOverride: $snapOverride)';
}

class UpdateCreatingElement extends EditingConflictAction {
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
  String toString() =>
      'UpdateCreatingElement(position: $currentPosition, '
      'snapOverride: $snapOverride)';
}

class UpdateCreatingElementBatch extends EditingConflictAction {
  UpdateCreatingElementBatch({
    required List<DrawPoint> positions,
    this.maintainAspectRatio = false,
    this.createFromCenter = false,
    this.snapOverride = false,
  }) : positions = _freezeList(positions);

  /// Creates a batch action using an already-frozen positions list.
  ///
  /// Callers must ensure [positions] will not be mutated after dispatch.
  UpdateCreatingElementBatch.frozen({
    required this.positions,
    this.maintainAspectRatio = false,
    this.createFromCenter = false,
    this.snapOverride = false,
  });

  /// Ordered pointer positions represented by this batched update.
  final List<DrawPoint> positions;
  final bool maintainAspectRatio;
  final bool createFromCenter;
  final bool snapOverride;

  @override
  String toString() =>
      'UpdateCreatingElementBatch(count: ${positions.length}, '
      'snapOverride: $snapOverride)';
}

class AddArrowPoint extends EditingConflictAction {
  const AddArrowPoint({required this.position, this.snapOverride = false});

  final DrawPoint position;
  final bool snapOverride;

  @override
  String toString() =>
      'AddArrowPoint(position: $position, snapOverride: $snapOverride)';
}

class FinishCreateElement extends EditingConflictHistoryRecordingAction {
  const FinishCreateElement();

  @override
  String toString() => 'FinishCreateElement()';
}

class CancelCreateElement extends EditingConflictAction {
  const CancelCreateElement();

  @override
  String toString() => 'CancelCreateElement()';
}

class DeleteElements extends EditingConflictHistoryRecordingAction {
  DeleteElements({required List<String> elementIds})
    : elementIds = _freezeList(elementIds);
  final List<String> elementIds;

  @override
  String toString() => 'DeleteElements(ids: $elementIds)';
}

class DuplicateElements extends EditingConflictHistoryRecordingAction {
  DuplicateElements({
    required List<String> elementIds,
    this.offsetX = 10.0,
    this.offsetY = 10.0,
  }) : elementIds = _freezeList(elementIds);
  final List<String> elementIds;
  final double offsetX;
  final double offsetY;

  @override
  String toString() =>
      'DuplicateElements(ids: $elementIds, offset: ($offsetX, $offsetY))';
}

class ChangeElementZIndex extends EditingConflictHistoryRecordingAction {
  const ChangeElementZIndex({required this.elementId, required this.operation});
  final String elementId;
  final ZIndexOperation operation;

  @override
  String toString() =>
      'ChangeElementZIndex(id: $elementId, operation: $operation)';
}

class ChangeElementsZIndex extends EditingConflictHistoryRecordingAction {
  ChangeElementsZIndex({
    required List<String> elementIds,
    required this.operation,
  }) : elementIds = _freezeList(elementIds);
  final List<String> elementIds;
  final ZIndexOperation operation;

  @override
  String toString() =>
      'ChangeElementsZIndex(ids: $elementIds, operation: $operation)';
}

enum ZIndexOperation { bringToFront, sendToBack, bringForward, sendBackward }

class UpdateElementsStyle extends EditingConflictHistoryRecordingAction {
  UpdateElementsStyle({
    required List<String> elementIds,
    this.color,
    this.fillColor,
    this.strokeWidth,
    this.strokeStyle,
    this.fillStyle,
    this.filterType,
    this.filterStrength,
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
    this.highlightShape,
    this.serialNumber,
    this.historyCoalescing,
  }) : elementIds = _freezeList(elementIds);

  final List<String> elementIds;
  final DrawColor? color;
  final DrawColor? fillColor;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final FillStyle? fillStyle;
  final CanvasFilterType? filterType;
  final double? filterStrength;
  final double? cornerRadius;
  final ArrowType? arrowType;
  final ArrowheadStyle? startArrowhead;
  final ArrowheadStyle? endArrowhead;
  final double? fontSize;
  final String? fontFamily;
  final TextHorizontalAlign? textAlign;
  final TextVerticalAlign? verticalAlign;
  final double? opacity;
  final DrawColor? textStrokeColor;
  final double? textStrokeWidth;
  final HighlightShape? highlightShape;
  final int? serialNumber;
  @override
  final HistoryCoalescing? historyCoalescing;

  /// Style payload applied to style-updatable element data.
  ///
  /// Opacity is intentionally excluded because it lives on element state
  /// rather than element data payloads.
  ElementStyleUpdate get styleUpdate => ElementStyleUpdate(
    color: color,
    fillColor: fillColor,
    strokeWidth: strokeWidth,
    strokeStyle: strokeStyle,
    fillStyle: fillStyle,
    filterType: filterType,
    filterStrength: filterStrength,
    cornerRadius: cornerRadius,
    arrowType: arrowType,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
    fontSize: fontSize,
    fontFamily: fontFamily,
    textAlign: textAlign,
    verticalAlign: verticalAlign,
    textStrokeColor: textStrokeColor,
    textStrokeWidth: textStrokeWidth,
    highlightShape: highlightShape,
    serialNumber: serialNumber,
  );

  /// Whether this action contains any data-payload style updates.
  bool get hasStyleUpdates => !styleUpdate.isEmpty;

  /// Whether this action has any effective updates (style payload or opacity).
  bool get hasUpdates => hasStyleUpdates || opacity != null;

  @override
  String toString() =>
      'UpdateElementsStyle(ids: $elementIds, opacity: $opacity)';
}

class UpdateGlobalElements extends EditingConflictHistoryRecordingAction
    implements Recordable {
  const UpdateGlobalElements({
    this.highlightMask,
    this.watermark,
    this.historyCoalescing,
  });

  final HighlightMaskConfig? highlightMask;
  final WatermarkConfig? watermark;
  @override
  final HistoryCoalescing? historyCoalescing;

  bool get hasUpdates => highlightMask != null || watermark != null;

  @override
  String get historyDescription {
    final hasHighlightMask = highlightMask != null;
    final hasWatermark = watermark != null;

    if (hasHighlightMask && !hasWatermark) {
      return 'Update highlight mask';
    }
    if (hasWatermark && !hasHighlightMask) {
      return 'Update watermark';
    }
    return 'Update global overlays';
  }

  @override
  HistoryRecordType get recordType => HistoryRecordType.edit;

  @override
  String toString() =>
      'UpdateGlobalElements('
      'highlightMask: $highlightMask, '
      'watermark: $watermark'
      ')';
}

class CreateSerialNumberTextElements
    extends EditingConflictHistoryRecordingAction
    implements Recordable {
  CreateSerialNumberTextElements({required List<String> elementIds})
    : elementIds = _freezeList(elementIds);

  final List<String> elementIds;

  @override
  String get historyDescription => 'Create serial number text';

  @override
  HistoryRecordType get recordType => HistoryRecordType.create;

  @override
  String toString() => 'CreateSerialNumberTextElements(ids: $elementIds)';
}

class StartTextEdit extends EditingConflictAction {
  const StartTextEdit({required this.position, this.elementId});

  /// Element id to edit. If null, a new text element is created.
  final String? elementId;
  final DrawPoint position;

  @override
  String toString() =>
      'StartTextEdit(elementId: $elementId, position: $position)';
}

class UpdateTextEdit extends DrawAction {
  const UpdateTextEdit({required this.text, this.rect});

  final String text;
  final DrawRect? rect;

  @override
  String toString() =>
      'UpdateTextEdit(textLength: ${text.length}, hasRect: ${rect != null})';
}

/// Recomputes text element bounds after runtime font availability changes.
///
/// This action is used when system fonts are loaded asynchronously and text
/// shaping metrics change. It refreshes bounds for auto-resizing text without
/// recording a history entry.
class RefreshAutoResizeTextLayoutsAfterFontLoad extends DrawAction {
  const RefreshAutoResizeTextLayoutsAfterFontLoad();
}

class FinishTextEdit extends EditingConflictHistoryRecordingAction
    implements Recordable {
  const FinishTextEdit({
    required this.elementId,
    required this.text,
    required this.isNew,
  });

  final String elementId;
  final String text;
  final bool isNew;

  bool get _deletesExistingText => text.trim().isEmpty && !isNew;

  @override
  String get historyDescription => _deletesExistingText
      ? 'Delete text'
      : (isNew ? 'Create text' : 'Edit text');

  @override
  HistoryRecordType get recordType => _deletesExistingText
      ? HistoryRecordType.delete
      : (isNew ? HistoryRecordType.create : HistoryRecordType.edit);

  @override
  String toString() => 'FinishTextEdit(elementId: $elementId, isNew: $isNew)';
}

class CancelTextEdit extends EditingConflictAction {
  const CancelTextEdit();
}

// ============================================================================
// Edit actions
// ============================================================================

class StartEdit extends DrawAction {
  const StartEdit({
    required this.operationId,
    required this.position,
    required this.params,
  });
  final EditOperationId operationId;
  final DrawPoint position;
  final EditOperationParams params;

  @override
  String toString() => 'StartEdit(id: $operationId, position: $position)';
}

class UpdateEdit extends DrawAction {
  const UpdateEdit({
    required this.currentPosition,
    this.modifiers = const EditModifiers(),
  });

  /// Current pointer position (world coordinates).
  final DrawPoint currentPosition;

  /// Modifier state captured by input layer.
  final EditModifiers modifiers;

  @override
  String toString() => 'UpdateEdit(currentPosition: $currentPosition)';
}

class FinishEdit extends HistoryRecordingAction implements Recordable {
  const FinishEdit({this.metadata});
  final HistoryMetadata? metadata;

  @override
  String get historyDescription => metadata?.description ?? 'Edit operation';

  @override
  HistoryRecordType get recordType =>
      metadata?.recordType ?? HistoryRecordType.edit;
}

class CancelEdit extends DrawAction {
  const CancelEdit({this.reason = EditCancelReason.userCancelled});
  final EditCancelReason reason;

  @override
  String toString() => 'CancelEdit(reason: $reason)';
}

class SetDragPending extends EditingConflictAction {
  const SetDragPending({
    required this.pointerDownPosition,
    required this.intent,
  });
  final DrawPoint pointerDownPosition;
  final PendingIntent intent;

  @override
  String toString() =>
      'SetDragPending(position: $pointerDownPosition, intent: $intent)';
}

class ClearDragPending extends EditingConflictAction {
  const ClearDragPending();

  @override
  String toString() => 'ClearDragPending()';
}

// ============================================================================
// Box select actions
// ============================================================================

class StartBoxSelect extends EditingConflictAction {
  const StartBoxSelect({required this.startPosition});
  final DrawPoint startPosition;

  @override
  String toString() => 'StartBoxSelect(start: $startPosition)';
}

class UpdateBoxSelect extends EditingConflictAction {
  const UpdateBoxSelect({required this.currentPosition});
  final DrawPoint currentPosition;

  @override
  String toString() => 'UpdateBoxSelect(current: $currentPosition)';
}

class FinishBoxSelect extends EditingConflictAction {
  const FinishBoxSelect();
}

class CancelBoxSelect extends EditingConflictAction {
  const CancelBoxSelect();
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
