import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_scene.dart';

enum ArrowBindingMode { inside, orbit, skip }

@immutable
final class ArrowBinding {
  const ArrowBinding({
    required this.elementId,
    required this.anchor,
    this.mode = ArrowBindingMode.orbit,
  });

  factory ArrowBinding.fromJson(Map<String, dynamic> json) {
    final elementId = ElementDataCodec.decodeString(
      json['elementId'],
      fieldName: 'elementId',
    );
    final anchor = ElementDataCodec.decodePoint(
      json['anchor'],
      fieldName: 'anchor',
    );
    final mode = ElementDataCodec.decodeEnumByName(
      values: ArrowBindingMode.values,
      raw: json['mode'],
      fieldName: 'mode',
    );
    return ArrowBinding(
      elementId: elementId,
      anchor: _normalizeFixedPoint(anchor),
      mode: mode,
    );
  }

  final String elementId;

  /// Fixed-point ratio in the target element's unrotated rect space.
  ///
  /// Values are typically within `0..1`, but can be outside that range for
  /// some repaired or transformed bindings, matching Excalidraw semantics.
  final DrawPoint anchor;
  final ArrowBindingMode mode;

  ArrowBinding copyWith({
    String? elementId,
    DrawPoint? anchor,
    ArrowBindingMode? mode,
  }) => ArrowBinding(
    elementId: elementId ?? this.elementId,
    anchor: anchor ?? this.anchor,
    mode: mode ?? this.mode,
  );

  Map<String, dynamic> toJson() => {
    'elementId': elementId,
    'anchor': {'x': anchor.x, 'y': anchor.y},
    'mode': mode.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowBinding &&
          other.elementId == elementId &&
          other.anchor == anchor &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(elementId, anchor, mode);
}

@immutable
final class ArrowBindingResult {
  const ArrowBindingResult({
    required this.binding,
    required this.snapPoint,
    required this.distance,
    required this.zIndex,
  });

  final ArrowBinding binding;
  final DrawPoint snapPoint;
  final double distance;
  final int zIndex;
}

/// Bridge utilities that project engine element state into arrow-core binding
/// primitives.
///
/// All binding resolution delegates to the shared arrow helpers.
class ArrowBindingUtils {
  const ArrowBindingUtils._();

  static const double elbowBindingGapBase = core.baseBindingGapElbow;
  static const double elbowArrowheadGapMultiplier =
      core.baseBindingGap / core.baseBindingGapElbow;

  static bool isBindableTarget(ElementState target) =>
      toCoreBindableState(target) != null;

  /// Returns whether either endpoint binding targets any id in [targetIds].
  static bool isBoundToAnyTargets({
    required ArrowBinding? startBinding,
    required ArrowBinding? endBinding,
    required Set<String> targetIds,
  }) {
    if (targetIds.isEmpty) {
      return false;
    }
    final startTargetId = startBinding?.elementId;
    if (startTargetId != null && targetIds.contains(startTargetId)) {
      return true;
    }
    final endTargetId = endBinding?.elementId;
    return endTargetId != null && targetIds.contains(endTargetId);
  }

  static double resolveBindingGap({required ElementState target}) {
    final bindable = toCoreBindableState(target);
    if (bindable == null) {
      return core.baseBindingGap;
    }
    return resolveCoreBindingGap(bindable: bindable, elbowed: false);
  }

  static double resolveBindingSearchDistance(double snapDistance) =>
      snapDistance * (1 + _bindingHitToleranceFactor);

  static ArrowBindingResult? resolveBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    ArrowBinding? preferredBinding,
    ArrowBinding? oppositeBinding,
    bool allowNewBinding = true,
    DrawPoint? referencePoint,
    bool dragStart = false,
    bool newArrow = false,
    bool initialBinding = false,
    bool preserveOppositeInsideBinding = false,
    DrawPoint? oppositeOrbitFocusPoint,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) {
    final candidates = _collectCoreBindableCandidatesFromTargets(targets);
    if (candidates.isEmpty) {
      return null;
    }
    return resolveBindingCandidateFromCoreCandidates(
      worldPoint: worldPoint,
      candidates: candidates,
      snapDistance: snapDistance,
      preferredBinding: preferredBinding,
      oppositeBinding: oppositeBinding,
      allowNewBinding: allowNewBinding,
      referencePoint: referencePoint,
      dragStart: dragStart,
      newArrow: newArrow,
      initialBinding: initialBinding,
      preserveOppositeInsideBinding: preserveOppositeInsideBinding,
      oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
      angleLocked: angleLocked,
      altKey: altKey,
      coreEngineContext: coreEngineContext,
    );
  }

  static ArrowBindingResult? resolveBindingCandidateFromCoreCandidates({
    required DrawPoint worldPoint,
    required ArrowBindableCandidates candidates,
    required double snapDistance,
    ArrowBinding? preferredBinding,
    ArrowBinding? oppositeBinding,
    bool allowNewBinding = true,
    DrawPoint? referencePoint,
    bool dragStart = false,
    bool newArrow = false,
    bool initialBinding = false,
    bool preserveOppositeInsideBinding = false,
    DrawPoint? oppositeOrbitFocusPoint,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) => _resolveBindingCandidateViaCore(
    worldPoint: worldPoint,
    candidates: candidates,
    snapDistance: snapDistance,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
    allowNewBinding: allowNewBinding,
    referencePoint: referencePoint,
    elbowed: false,
    dragStart: dragStart,
    newArrow: newArrow,
    initialBinding: initialBinding,
    preserveOppositeInsideBinding: preserveOppositeInsideBinding,
    oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
    angleLocked: angleLocked,
    altKey: altKey,
    coreEngineContext: coreEngineContext,
  );

  static ArrowBindingResult? resolveElbowBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? preferredBinding,
    ArrowBinding? oppositeBinding,
    DrawPoint? referencePoint,
    bool allowNewBinding = true,
    bool dragStart = false,
    bool newArrow = false,
    bool initialBinding = false,
    bool preserveOppositeInsideBinding = false,
    DrawPoint? oppositeOrbitFocusPoint,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) {
    final candidates = _collectCoreBindableCandidatesFromTargets(targets);
    if (candidates.isEmpty) {
      return null;
    }
    return resolveElbowBindingCandidateFromCoreCandidates(
      worldPoint: worldPoint,
      candidates: candidates,
      snapDistance: snapDistance,
      hasArrowhead: hasArrowhead,
      preferredBinding: preferredBinding,
      oppositeBinding: oppositeBinding,
      referencePoint: referencePoint,
      allowNewBinding: allowNewBinding,
      dragStart: dragStart,
      newArrow: newArrow,
      initialBinding: initialBinding,
      preserveOppositeInsideBinding: preserveOppositeInsideBinding,
      oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
      angleLocked: angleLocked,
      altKey: altKey,
      coreEngineContext: coreEngineContext,
    );
  }

  static ArrowBindingResult? resolveElbowBindingCandidateFromCoreCandidates({
    required DrawPoint worldPoint,
    required ArrowBindableCandidates candidates,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? preferredBinding,
    ArrowBinding? oppositeBinding,
    DrawPoint? referencePoint,
    bool allowNewBinding = true,
    bool dragStart = false,
    bool newArrow = false,
    bool initialBinding = false,
    bool preserveOppositeInsideBinding = false,
    DrawPoint? oppositeOrbitFocusPoint,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) => _resolveBindingCandidateViaCore(
    worldPoint: worldPoint,
    candidates: candidates,
    snapDistance: snapDistance,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
    allowNewBinding: allowNewBinding,
    referencePoint: referencePoint,
    elbowed: true,
    hasArrowhead: hasArrowhead,
    dragStart: dragStart,
    newArrow: newArrow,
    initialBinding: initialBinding,
    preserveOppositeInsideBinding: preserveOppositeInsideBinding,
    oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
    angleLocked: angleLocked,
    altKey: altKey,
    coreEngineContext: coreEngineContext,
  );

  /// Resolves a single-target binding candidate without list iteration.
  ///
  /// Use this for hot paths that already resolved the target element.
  static ArrowBindingResult? resolveBindingCandidateForTarget({
    required DrawPoint worldPoint,
    required ElementState target,
    required double snapDistance,
    DrawPoint? referencePoint,
    ArrowBinding? oppositeBinding,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) {
    if (snapDistance <= 0 || target.opacity <= 0) {
      return null;
    }
    final bindable = toCoreBindableState(target);
    if (bindable == null) {
      return null;
    }
    return resolveBindingCandidateFromCoreCandidates(
      worldPoint: worldPoint,
      candidates: ArrowBindableCandidates(
        elements: <ElementState>[target],
        bindables: <core.BindableState>[bindable],
      ),
      snapDistance: snapDistance,
      referencePoint: referencePoint,
      oppositeBinding: oppositeBinding,
      angleLocked: angleLocked,
      altKey: altKey,
      coreEngineContext: coreEngineContext,
    );
  }

  /// Resolves a single-target elbow binding candidate without list iteration.
  ///
  /// Use this for hot paths that already resolved the target element.
  static ArrowBindingResult? resolveElbowBindingCandidateForTarget({
    required DrawPoint worldPoint,
    required ElementState target,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? oppositeBinding,
    DrawPoint? referencePoint,
    bool angleLocked = false,
    bool altKey = false,
    core.EngineContext? coreEngineContext,
  }) {
    if (snapDistance <= 0 || target.opacity <= 0) {
      return null;
    }
    final bindable = toCoreBindableState(target);
    if (bindable == null) {
      return null;
    }
    return resolveElbowBindingCandidateFromCoreCandidates(
      worldPoint: worldPoint,
      candidates: ArrowBindableCandidates(
        elements: <ElementState>[target],
        bindables: <core.BindableState>[bindable],
      ),
      snapDistance: snapDistance,
      hasArrowhead: hasArrowhead,
      oppositeBinding: oppositeBinding,
      referencePoint: referencePoint,
      angleLocked: angleLocked,
      altKey: altKey,
      coreEngineContext: coreEngineContext,
    );
  }

  static DrawPoint? resolveBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    DrawPoint? referencePoint,
    Iterable<core.BindableState>? bindables,
  }) => _resolveBoundPointViaCore(
    binding: binding,
    target: target,
    elbowed: false,
    referencePoint: referencePoint,
    bindables: bindables,
  );

  static DrawPoint? resolveElbowBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    required bool hasArrowhead,
    Iterable<core.BindableState>? bindables,
  }) => _resolveBoundPointViaCore(
    binding: binding,
    target: target,
    elbowed: true,
    hasArrowhead: hasArrowhead,
    bindables: bindables,
  );

  static DrawPoint? resolveElbowAnchorPoint({
    required ArrowBinding binding,
    required ElementState target,
  }) {
    final bindable = toCoreBindableState(target);
    if (bindable == null || binding.elementId != bindable.id) {
      return null;
    }
    final coreBinding = core.FixedPointBinding(
      elementId: binding.elementId,
      fixedPoint: <double>[binding.anchor.x, binding.anchor.y],
      mode: _toCoreBindingMode(binding.mode),
    );
    final global = resolveCoreGlobalFixedPoint(
      binding: coreBinding,
      bindable: bindable,
    );
    return DrawPoint(x: global[0], y: global[1]);
  }

  static ArrowBinding? bindingFromLocalPoint({
    required ElementState target,
    required DrawPoint localPoint,
    ArrowBindingMode mode = ArrowBindingMode.orbit,
  }) {
    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }
    final normalized = DrawPoint(
      x: (localPoint.x - rect.minX) / rect.width,
      y: (localPoint.y - rect.minY) / rect.height,
    );
    return ArrowBinding(
      elementId: target.id,
      anchor: _normalizeFixedPoint(normalized),
      mode: mode,
    );
  }
}

ArrowBindingResult? _resolveBindingCandidateViaCore({
  required DrawPoint worldPoint,
  required ArrowBindableCandidates candidates,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
  required ArrowBinding? oppositeBinding,
  required bool allowNewBinding,
  required DrawPoint? referencePoint,
  required bool elbowed,
  required bool dragStart,
  bool newArrow = false,
  bool initialBinding = false,
  bool preserveOppositeInsideBinding = false,
  DrawPoint? oppositeOrbitFocusPoint,
  bool hasArrowhead = false,
  bool angleLocked = false,
  bool altKey = false,
  core.EngineContext? coreEngineContext,
}) {
  if (snapDistance <= 0) {
    return null;
  }

  final preferredElementId = preferredBinding?.elementId;
  final oppositeElementId = oppositeBinding?.elementId;
  if (!allowNewBinding && preferredElementId == null) {
    return null;
  }
  if (candidates.isEmpty) {
    return null;
  }

  final targetById = candidates.elementById;
  if (targetById.isEmpty) {
    return null;
  }
  final bindables = <core.BindableState>[];
  for (final bindable in candidates.bindables) {
    if (candidates.elementForId(bindable.id) == null) {
      continue;
    }
    if (!allowNewBinding &&
        preferredElementId != null &&
        bindable.id != preferredElementId &&
        bindable.id != oppositeElementId) {
      continue;
    }
    bindables.add(bindable);
  }

  if (bindables.isEmpty) {
    return null;
  }
  if (!allowNewBinding &&
      preferredElementId != null &&
      !targetById.containsKey(preferredElementId)) {
    return null;
  }

  final oppositePoint =
      referencePoint ??
      DrawPoint(
        x: worldPoint.x - math.max(1, snapDistance * _previewSpanMultiplier),
        y: worldPoint.y,
      );
  final normalizedPoints = dragStart
      ? <core.Point>[_toCorePoint(worldPoint), _toCorePoint(oppositePoint)]
      : <core.Point>[_toCorePoint(oppositePoint), _toCorePoint(worldPoint)];
  final normalized = core.normalizeArrowFromGlobalPoints(
    normalizedPoints,
    _defaultMaxCoordinate,
  );

  final preferredCoreBinding = preferredBinding == null
      ? null
      : core.FixedPointBinding(
          elementId: preferredBinding.elementId,
          fixedPoint: <double>[
            preferredBinding.anchor.x,
            preferredBinding.anchor.y,
          ],
          mode: _toCoreBindingMode(preferredBinding.mode),
        );
  final oppositeCoreBinding = oppositeBinding == null
      ? null
      : core.FixedPointBinding(
          elementId: oppositeBinding.elementId,
          fixedPoint: <double>[
            oppositeBinding.anchor.x,
            oppositeBinding.anchor.y,
          ],
          mode: _toCoreBindingMode(oppositeBinding.mode),
        );

  final previewArrow = core.ArrowState(
    id: '__binding-preview__',
    x: normalized.x,
    y: normalized.y,
    width: normalized.width,
    height: normalized.height,
    points: normalized.points,
    startBinding: dragStart ? preferredCoreBinding : oppositeCoreBinding,
    endBinding: dragStart ? oppositeCoreBinding : preferredCoreBinding,
    startArrowhead: elbowed && hasArrowhead && dragStart ? 'arrow' : null,
    endArrowhead: elbowed && hasArrowhead && !dragStart ? 'arrow' : null,
    elbowed: elbowed,
    fixedSegments: null,
    startIsSpecial: null,
    endIsSpecial: null,
  );
  final localPointer = <double>[
    worldPoint.x - previewArrow.x,
    worldPoint.y - previewArrow.y,
  ];

  final strategies = resolveCoreEndpointBindingStrategy(
    arrow: previewArrow,
    draggedPoints: <int, core.Point>{
      dragStart ? 0 : previewArrow.points.length - 1: localPointer,
    },
    pointer: _toCorePoint(worldPoint),
    bindables: bindables,
    context: coreEngineContext ?? core.defaultEngineContext,
    options: ArrowCoreEndpointBindingOptions(
      newArrow: newArrow,
      initialBinding: initialBinding,
      preserveOppositeInsideBinding: preserveOppositeInsideBinding,
      oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
      angleLocked: angleLocked,
      altKey: altKey,
    ),
  );
  final strategy = dragStart ? strategies.start : strategies.end;
  final edge = dragStart ? core.arrowEndpointStart : core.arrowEndpointEnd;

  var nextArrow = previewArrow;
  if (strategy != null) {
    if (strategy.mode == null) {
      final mutation = unbindCoreArrowEndpoint(arrow: previewArrow, edge: edge);
      nextArrow = core.applyArrowPatch(previewArrow, mutation.arrowPatch);
    } else if (strategy.element != null && strategy.focusPoint != null) {
      final mutation = bindCoreArrowEndpoint(
        arrow: previewArrow,
        edge: edge,
        bindable: strategy.element!,
        mode: strategy.mode,
        focusPoint: strategy.focusPoint,
      );
      nextArrow = core.applyArrowPatch(previewArrow, mutation.arrowPatch);
    }
  }
  final nextBinding = dragStart ? nextArrow.startBinding : nextArrow.endBinding;
  if (nextBinding == null) {
    return null;
  }
  if (!allowNewBinding &&
      preferredElementId != null &&
      nextBinding.elementId != preferredElementId) {
    return null;
  }

  final target = targetById[nextBinding.elementId];
  if (target == null) {
    return null;
  }

  final endpoint = _arrowWorldEndpoint(nextArrow, dragStart: dragStart);
  return ArrowBindingResult(
    binding: ArrowBinding(
      elementId: nextBinding.elementId,
      anchor: DrawPoint(
        x: nextBinding.fixedPoint[0],
        y: nextBinding.fixedPoint[1],
      ),
      mode: _fromCoreBindingMode(nextBinding.mode),
    ),
    snapPoint: endpoint,
    distance: worldPoint.distance(endpoint),
    zIndex: target.zIndex,
  );
}

DrawPoint? _resolveBoundPointViaCore({
  required ArrowBinding binding,
  required ElementState target,
  required bool elbowed,
  DrawPoint? referencePoint,
  bool hasArrowhead = false,
  Iterable<core.BindableState>? bindables,
}) {
  final bindableList = <core.BindableState>[...?bindables];
  final bindablesById = <String, core.BindableState>{
    for (final candidate in bindableList) candidate.id: candidate,
  };
  final bindable = bindablesById[target.id] ?? toCoreBindableState(target);
  if (bindable == null || binding.elementId != bindable.id) {
    return null;
  }
  bindablesById.putIfAbsent(bindable.id, () => bindable);

  final coreBinding = core.FixedPointBinding(
    elementId: binding.elementId,
    fixedPoint: <double>[binding.anchor.x, binding.anchor.y],
    mode: _toCoreBindingMode(binding.mode),
  );
  final focus = core.getGlobalFixedPoint(coreBinding, bindable);
  final focusPoint = DrawPoint(x: focus[0], y: focus[1]);
  final otherPoint =
      referencePoint ??
      DrawPoint(
        x: focusPoint.x + math.max(1, bindable.strokeWidth),
        y: focusPoint.y,
      );

  final normalized = core.normalizeArrowFromGlobalPoints(<core.Point>[
    _toCorePoint(focusPoint),
    _toCorePoint(otherPoint),
  ], _defaultMaxCoordinate);
  final arrow = core.ArrowState(
    id: '__binding-bound-point__',
    x: normalized.x,
    y: normalized.y,
    width: normalized.width,
    height: normalized.height,
    points: normalized.points,
    startBinding: coreBinding,
    endBinding: null,
    startArrowhead: elbowed && hasArrowhead ? 'arrow' : null,
    endArrowhead: null,
    elbowed: elbowed,
    fixedSegments: null,
    startIsSpecial: null,
    endIsSpecial: null,
  );

  final local = updateCoreBoundPoint(
    arrow: arrow,
    edge: 'startBinding',
    binding: coreBinding,
    bindable: bindable,
    bindablesById: bindablesById,
  );
  if (local == null) {
    return focusPoint;
  }
  return DrawPoint(x: arrow.x + local[0], y: arrow.y + local[1]);
}

core.Point _toCorePoint(DrawPoint point) => <double>[point.x, point.y];

ArrowBindingMode _fromCoreBindingMode(String mode) => switch (mode) {
  core.bindModeInside => ArrowBindingMode.inside,
  core.bindModeSkip => ArrowBindingMode.skip,
  _ => ArrowBindingMode.orbit,
};

String _toCoreBindingMode(ArrowBindingMode mode) => switch (mode) {
  ArrowBindingMode.inside => core.bindModeInside,
  ArrowBindingMode.skip => core.bindModeSkip,
  ArrowBindingMode.orbit => core.bindModeOrbit,
};

DrawPoint _arrowWorldEndpoint(
  core.ArrowState arrow, {
  required bool dragStart,
}) {
  if (arrow.points.isEmpty) {
    return DrawPoint(x: arrow.x, y: arrow.y);
  }
  final endpoint = dragStart ? arrow.points.first : arrow.points.last;
  return DrawPoint(x: arrow.x + endpoint[0], y: arrow.y + endpoint[1]);
}

DrawPoint _normalizeFixedPoint(DrawPoint point) => DrawPoint(
  x: _resolveNormalizedFixedRatioX(point),
  y: _resolveNormalizedFixedRatioY(point),
);

double _resolveNormalizedFixedRatioX(DrawPoint point) {
  if (!_isFiniteFixedPoint(point)) {
    return 0.5001;
  }
  return _resolveHalfEpsilonRatio(point.x);
}

double _resolveNormalizedFixedRatioY(DrawPoint point) {
  if (!_isFiniteFixedPoint(point)) {
    return 0.5001;
  }
  return _resolveHalfEpsilonRatio(point.y);
}

bool _isFiniteFixedPoint(DrawPoint point) =>
    point.x.isFinite && point.y.isFinite;

double _resolveHalfEpsilonRatio(double value) {
  const epsilon = 0.0001;
  if ((value - 0.5).abs() < epsilon) {
    return 0.5001;
  }
  return value;
}

const _defaultMaxCoordinate = 1e6;
const _bindingHitToleranceFactor = 0.4;
const _previewSpanMultiplier = 3.0;

ArrowBindableCandidates _collectCoreBindableCandidatesFromTargets(
  Iterable<ElementState> targets,
) => projectArrowBindableCandidates(elements: targets);
