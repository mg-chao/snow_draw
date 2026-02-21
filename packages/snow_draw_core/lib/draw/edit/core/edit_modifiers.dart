import 'package:meta/meta.dart';

/// Edit-time keyboard modifiers coming from the UI/input layer.
///
/// These flags represent transient modifier keys at the time an edit update is
/// processed.
@immutable
class EditModifiers {
  const EditModifiers({
    this.maintainAspectRatio = false,
    this.fromCenter = false,
    this.discreteAngle = false,
    this.snapOverride = false,
  });

  /// Keeps the edited bounds constrained to an aspect ratio when supported.
  final bool maintainAspectRatio;

  /// Resizes or transforms relative to the center when supported.
  final bool fromCenter;

  /// Applies discrete rotation snapping when supported.
  final bool discreteAngle;

  /// Overrides default snapping behavior when supported.
  final bool snapOverride;
}

/// Policy for handling update failures during edit sessions.
enum EditUpdateFailurePolicy { toIdle, keepState }
