import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../shared/element_data_codec.dart';
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
    return core.getBindingGap(bindable, false);
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
    bool angleLocked = false,
    bool altKey = false,
  }) => _resolveBindingCandidateViaCore(
    worldPoint: worldPoint,
    targets: targets,
    snapDistance: snapDistance,
    preferredBinding: preferredBinding,
    allowNewBinding: allowNewBinding,
    referencePoint: referencePoint,
    elbowed: false,
    angleLocked: angleLocked,
    altKey: altKey,
  );

  static ArrowBindingResult? resolveElbowBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? preferredBinding,
    bool allowNewBinding = true,
    bool angleLocked = false,
    bool altKey = false,
  }) => _resolveBindingCandidateViaCore(
    worldPoint: worldPoint,
    targets: targets,
    snapDistance: snapDistance,
    preferredBinding: preferredBinding,
    allowNewBinding: allowNewBinding,
    referencePoint: null,
    elbowed: true,
    hasArrowhead: hasArrowhead,
    angleLocked: angleLocked,
    altKey: altKey,
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
  }) {
    if (snapDistance <= 0 || target.opacity <= 0) {
      return null;
    }
    return _resolveBindingCandidateViaCore(
      worldPoint: worldPoint,
      targets: <ElementState>[target],
      snapDistance: snapDistance,
      preferredBinding: null,
      allowNewBinding: true,
      referencePoint: referencePoint,
      elbowed: false,
      angleLocked: angleLocked,
      altKey: altKey,
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
  }) {
    if (snapDistance <= 0 || target.opacity <= 0) {
      return null;
    }
    return _resolveBindingCandidateViaCore(
      worldPoint: worldPoint,
      targets: <ElementState>[target],
      snapDistance: snapDistance,
      preferredBinding: null,
      allowNewBinding: true,
      referencePoint: null,
      elbowed: true,
      hasArrowhead: hasArrowhead,
      angleLocked: angleLocked,
      altKey: altKey,
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
    final global = core.getGlobalFixedPoint(coreBinding, bindable);
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
  required Iterable<ElementState> targets,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
  required bool allowNewBinding,
  required DrawPoint? referencePoint,
  required bool elbowed,
  bool hasArrowhead = false,
  bool angleLocked = false,
  bool altKey = false,
}) {
  if (snapDistance <= 0) {
    return null;
  }

  final preferredElementId = preferredBinding?.elementId;
  if (!allowNewBinding && preferredElementId == null) {
    return null;
  }

  final targetById = <String, ElementState>{};
  final bindables = <core.BindableState>[];
  for (final target in targets) {
    if (target.opacity <= 0 || !ArrowBindingUtils.isBindableTarget(target)) {
      continue;
    }
    if (!allowNewBinding &&
        preferredElementId != null &&
        target.id != preferredElementId) {
      continue;
    }
    final bindable = toCoreBindableState(target);
    if (bindable == null) {
      continue;
    }
    targetById[target.id] = target;
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
  final normalized = core.normalizeArrowFromGlobalPoints(<core.Point>[
    _toCorePoint(oppositePoint),
    _toCorePoint(worldPoint),
  ], _defaultMaxCoordinate);

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
    startBinding: null,
    endBinding: preferredCoreBinding,
    startArrowhead: null,
    endArrowhead: elbowed && hasArrowhead ? 'arrow' : null,
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
      previewArrow.points.length - 1: localPointer,
    },
    pointer: _toCorePoint(worldPoint),
    bindables: bindables,
    context: core.defaultEngineContext,
    options: <String, dynamic>{
      'complexBindings': true,
      if (referencePoint == null) 'newArrow': true,
      if (angleLocked) 'angleLocked': true,
      if (altKey) 'altKey': true,
    },
  );

  final nextArrow = core.applyArrowPatch(previewArrow, result.arrowPatch);
  final nextBinding = nextArrow.endBinding;
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

  final endpoint = _arrowWorldEndpoint(nextArrow);
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

  final local = core.updateBoundPoint(
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

DrawPoint _arrowWorldEndpoint(core.ArrowState arrow) {
  if (arrow.points.isEmpty) {
    return DrawPoint(x: arrow.x, y: arrow.y);
  }
  final endpoint = arrow.points.last;
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
