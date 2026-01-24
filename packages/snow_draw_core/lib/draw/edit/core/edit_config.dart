import 'dart:math' as math;
import 'package:meta/meta.dart';

import '../../config/draw_config.dart';

/// Configuration for edit operations.
///
/// Includes all settings related to edit operations.
@immutable
class EditConfig {
  const EditConfig({
    this.dragThreshold = ConfigDefaults.dragThreshold,
    this.selectionPadding = ConfigDefaults.selectionPadding,
    this.handleTolerance = ConfigDefaults.handleTolerance,
    this.minElementSize = ConfigDefaults.minResizeElementSize,
    this.rotationSnapAngle = ConfigDefaults.rotationSnapAngle,
    this.rotationHandleOffset = ConfigDefaults.rotateHandleOffset,
  });
  // ============ Move configuration ============

  /// Drag detection threshold (pixels).
  ///
  /// Dragging starts only after movement exceeds this value.
  final double dragThreshold;

  // ============ Resize configuration ============

  /// Selection padding (pixels).
  ///
  /// Distance between the selection box and element bounds.
  final double selectionPadding;

  /// Handle hit tolerance (pixels).
  final double handleTolerance;

  /// Minimum element size (pixels).
  ///
  /// Minimum width and height during resize.
  final double minElementSize;

  // ============ Rotation configuration ============

  /// Rotation snap angle (radians).
  ///
  /// Alignment interval when holding Shift.
  /// Default: pi/12 (15 deg).
  final double rotationSnapAngle;

  /// Rotation handle offset (pixels).
  ///
  /// Distance from the selection box top to the rotation handle.
  final double rotationHandleOffset;

  /// Default configuration.
  static const defaults = EditConfig();

  /// Rotation snap angle in degrees (for display).
  double get rotationSnapAngleDegrees => rotationSnapAngle * 180 / math.pi;

  EditConfig copyWith({
    double? dragThreshold,
    double? selectionPadding,
    double? handleTolerance,
    double? minElementSize,
    double? rotationSnapAngle,
    double? rotationHandleOffset,
  }) => EditConfig(
    dragThreshold: dragThreshold ?? this.dragThreshold,
    selectionPadding: selectionPadding ?? this.selectionPadding,
    handleTolerance: handleTolerance ?? this.handleTolerance,
    minElementSize: minElementSize ?? this.minElementSize,
    rotationSnapAngle: rotationSnapAngle ?? this.rotationSnapAngle,
    rotationHandleOffset: rotationHandleOffset ?? this.rotationHandleOffset,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditConfig &&
          other.dragThreshold == dragThreshold &&
          other.selectionPadding == selectionPadding &&
          other.handleTolerance == handleTolerance &&
          other.minElementSize == minElementSize &&
          other.rotationSnapAngle == rotationSnapAngle &&
          other.rotationHandleOffset == rotationHandleOffset;

  @override
  int get hashCode => Object.hash(
    dragThreshold,
    selectionPadding,
    handleTolerance,
    minElementSize,
    rotationSnapAngle,
    rotationHandleOffset,
  );

  @override
  String toString() =>
      'EditConfig('
      'dragThreshold: $dragThreshold, '
      'selectionPadding: $selectionPadding, '
      'handleTolerance: $handleTolerance, '
      'minElementSize: $minElementSize, '
      'rotationSnapAngle: $rotationSnapAngle, '
      'rotationHandleOffset: $rotationHandleOffset'
      ')';
}
