import 'package:meta/meta.dart';

import '../elements/types/text/text_data.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/edit_context.dart';
import '../types/edit_operation_id.dart';
import '../types/edit_transform.dart';
import '../types/snap_guides.dart';
import 'edit_session_id.dart';
import 'element_state.dart';

@immutable
sealed class InteractionState {
  const InteractionState();
}

@immutable
class PendingSelectInfo {
  const PendingSelectInfo({
    required this.elementId,
    required this.addToSelection,
    required this.pointerDownPosition,
  });
  final String elementId;
  final bool addToSelection;
  final DrawPoint pointerDownPosition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSelectInfo &&
          other.elementId == elementId &&
          other.addToSelection == addToSelection &&
          other.pointerDownPosition == pointerDownPosition;

  @override
  int get hashCode =>
      Object.hash(elementId, addToSelection, pointerDownPosition);

  @override
  String toString() =>
      'PendingSelectInfo(elementId: $elementId, '
      'addToSelection: $addToSelection, '
      'pointerDownPosition: $pointerDownPosition)';
}

@immutable
class IdleState extends InteractionState {
  const IdleState();

  @override
  String toString() => 'IdleState()';
}

@immutable
class PendingSelectState extends InteractionState {
  const PendingSelectState({required this.pendingSelect});
  final PendingSelectInfo pendingSelect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSelectState && other.pendingSelect == pendingSelect;

  @override
  int get hashCode => pendingSelect.hashCode;

  @override
  String toString() => 'PendingSelectState($pendingSelect)';
}

@immutable
class PendingMoveState extends InteractionState {
  const PendingMoveState({required this.pointerDownPosition});
  final DrawPoint pointerDownPosition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingMoveState &&
          other.pointerDownPosition == pointerDownPosition;

  @override
  int get hashCode => pointerDownPosition.hashCode;

  @override
  String toString() =>
      'PendingMoveState(pointerDownPosition: $pointerDownPosition)';
}

@immutable
class EditingState extends InteractionState {
  const EditingState({
    required this.operationId,
    required this.sessionId,
    required this.context,
    required this.currentTransform,
    this.snapGuides = const [],
  });

  /// Stable id of the running edit operation.
  final EditOperationId operationId;

  /// Stable id of the edit session stored in the owning store.
  final EditSessionId sessionId;

  /// Immutable edit context captured at edit start.
  final EditContext context;

  /// Mutable part of an edit session (current delta/position/angle).
  final EditTransform currentTransform;
  final List<SnapGuide> snapGuides;

  EditingState copyWith({
    EditOperationId? operationId,
    EditSessionId? sessionId,
    EditContext? context,
    EditTransform? currentTransform,
    List<SnapGuide>? snapGuides,
  }) => EditingState(
    operationId: operationId ?? this.operationId,
    sessionId: sessionId ?? this.sessionId,
    context: context ?? this.context,
    currentTransform: currentTransform ?? this.currentTransform,
    snapGuides: snapGuides ?? this.snapGuides,
  );

  EditingState withTransform(
    EditTransform transform, {
    List<SnapGuide>? guides,
  }) => EditingState(
    operationId: operationId,
    sessionId: sessionId,
    context: context,
    currentTransform: transform,
    snapGuides: guides ?? snapGuides,
  );

  /// Current (in-progress) applied rotation delta in radians.
  ///
  /// This is used by selection overlay rendering during rotate sessions
  /// (e.g. multi-select rotation preview). It intentionally returns a primitive
  /// value to avoid leaking [RotateTransform] details to callers.
  double get rotationDelta => _rotationDeltaFor(currentTransform);

  static double _rotationDeltaFor(EditTransform transform) =>
      switch (transform) {
        RotateTransform(:final appliedAngle) => appliedAngle,
        CompositeTransform(:final transforms) => transforms.fold(
          0,
          (sum, t) => sum + _rotationDeltaFor(t),
        ),
        _ => 0.0,
      };

  @override
  String toString() => 'EditingState(operationId: $operationId)';
}

@immutable
class CreatingState extends InteractionState {
  const CreatingState({
    required this.element,
    required this.startPosition,
    required this.currentRect,
    this.snapGuides = const [],
  });
  final ElementState element;
  final DrawPoint startPosition;
  final DrawRect currentRect;
  final List<SnapGuide> snapGuides;

  String get elementId => element.id;

  CreatingState copyWith({
    ElementState? element,
    DrawPoint? startPosition,
    DrawRect? currentRect,
    List<SnapGuide>? snapGuides,
  }) => CreatingState(
    element: element ?? this.element,
    startPosition: startPosition ?? this.startPosition,
    currentRect: currentRect ?? this.currentRect,
    snapGuides: snapGuides ?? this.snapGuides,
  );

  @override
  String toString() => 'CreatingState(elementId: $elementId)';
}

@immutable
class ArrowCreatingState extends CreatingState {
  const ArrowCreatingState({
    required super.element,
    required super.startPosition,
    required super.currentRect,
    super.snapGuides = const [],
    this.fixedPoints = const [],
    this.currentPoint,
  });

  /// Fixed turning points in world coordinates.
  final List<DrawPoint> fixedPoints;

  /// Current (preview) point in world coordinates.
  final DrawPoint? currentPoint;

  @override
  ArrowCreatingState copyWith({
    ElementState? element,
    DrawPoint? startPosition,
    DrawRect? currentRect,
    List<SnapGuide>? snapGuides,
    List<DrawPoint>? fixedPoints,
    DrawPoint? currentPoint,
  }) => ArrowCreatingState(
    element: element ?? this.element,
    startPosition: startPosition ?? this.startPosition,
    currentRect: currentRect ?? this.currentRect,
    snapGuides: snapGuides ?? this.snapGuides,
    fixedPoints: fixedPoints ?? this.fixedPoints,
    currentPoint: currentPoint ?? this.currentPoint,
  );

  @override
  String toString() => 'ArrowCreatingState(elementId: $elementId)';
}

@immutable
class BoxSelectingState extends InteractionState {
  const BoxSelectingState({
    required this.startPosition,
    required this.currentPosition,
  });
  final DrawPoint startPosition;
  final DrawPoint currentPosition;

  BoxSelectingState copyWith({
    DrawPoint? startPosition,
    DrawPoint? currentPosition,
  }) => BoxSelectingState(
    startPosition: startPosition ?? this.startPosition,
    currentPosition: currentPosition ?? this.currentPosition,
  );

  DrawRect get bounds {
    final minX = startPosition.x < currentPosition.x
        ? startPosition.x
        : currentPosition.x;
    final minY = startPosition.y < currentPosition.y
        ? startPosition.y
        : currentPosition.y;
    final maxX = startPosition.x > currentPosition.x
        ? startPosition.x
        : currentPosition.x;
    final maxY = startPosition.y > currentPosition.y
        ? startPosition.y
        : currentPosition.y;
    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  @override
  String toString() =>
      'BoxSelectingState(start: $startPosition, current: $currentPosition)';
}

@immutable
class TextEditingState extends InteractionState {
  const TextEditingState({
    required this.elementId,
    required this.draftData,
    required this.rect,
    required this.isNew,
    required this.opacity,
    required this.rotation,
    this.initialCursorPosition,
  });

  final String elementId;
  final TextData draftData;
  final DrawRect rect;
  final bool isNew;
  final double opacity;
  final double rotation;
  final DrawPoint? initialCursorPosition;

  TextEditingState copyWith({
    TextData? draftData,
    DrawRect? rect,
    bool? isNew,
    double? opacity,
    double? rotation,
    DrawPoint? initialCursorPosition,
  }) => TextEditingState(
    elementId: elementId,
    draftData: draftData ?? this.draftData,
    rect: rect ?? this.rect,
    isNew: isNew ?? this.isNew,
    opacity: opacity ?? this.opacity,
    rotation: rotation ?? this.rotation,
    initialCursorPosition:
        initialCursorPosition ?? this.initialCursorPosition,
  );

  @override
  String toString() =>
      'TextEditingState(elementId: $elementId, isNew: $isNew)';
}
