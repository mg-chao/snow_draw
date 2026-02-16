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
  PointerMoveInputEvent({
    required super.position,
    required super.modifiers,
    super.pressure,
    List<DrawPoint> sampledPoints = const <DrawPoint>[],
  }) : sampledPoints = _freezeSampledPoints(
         sampledPoints: sampledPoints,
         position: position,
       );

  /// Coalesced pointer samples represented by this event.
  ///
  /// When empty, [position] is the sole sample.
  final List<DrawPoint> sampledPoints;

  /// Total number of pointer samples represented by this event.
  int get sampleCount => sampledPoints.isEmpty ? 1 : sampledPoints.length;

  /// Returns all pointer samples in draw order.
  Iterable<DrawPoint> samples() sync* {
    if (sampledPoints.isEmpty) {
      yield position;
      return;
    }
    yield* sampledPoints;
  }

  /// Merges this event with [next], preserving sample order.
  ///
  /// The merged event uses [next]'s position/modifiers/pressure and keeps all
  /// intermediate samples from both events.
  PointerMoveInputEvent mergeWith(PointerMoveInputEvent next) {
    final merged = <DrawPoint>[];

    void appendSample(DrawPoint point) {
      if (merged.isEmpty || merged.last != point) {
        merged.add(point);
      }
    }

    void appendEventSamples(PointerMoveInputEvent event) {
      for (final point in event.samples()) {
        appendSample(point);
      }
    }

    appendEventSamples(this);
    appendEventSamples(next);

    return PointerMoveInputEvent(
      position: next.position,
      modifiers: next.modifiers,
      pressure: next.pressure,
      sampledPoints: merged,
    );
  }

  @override
  String toString() =>
      'PointerMoveInputEvent($position, $modifiers, samples: $sampleCount)';
}

List<DrawPoint> _freezeSampledPoints({
  required List<DrawPoint> sampledPoints,
  required DrawPoint position,
}) {
  if (sampledPoints.isEmpty) {
    return const <DrawPoint>[];
  }
  if (sampledPoints.last == position) {
    return List<DrawPoint>.unmodifiable(sampledPoints);
  }
  final normalized = List<DrawPoint>.of(sampledPoints)..add(position);
  return List<DrawPoint>.unmodifiable(normalized);
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
