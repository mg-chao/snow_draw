import 'package:meta/meta.dart';

import 'draw_point.dart';
import 'draw_rect.dart';
import 'element_geometry.dart';
import 'resize_mode.dart';

/// Immutable context snapshot for an edit operation.
///
/// Created on edit-start and kept unchanged for the entire edit session.
///
/// Memory note:
/// Each subclass now carries minimal geometry snapshots (ElementMoveSnapshot,
/// ElementResizeSnapshot, ElementRotateSnapshot) instead of full ElementState.
@immutable
abstract class EditContext {
  const EditContext({
    required this.startPosition,
    required this.startBounds,
    required this.selectedIdsAtStart,
    required this.selectionVersion,
    required this.elementsVersion,
  });

  /// Pointer position at the start of the edit operation (world coordinates).
  final DrawPoint startPosition;

  /// Selection overlay bounds at the start of the edit operation.
  final DrawRect startBounds;

  /// Selected element ids at the start of the edit operation.
  ///
  /// This snapshot is part of the edit session invariants:
  /// - preview should be based on this set
  /// - finish/commit must not depend on selection changing during editing
  final Set<String> selectedIdsAtStart;

  /// Selection version captured when the edit session started.
  final int selectionVersion;

  /// Elements version captured when the edit session started.
  final int elementsVersion;

  DrawPoint get startCenter => startBounds.center;

  bool get isSingleSelect => selectedIdsAtStart.length == 1;
  bool get isMultiSelect => selectedIdsAtStart.length > 1;

  /// Whether this context carries non-empty element snapshots.
  ///
  /// Subclasses override to check their specific snapshot map. This
  /// eliminates the need for a type-switch in [EditValidation].
  bool get hasSnapshots => false;
}

/// Context for move operations.
///
/// Uses ElementMoveSnapshot to store each element's starting center,
/// saving about 92% memory compared to full ElementState.
@immutable
final class MoveEditContext extends EditContext {
  const MoveEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.elementSnapshots,
  });

  /// Starting center for each element (lean snapshot).
  ///
  /// Stores only the data needed for move operations: element centers.
  final Map<String, ElementMoveSnapshot> elementSnapshots;

  @override
  bool get hasSnapshots => elementSnapshots.isNotEmpty;

  /// Get the starting center for an element.
  DrawPoint? getStartCenter(String id) => elementSnapshots[id]?.center;
}

/// Context for resize operations.
///
/// Uses ElementResizeSnapshot to store each element's starting rect and
/// rotation, saving about 80% memory compared to full ElementState.
@immutable
final class ResizeEditContext extends EditContext {
  const ResizeEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.resizeMode,
    required this.handleOffset,
    required this.rotation,
    required this.elementSnapshots,
    this.selectionPadding = 0.0,
  });
  final ResizeMode resizeMode;
  final DrawPoint handleOffset;
  final double rotation;
  final double selectionPadding;

  /// Starting geometry for each element (lean snapshot).
  final Map<String, ElementResizeSnapshot> elementSnapshots;

  @override
  bool get hasSnapshots => elementSnapshots.isNotEmpty;

  bool get hasRotation => rotation != 0.0;

  /// Get the starting geometry for an element.
  ElementResizeSnapshot? getStartGeometry(String id) => elementSnapshots[id];
}

/// Context for rotate operations.
///
/// Uses ElementRotateSnapshot to store each element's starting center and
/// rotation, saving about 88% memory compared to full ElementState.
@immutable
final class RotateEditContext extends EditContext {
  const RotateEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.startAngle,
    required this.baseRotation,
    required this.rotationSnapAngle,
    required this.elementSnapshots,
  });

  /// Pointer angle around [startCenter] at start (raw atan2 angle).
  final double startAngle;

  /// Base rotation at start (single-select: element rotation; multi-select:
  /// overlay rotation).
  final double baseRotation;

  /// Discrete snap interval for rotation (radians).
  final double rotationSnapAngle;

  /// Starting rotation info for each element (lean snapshot).
  final Map<String, ElementRotateSnapshot> elementSnapshots;

  @override
  bool get hasSnapshots => elementSnapshots.isNotEmpty;

  /// Get the starting rotation for an element.
  ElementRotateSnapshot? getStartRotation(String id) => elementSnapshots[id];
}
