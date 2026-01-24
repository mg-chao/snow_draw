import 'package:meta/meta.dart';

/// Edit-time keyboard modifiers coming from the UI/input layer.
@immutable
class EditModifiers {
  // Shift (rotate)

  const EditModifiers({
    this.maintainAspectRatio = false,
    this.fromCenter = false,
    this.discreteAngle = false,
    this.snapOverride = false,
  });
  final bool maintainAspectRatio; // Shift
  final bool fromCenter; // Alt
  final bool discreteAngle;
  final bool snapOverride; // Ctrl
}

/// Policy for handling update failures during edit sessions.
enum EditUpdateFailurePolicy { toIdle, keepState }
