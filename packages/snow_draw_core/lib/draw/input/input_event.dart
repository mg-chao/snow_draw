import 'package:meta/meta.dart';

import '../edit/core/edit_modifiers.dart';
import '../types/draw_point.dart';

/// Keyboard modifier state carried with input events.
@immutable
class KeyModifiers {
  const KeyModifiers({
    this.shift = false,
    this.control = false,
    this.alt = false,
  });
  final bool shift;
  final bool control;
  final bool alt;

  static const none = KeyModifiers();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyModifiers &&
          other.shift == shift &&
          other.control == control &&
          other.alt == alt;

  @override
  int get hashCode => Object.hash(shift, control, alt);

  @override
  String toString() => 'KeyModifiers(shift: $shift, ctrl: $control, alt: $alt)';

  /// Convert keyboard modifiers to edit-domain modifiers.
  ///
  /// Centralises the mapping so every plugin uses the same logic.
  EditModifiers toEditModifiers() => EditModifiers(
    maintainAspectRatio: shift,
    discreteAngle: shift,
    fromCenter: alt,
    snapOverride: control,
  );
}

/// Base class for input events passed from UI -> business.
abstract class InputEvent {
  const InputEvent({
    required this.position,
    required this.modifiers,
    this.pressure = 0.0,
  });

  /// World coordinate position.
  final DrawPoint position;

  /// Modifier keys state.
  final KeyModifiers modifiers;

  /// Pointer pressure in the range 0..1 (0 = unknown).
  final double pressure;
}

class PointerDownInputEvent extends InputEvent {
  const PointerDownInputEvent({
    required super.position,
    required super.modifiers,
    super.pressure,
  });

  @override
  String toString() => 'PointerDownInputEvent($position, $modifiers)';
}

class PointerMoveInputEvent extends InputEvent {
  const PointerMoveInputEvent({
    required super.position,
    required super.modifiers,
    super.pressure,
  });

  @override
  String toString() => 'PointerMoveInputEvent($position, $modifiers)';
}

class PointerHoverInputEvent extends InputEvent {
  const PointerHoverInputEvent({
    required super.position,
    required super.modifiers,
  });

  @override
  String toString() => 'PointerHoverInputEvent($position, $modifiers)';
}

class PointerUpInputEvent extends InputEvent {
  const PointerUpInputEvent({
    required super.position,
    required super.modifiers,
  });

  @override
  String toString() => 'PointerUpInputEvent($position, $modifiers)';
}

class PointerCancelInputEvent extends InputEvent {
  const PointerCancelInputEvent({
    required super.position,
    required super.modifiers,
  });

  @override
  String toString() => 'PointerCancelInputEvent($position, $modifiers)';
}
