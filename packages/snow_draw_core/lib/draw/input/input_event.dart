import 'package:meta/meta.dart';

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
}

/// Base class for input events passed from UI -> business.
abstract class InputEvent {
  const InputEvent({required this.position, required this.modifiers});

  /// World coordinate position.
  final DrawPoint position;

  /// Modifier keys state.
  final KeyModifiers modifiers;
}

class PointerDownInputEvent extends InputEvent {
  const PointerDownInputEvent({
    required super.position,
    required super.modifiers,
  });

  @override
  String toString() => 'PointerDownInputEvent($position, $modifiers)';
}

class PointerMoveInputEvent extends InputEvent {
  const PointerMoveInputEvent({
    required super.position,
    required super.modifiers,
  });

  @override
  String toString() => 'PointerMoveInputEvent($position, $modifiers)';
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
