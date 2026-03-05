import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bindable_candidates.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';

enum ArrowBindingMode { inside, orbit }

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
      anchor: DrawPoint(x: _clamp01(anchor.x), y: _clamp01(anchor.y)),
      mode: mode,
    );
  }

  final String elementId;

  /// Normalized anchor in the target element's unrotated rect (0..1).
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
/// All binding resolution delegates to `snow_draw_arrow_core`.
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
    required ArrowCoreBindableCandidates candidates,
    required double snapDistance,
    ArrowBinding? preferredBinding,
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
    required ArrowCoreBindableCandidates candidates,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? preferredBinding,
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
    allowNewBinding: allowNewBinding,
    referencePoint: null,
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
      candidates: ArrowCoreBindableCandidates(
        elements: <ElementState>[target],
        bindables: <core.BindableState>[bindable],
      ),
      snapDistance: snapDistance,
      referencePoint: referencePoint,
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
      candidates: ArrowCoreBindableCandidates(
        elements: <ElementState>[target],
        bindables: <core.BindableState>[bindable],
      ),
      snapDistance: snapDistance,
      hasArrowhead: hasArrowhead,
      angleLocked: angleLocked,
      altKey: altKey,
      coreEngineContext: coreEngineContext,
    );
  }

  static DrawPoint? resolveBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    DrawPoint? referencePoint,
  }) => _resolveBoundPointViaCore(
    binding: binding,
    target: target,
    elbowed: false,
    referencePoint: referencePoint,
  );

  static DrawPoint? resolveElbowBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    required bool hasArrowhead,
  }) => _resolveBoundPointViaCore(
    binding: binding,
    target: target,
    elbowed: true,
    hasArrowhead: hasArrowhead,
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
      fixedPoint: <double>[
        _clamp01(binding.anchor.x),
        _clamp01(binding.anchor.y),
      ],
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
      anchor: DrawPoint(x: _clamp01(normalized.x), y: _clamp01(normalized.y)),
      mode: mode,
    );
  }
}

ArrowBindingResult? _resolveBindingCandidateViaCore({
  required DrawPoint worldPoint,
  required ArrowCoreBindableCandidates candidates,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
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
        bindable.id != preferredElementId) {
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
            _clamp01(preferredBinding.anchor.x),
            _clamp01(preferredBinding.anchor.y),
          ],
          mode: _toCoreBindingMode(preferredBinding.mode),
        );

  final previewArrow = core.ArrowState(
    id: '__binding-preview__',
    x: normalized.x,
    y: normalized.y,
    width: normalized.width,
    height: normalized.height,
    points: normalized.points,
    startBinding: dragStart ? preferredCoreBinding : null,
    endBinding: dragStart ? null : preferredCoreBinding,
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

  final result = computeCoreSimpleBindingPatch(
    arrow: previewArrow,
    draggedPoints: <int, core.Point>{
      dragStart ? 0 : previewArrow.points.length - 1: localPointer,
    },
    pointer: _toCorePoint(worldPoint),
    bindables: bindables,
    context: coreEngineContext ?? core.defaultEngineContext,
    options: <String, dynamic>{
      'complexBindings': true,
      if (newArrow) 'newArrow': true,
      if (initialBinding) 'initialBinding': true,
      if (preserveOppositeInsideBinding) 'preserveOppositeInsideBinding': true,
      if (oppositeOrbitFocusPoint != null)
        'oppositeOrbitFocusPoint': _toCorePoint(oppositeOrbitFocusPoint),
      if (angleLocked) 'angleLocked': true,
      if (altKey) 'altKey': true,
    },
  );

  final nextArrow = core.applyArrowPatch(previewArrow, result.arrowPatch);
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
        x: _clamp01(nextBinding.fixedPoint[0]),
        y: _clamp01(nextBinding.fixedPoint[1]),
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
}) {
  final bindable = toCoreBindableState(target);
  if (bindable == null || binding.elementId != bindable.id) {
    return null;
  }

  final coreBinding = core.FixedPointBinding(
    elementId: binding.elementId,
    fixedPoint: <double>[
      _clamp01(binding.anchor.x),
      _clamp01(binding.anchor.y),
    ],
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
    bindablesById: <String, core.BindableState>{bindable.id: bindable},
  );
  if (local == null) {
    return focusPoint;
  }
  return DrawPoint(x: arrow.x + local[0], y: arrow.y + local[1]);
}

core.Point _toCorePoint(DrawPoint point) => <double>[point.x, point.y];

ArrowBindingMode _fromCoreBindingMode(String mode) =>
    mode == core.bindModeInside
    ? ArrowBindingMode.inside
    : ArrowBindingMode.orbit;

String _toCoreBindingMode(ArrowBindingMode mode) =>
    mode == ArrowBindingMode.inside ? core.bindModeInside : core.bindModeOrbit;

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

double _clamp01(double value) {
  if (!value.isFinite) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

const _defaultMaxCoordinate = 1e6;
const _bindingHitToleranceFactor = 0.4;
const _previewSpanMultiplier = 3.0;

ArrowCoreBindableCandidates _collectCoreBindableCandidatesFromTargets(
  Iterable<ElementState> targets,
) {
  final seenIds = <String>{};
  final elements = <ElementState>[];
  final bindables = <core.BindableState>[];
  for (final target in targets) {
    if (target.opacity <= 0 ||
        !ArrowBindingUtils.isBindableTarget(target) ||
        !seenIds.add(target.id)) {
      continue;
    }
    final bindable = toCoreBindableState(target);
    if (bindable == null) {
      continue;
    }
    elements.add(target);
    bindables.add(bindable);
  }
  if (bindables.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }
  return ArrowCoreBindableCandidates(
    elements: List<ElementState>.unmodifiable(elements),
    bindables: List<core.BindableState>.unmodifiable(bindables),
  );
}
