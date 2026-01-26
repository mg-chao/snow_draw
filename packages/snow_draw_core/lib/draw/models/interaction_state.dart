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

// ============================================================================
// Pending Intent (unified pending state discriminator)
// ============================================================================

@immutable
sealed class PendingIntent {
  const PendingIntent();
}

@immutable
class PendingSelectIntent extends PendingIntent {
  const PendingSelectIntent({
    required this.elementId,
    required this.addToSelection,
  });
  final String elementId;
  final bool addToSelection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingSelectIntent &&
          other.elementId == elementId &&
          other.addToSelection == addToSelection;

  @override
  int get hashCode => Object.hash(elementId, addToSelection);

  @override
  String toString() =>
      'PendingSelectIntent(elementId: $elementId, '
      'addToSelection: $addToSelection)';
}

@immutable
class PendingMoveIntent extends PendingIntent {
  const PendingMoveIntent();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PendingMoveIntent;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'PendingMoveIntent()';
}

@immutable
class IdleState extends InteractionState {
  const IdleState();

  @override
  String toString() => 'IdleState()';
}

@immutable
class DragPendingState extends InteractionState {
  const DragPendingState({
    required this.pointerDownPosition,
    required this.intent,
  });
  final DrawPoint pointerDownPosition;
  final PendingIntent intent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DragPendingState &&
          other.pointerDownPosition == pointerDownPosition &&
          other.intent == intent;

  @override
  int get hashCode => Object.hash(pointerDownPosition, intent);

  @override
  String toString() =>
      'DragPendingState(position: $pointerDownPosition, intent: $intent)';
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

// ============================================================================
// Creation Mode (unified creation discriminator)
// ============================================================================

/// Discriminator for creation mode within [CreatingState].
@immutable
sealed class CreationMode {
  const CreationMode();
}

/// Rect-based creation mode (default for rectangles, text, etc.).
@immutable
class RectCreationMode extends CreationMode {
  const RectCreationMode();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RectCreationMode;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'RectCreationMode()';
}

/// Point-based creation mode (for arrows and polylines).
@immutable
class PointCreationMode extends CreationMode {
  const PointCreationMode({this.fixedPoints = const [], this.currentPoint});

  /// Fixed turning points in world coordinates.
  final List<DrawPoint> fixedPoints;

  /// Current (preview) point in world coordinates.
  final DrawPoint? currentPoint;

  PointCreationMode copyWith({
    List<DrawPoint>? fixedPoints,
    DrawPoint? currentPoint,
  }) => PointCreationMode(
    fixedPoints: fixedPoints ?? this.fixedPoints,
    currentPoint: currentPoint ?? this.currentPoint,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointCreationMode &&
          _listEquals(other.fixedPoints, fixedPoints) &&
          other.currentPoint == currentPoint;

  @override
  int get hashCode => Object.hash(Object.hashAll(fixedPoints), currentPoint);

  @override
  String toString() =>
      'PointCreationMode(fixedPoints: ${fixedPoints.length}, '
      'currentPoint: $currentPoint)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

// ============================================================================
// Creating State (unified)
// ============================================================================

@immutable
class CreatingState extends InteractionState {
  const CreatingState({
    required this.element,
    required this.startPosition,
    required this.currentRect,
    this.snapGuides = const [],
    this.creationMode = const RectCreationMode(),
  });
  final ElementState element;
  final DrawPoint startPosition;
  final DrawRect currentRect;
  final List<SnapGuide> snapGuides;
  final CreationMode creationMode;

  String get elementId => element.id;

  /// Fixed points for point-based creation (arrows/polylines).
  List<DrawPoint> get fixedPoints => switch (creationMode) {
    PointCreationMode(:final fixedPoints) => fixedPoints,
    _ => const [],
  };

  /// Current preview point for point-based creation.
  DrawPoint? get currentPoint => switch (creationMode) {
    PointCreationMode(:final currentPoint) => currentPoint,
    _ => null,
  };

  /// Whether this is a point-based creation (arrow/polyline).
  bool get isPointCreation => creationMode is PointCreationMode;

  CreatingState copyWith({
    ElementState? element,
    DrawPoint? startPosition,
    DrawRect? currentRect,
    List<SnapGuide>? snapGuides,
    CreationMode? creationMode,
  }) => CreatingState(
    element: element ?? this.element,
    startPosition: startPosition ?? this.startPosition,
    currentRect: currentRect ?? this.currentRect,
    snapGuides: snapGuides ?? this.snapGuides,
    creationMode: creationMode ?? this.creationMode,
  );

  @override
  String toString() =>
      'CreatingState(elementId: $elementId, '
      'mode: ${creationMode.runtimeType})';
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
    initialCursorPosition: initialCursorPosition ?? this.initialCursorPosition,
  );

  @override
  String toString() => 'TextEditingState(elementId: $elementId, isNew: $isNew)';
}
