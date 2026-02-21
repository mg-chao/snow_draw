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
  factory PointerMoveInputEvent({
    required DrawPoint position,
    required KeyModifiers modifiers,
    double pressure = 0.0,
    List<DrawPoint> sampledPoints = const <DrawPoint>[],
  }) {
    final normalizedSamples = _normalizePointerMoveSamples(
      sampledPoints: sampledPoints,
      position: position,
    );
    if (normalizedSamples.length == 1) {
      return PointerMoveInputEvent._internal(
        position: position,
        modifiers: modifiers,
        pressure: pressure,
        sampleNode: _PointerSampleSingle(normalizedSamples.first),
        sampledPointsCache: const <DrawPoint>[],
      );
    }

    final frozenSamples = List<DrawPoint>.unmodifiable(normalizedSamples);

    return PointerMoveInputEvent._internal(
      position: position,
      modifiers: modifiers,
      pressure: pressure,
      sampleNode: _PointerSampleLeaf(frozenSamples),
      sampledPointsCache: frozenSamples,
    );
  }

  PointerMoveInputEvent._internal({
    required super.position,
    required super.modifiers,
    required _PointerSampleNode sampleNode,
    super.pressure = 0.0,
    List<DrawPoint>? sampledPointsCache,
  }) : _sampleNode = sampleNode,
       _sampledPointsCache = sampledPointsCache;

  final _PointerSampleNode _sampleNode;
  List<DrawPoint>? _sampledPointsCache;

  /// Coalesced pointer samples represented by this event.
  ///
  /// When empty, [position] is the sole sample.
  List<DrawPoint> get sampledPoints {
    final cached = _sampledPointsCache;
    if (cached != null) {
      return cached;
    }

    final resolved = samples().toList(growable: false);
    if (resolved.length <= 1) {
      return _sampledPointsCache = const <DrawPoint>[];
    }

    return _sampledPointsCache = List<DrawPoint>.unmodifiable(resolved);
  }

  /// Total number of pointer samples represented by this event.
  int get sampleCount => _sampleNode.sampleCount;

  /// Returns all pointer samples in draw order.
  Iterable<DrawPoint> samples() sync* {
    final stack = <_PointerSampleNode>[_sampleNode];
    DrawPoint? previous;

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is _PointerSampleMerged) {
        stack
          ..add(node.right)
          ..add(node.left);
        continue;
      }

      if (node is _PointerSampleSingle) {
        final point = node.point;
        if (previous == point) {
          continue;
        }
        previous = point;
        yield point;
        continue;
      }

      final leaf = node as _PointerSampleLeaf;
      for (final point in leaf.points) {
        if (previous == point) {
          continue;
        }
        previous = point;
        yield point;
      }
    }
  }

  /// Merges this event with [next], preserving sample order.
  ///
  /// The merged event uses [next]'s position/modifiers/pressure and keeps all
  /// intermediate samples from both events.
  PointerMoveInputEvent mergeWith(PointerMoveInputEvent next) =>
      PointerMoveInputEvent._internal(
        position: next.position,
        modifiers: next.modifiers,
        pressure: next.pressure,
        sampleNode: _PointerSampleMerged(_sampleNode, next._sampleNode),
      );

  @override
  String toString() =>
      'PointerMoveInputEvent($position, $modifiers, samples: $sampleCount)';
}

List<DrawPoint> _normalizePointerMoveSamples({
  required List<DrawPoint> sampledPoints,
  required DrawPoint position,
}) {
  final normalized = <DrawPoint>[];

  void appendSample(DrawPoint point) {
    if (normalized.isEmpty || normalized.last != point) {
      normalized.add(point);
    }
  }

  for (final point in sampledPoints) {
    appendSample(point);
  }
  appendSample(position);
  return normalized;
}

sealed class _PointerSampleNode {
  const _PointerSampleNode({
    required this.sampleCount,
    required this.firstPoint,
    required this.lastPoint,
  });

  final int sampleCount;
  final DrawPoint firstPoint;
  final DrawPoint lastPoint;
}

final class _PointerSampleSingle extends _PointerSampleNode {
  _PointerSampleSingle(this.point)
    : super(sampleCount: 1, firstPoint: point, lastPoint: point);

  final DrawPoint point;
}

final class _PointerSampleLeaf extends _PointerSampleNode {
  _PointerSampleLeaf(this.points)
    : assert(points.isNotEmpty, 'Pointer sample leaf cannot be empty'),
      super(
        sampleCount: points.length,
        firstPoint: points.first,
        lastPoint: points.last,
      );

  final List<DrawPoint> points;
}

final class _PointerSampleMerged extends _PointerSampleNode {
  _PointerSampleMerged(this.left, this.right)
    : super(
        sampleCount:
            left.sampleCount +
            right.sampleCount -
            (left.lastPoint == right.firstPoint ? 1 : 0),
        firstPoint: left.firstPoint,
        lastPoint: right.lastPoint,
      );

  final _PointerSampleNode left;
  final _PointerSampleNode right;
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
