import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/selection_calculator.dart';
import '../rectangle/rectangle_data.dart';
import '../serial_number/serial_number_data.dart';
import '../serial_number/serial_number_layout.dart';
import '../shared/element_data_codec.dart';
import '../text/text_data.dart';
import 'arrow_core_ops.dart';
import 'elbow/elbow_geometry.dart';
import 'elbow/elbow_heading.dart';

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

class ArrowBindingUtils {
  const ArrowBindingUtils._();

  static const double elbowBindingGapBase = _elbowBindingGapBase;
  static const double elbowArrowheadGapMultiplier =
      _bindingArrowheadGapMultiplier;

  static bool isBindableTarget(ElementState target) {
    final data = target.data;
    return data is RectangleData ||
        data is TextData ||
        data is SerialNumberData;
  }

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

  static double resolveBindingGap({required ElementState target}) =>
      _resolveBindingGapViaCore(target) ?? _resolveBindingGap(target);

  static double resolveBindingSearchDistance(double snapDistance) =>
      snapDistance * (1 + _bindingHitToleranceFactor);

  static ArrowBindingResult? resolveBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    ArrowBinding? preferredBinding,
    bool allowNewBinding = true,
    DrawPoint? referencePoint,
  }) =>
      _resolveBindingCandidateViaCore(
        worldPoint: worldPoint,
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        referencePoint: referencePoint,
        elbowed: false,
      ) ??
      _resolveBestBindingCandidate(
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        resolver: (target) => _resolveBindingOnTarget(
          target: target,
          worldPoint: worldPoint,
          snapDistance: snapDistance,
          referencePoint: referencePoint,
        ),
      );

  static ArrowBindingResult? resolveElbowBindingCandidate({
    required DrawPoint worldPoint,
    required Iterable<ElementState> targets,
    required double snapDistance,
    required bool hasArrowhead,
    ArrowBinding? preferredBinding,
    bool allowNewBinding = true,
  }) =>
      _resolveBindingCandidateViaCore(
        worldPoint: worldPoint,
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        referencePoint: null,
        elbowed: true,
        hasArrowhead: hasArrowhead,
      ) ??
      _resolveBestBindingCandidate(
        targets: targets,
        snapDistance: snapDistance,
        preferredBinding: preferredBinding,
        allowNewBinding: allowNewBinding,
        resolver: (target) => _resolveElbowBindingOnTarget(
          target: target,
          worldPoint: worldPoint,
          snapDistance: snapDistance,
          hasArrowhead: hasArrowhead,
        ),
      );

  /// Resolves a single-target binding candidate without list iteration.
  ///
  /// Use this for hot paths that already resolved the target element.
  static ArrowBindingResult? resolveBindingCandidateForTarget({
    required DrawPoint worldPoint,
    required ElementState target,
    required double snapDistance,
    DrawPoint? referencePoint,
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
        ) ??
        _resolveBindingOnTarget(
          target: target,
          worldPoint: worldPoint,
          snapDistance: snapDistance,
          referencePoint: referencePoint,
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
        ) ??
        _resolveElbowBindingOnTarget(
          target: target,
          worldPoint: worldPoint,
          snapDistance: snapDistance,
          hasArrowhead: hasArrowhead,
        );
  }

  static DrawPoint? resolveBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    DrawPoint? referencePoint,
  }) {
    final coreResolved = _resolveBoundPointViaCore(
      binding: binding,
      target: target,
      referencePoint: referencePoint,
      elbowed: false,
    );
    if (coreResolved != null) {
      return coreResolved;
    }

    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }
    final localAnchor = DrawPoint(
      x: rect.minX + rect.width * binding.anchor.x,
      y: rect.minY + rect.height * binding.anchor.y,
    );
    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    if (binding.mode == ArrowBindingMode.inside) {
      return space.toWorld(localAnchor);
    }

    final gap = _resolveBindingGap(target);
    final localReference = referencePoint == null
        ? null
        : space.fromWorld(referencePoint);
    if (_isCircularTarget(target)) {
      final radius = _resolveCircleRadius(rect);
      if (radius <= 0) {
        return null;
      }
      final snapPoint = _resolveCircleOrbitSnapPoint(
        center: rect.center,
        radius: radius,
        anchorPoint: localAnchor,
        localReference: localReference,
        gap: gap,
      );
      return space.toWorld(snapPoint);
    }
    final snapPoint = _resolveOrbitSnapPoint(
      rect: rect,
      anchorPoint: localAnchor,
      localReference: localReference,
      gap: gap,
    );
    return space.toWorld(snapPoint);
  }

  static DrawPoint? resolveElbowBoundPoint({
    required ArrowBinding binding,
    required ElementState target,
    required bool hasArrowhead,
  }) {
    final coreResolved = _resolveBoundPointViaCore(
      binding: binding,
      target: target,
      elbowed: true,
      hasArrowhead: hasArrowhead,
    );
    if (coreResolved != null) {
      return coreResolved;
    }

    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }

    final localAnchor = DrawPoint(
      x: rect.minX + rect.width * binding.anchor.x,
      y: rect.minY + rect.height * binding.anchor.y,
    );
    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    if (_isCircularTarget(target)) {
      final radius = _resolveCircleRadius(rect);
      if (radius <= 0) {
        return null;
      }
      final anchorPoint = _resolveCircleElbowAnchorPoint(
        center: rect.center,
        radius: radius,
        point: localAnchor,
      );
      final worldAnchor = space.toWorld(anchorPoint);
      final heading = ElbowGeometry.headingForVector(
        worldAnchor.x - rect.centerX,
        worldAnchor.y - rect.centerY,
      );
      final gap = _resolveElbowBindingGap(hasArrowhead);
      return DrawPoint(
        x: worldAnchor.x + heading.dx * gap,
        y: worldAnchor.y + heading.dy * gap,
      );
    }
    final anchorPoint = _resolveElbowAnchorPoint(
      rect: rect,
      point: localAnchor,
    );
    final worldAnchor = space.toWorld(anchorPoint);
    final heading = ElbowGeometry.headingForPointOnBounds(
      SelectionCalculator.computeElementWorldAabb(target),
      worldAnchor,
    );
    final gap = _resolveElbowBindingGap(hasArrowhead);
    return DrawPoint(
      x: worldAnchor.x + heading.dx * gap,
      y: worldAnchor.y + heading.dy * gap,
    );
  }

  static DrawPoint? resolveElbowAnchorPoint({
    required ArrowBinding binding,
    required ElementState target,
  }) {
    final bindable = _toCoreBindableStateForPreview(target);
    if (bindable != null && binding.elementId == bindable.id) {
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

    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }
    final localAnchor = DrawPoint(
      x: rect.minX + rect.width * binding.anchor.x,
      y: rect.minY + rect.height * binding.anchor.y,
    );
    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    if (_isCircularTarget(target)) {
      final radius = _resolveCircleRadius(rect);
      if (radius <= 0) {
        return null;
      }
      final anchorPoint = _resolveCircleElbowAnchorPoint(
        center: rect.center,
        radius: radius,
        point: localAnchor,
      );
      return space.toWorld(anchorPoint);
    }
    final anchorPoint = _resolveElbowAnchorPoint(
      rect: rect,
      point: localAnchor,
    );
    return space.toWorld(anchorPoint);
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

  static ArrowBindingResult? _resolveBindingOnTarget({
    required ElementState target,
    required DrawPoint worldPoint,
    required double snapDistance,
    DrawPoint? referencePoint,
  }) {
    final rect = target.rect;
    if (rect.width == 0 || rect.height == 0) {
      return null;
    }

    final space = ElementSpace(rotation: target.rotation, origin: rect.center);
    final localPoint = space.fromWorld(worldPoint);
    final localReference = referencePoint == null
        ? null
        : space.fromWorld(referencePoint);
    final gap = _resolveBindingGap(target);
    final hit = _isCircularTarget(target)
        ? _resolveCircleBindingHit(
            rect: rect,
            localPoint: localPoint,
            localReference: localReference,
            snapDistance: snapDistance,
            gap: gap,
          )
        : _resolveBindingHit(
            rect: rect,
            localPoint: localPoint,
            localReference: localReference,
            snapDistance: snapDistance,
            gap: gap,
          );
    if (hit == null) {
      return null;
    }

    final binding = bindingFromLocalPoint(
      target: target,
      localPoint: hit.anchorPoint,
      mode: hit.mode,
    );
    if (binding == null) {
      return null;
    }

    return ArrowBindingResult(
      binding: binding,
      snapPoint: space.toWorld(hit.snapPoint),
      distance: hit.distance,
      zIndex: target.zIndex,
    );
  }
}

double? _resolveBindingGapViaCore(ElementState target) {
  final bindable = _toCoreBindableStateForPreview(target);
  if (bindable == null) {
    return null;
  }
  return core.getBindingGap(bindable, false);
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
    final bindable = _toCoreBindableStateForPreview(target);
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
      DrawPoint(x: worldPoint.x - math.max(1, snapDistance), y: worldPoint.y);
  final normalized = core.normalizeArrowFromGlobalPoints(<core.Point>[
    _toCorePoint(oppositePoint),
    _toCorePoint(worldPoint),
  ], 1000000);

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

  final arrow = core.ArrowState(
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

  final result = computeCoreSimpleBindingPatch(
    arrow: arrow,
    draggedPoints: <int, core.Point>{
      arrow.points.length - 1: _toCorePoint(worldPoint),
    },
    pointer: _toCorePoint(worldPoint),
    bindables: bindables,
    context: core.defaultEngineContext,
    options: <String, dynamic>{
      'complexBindings': true,
      if (referencePoint == null) 'newArrow': true,
    },
  );

  final nextArrow = core.applyArrowPatch(arrow, result.arrowPatch);
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

DrawPoint? _resolveBoundPointViaCore({
  required ArrowBinding binding,
  required ElementState target,
  required bool elbowed,
  DrawPoint? referencePoint,
  bool hasArrowhead = false,
}) {
  final bindable = _toCoreBindableStateForPreview(target);
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
  ], 1000000);
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

core.BindableRoundness? _toCoreRoundness(ElementState target) {
  final data = target.data;
  if (data is! RectangleData || data.cornerRadius <= 0) {
    return null;
  }
  return core.BindableRoundness(type: 'adaptive', value: data.cornerRadius);
}

core.BindableState? _toCoreBindableStateForPreview(ElementState target) {
  final data = target.data;
  if (data is RectangleData) {
    return core.BindableState(
      id: target.id,
      shape: 'rectangle',
      x: target.rect.minX,
      y: target.rect.minY,
      width: target.rect.width,
      height: target.rect.height,
      angle: target.rotation,
      strokeWidth: data.strokeWidth,
      roundness: _toCoreRoundness(target),
      zIndex: target.zIndex.toDouble(),
      backgroundOpaque: data.fillColor.a > 0,
      bindingEnabled: true,
      interiorHitEnabled: true,
    );
  }

  if (data is TextData) {
    return core.BindableState(
      id: target.id,
      shape: 'rectangle',
      x: target.rect.minX,
      y: target.rect.minY,
      width: target.rect.width,
      height: target.rect.height,
      angle: target.rotation,
      strokeWidth: data.strokeWidth,
      zIndex: target.zIndex.toDouble(),
      backgroundOpaque: data.fillColor.a > 0,
      bindingEnabled: true,
      interiorHitEnabled: true,
    );
  }

  if (data is SerialNumberData) {
    return core.BindableState(
      id: target.id,
      shape: 'ellipse',
      x: target.rect.minX,
      y: target.rect.minY,
      width: target.rect.width,
      height: target.rect.height,
      angle: target.rotation,
      strokeWidth: resolveSerialNumberStrokeWidth(data: data),
      zIndex: target.zIndex.toDouble(),
      backgroundOpaque: data.fillColor.a > 0,
      bindingEnabled: true,
      interiorHitEnabled: true,
    );
  }

  return null;
}

ArrowBindingResult? _resolveBestBindingCandidate({
  required Iterable<ElementState> targets,
  required double snapDistance,
  required ArrowBinding? preferredBinding,
  required bool allowNewBinding,
  required ArrowBindingResult? Function(ElementState target) resolver,
}) {
  if (snapDistance <= 0) {
    return null;
  }
  final preferredElementId = preferredBinding?.elementId;
  if (!allowNewBinding && preferredElementId == null) {
    return null;
  }

  ArrowBindingResult? best;
  var bestScore = double.infinity;
  for (final target in targets) {
    if (target.opacity <= 0) {
      continue;
    }
    if (!allowNewBinding &&
        preferredElementId != null &&
        target.id != preferredElementId) {
      continue;
    }

    final candidate = resolver(target);
    if (candidate == null) {
      continue;
    }

    var score = candidate.distance;
    if (preferredElementId == target.id) {
      score = math.max(0, score - snapDistance * 0.25);
    }

    if (_isBetterBindingCandidate(
      candidate: candidate,
      candidateScore: score,
      currentBest: best,
      currentBestScore: bestScore,
    )) {
      best = candidate;
      bestScore = score;
    }
  }

  return best;
}

bool _isBetterBindingCandidate({
  required ArrowBindingResult candidate,
  required double candidateScore,
  required ArrowBindingResult? currentBest,
  required double currentBestScore,
}) {
  if (candidateScore < currentBestScore) {
    return true;
  }
  if (candidateScore > currentBestScore) {
    return false;
  }
  if (currentBest == null) {
    return true;
  }
  if (candidate.zIndex > currentBest.zIndex) {
    return true;
  }
  if (candidate.zIndex < currentBest.zIndex) {
    return false;
  }
  return candidate.binding.elementId.compareTo(currentBest.binding.elementId) <
      0;
}

@immutable
final class _BindingHit {
  const _BindingHit({
    required this.anchorPoint,
    required this.snapPoint,
    required this.mode,
    required this.distance,
  });

  final DrawPoint anchorPoint;
  final DrawPoint snapPoint;
  final ArrowBindingMode mode;
  final double distance;
}

const _bindingGapBase = 6.0;
const _elbowBindingGapBase = 5.0;
const _bindingHitToleranceFactor = 0.4;
const double _bindingArrowheadGapMultiplier =
    _bindingGapBase / _elbowBindingGapBase;
const _intersectionEpsilon = 1e-6;
const _insideEpsilon = 1e-6;

double _resolveInsideBindingThreshold({
  required DrawRect rect,
  required double snapDistance,
}) {
  final maxDepth = math.min(rect.width.abs(), rect.height.abs()) / 2;
  return math.min(math.max(0, snapDistance), math.max(0, maxDepth));
}

double _resolveInsideDepth(DrawRect rect, DrawPoint point) {
  final left = (point.x - rect.minX).abs();
  final right = (rect.maxX - point.x).abs();
  final top = (point.y - rect.minY).abs();
  final bottom = (rect.maxY - point.y).abs();
  return math.min(math.min(left, right), math.min(top, bottom));
}

double _resolveCircleInsideBindingThreshold({
  required double radius,
  required double snapDistance,
}) => math.min(math.max(0, snapDistance), math.max(0, radius));

double _resolveCircleInsideDepth({
  required DrawPoint center,
  required double radius,
  required DrawPoint point,
}) {
  final dx = point.x - center.x;
  final dy = point.y - center.y;
  final distance = math.sqrt(dx * dx + dy * dy);
  return radius - distance;
}

DrawPoint _nearestPointOnRectBoundary(DrawRect rect, DrawPoint point) {
  final clampedX = _clamp(point.x, rect.minX, rect.maxX);
  final clampedY = _clamp(point.y, rect.minY, rect.maxY);

  final inside =
      point.x >= rect.minX &&
      point.x <= rect.maxX &&
      point.y >= rect.minY &&
      point.y <= rect.maxY;
  if (!inside) {
    return DrawPoint(x: clampedX, y: clampedY);
  }

  final left = (point.x - rect.minX).abs();
  final right = (rect.maxX - point.x).abs();
  final top = (point.y - rect.minY).abs();
  final bottom = (rect.maxY - point.y).abs();

  final minDistance = math.min(math.min(left, right), math.min(top, bottom));
  if (minDistance == left) {
    return DrawPoint(x: rect.minX, y: point.y);
  }
  if (minDistance == right) {
    return DrawPoint(x: rect.maxX, y: point.y);
  }
  if (minDistance == top) {
    return DrawPoint(x: point.x, y: rect.minY);
  }
  return DrawPoint(x: point.x, y: rect.maxY);
}

DrawPoint _nearestPointOnCircleBoundary(
  DrawPoint center,
  double radius,
  DrawPoint point,
) {
  if (radius <= 0) {
    return center;
  }
  final dx = point.x - center.x;
  final dy = point.y - center.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= _intersectionEpsilon) {
    return DrawPoint(x: center.x + radius, y: center.y);
  }
  final scale = radius / length;
  return DrawPoint(x: center.x + dx * scale, y: center.y + dy * scale);
}

double _resolveBindingGap(ElementState target) {
  final data = target.data;
  var strokeWidth = 0.0;
  if (data is RectangleData) {
    strokeWidth = data.strokeWidth;
  } else if (data is TextData) {
    strokeWidth = data.strokeWidth;
  } else if (data is SerialNumberData) {
    strokeWidth = resolveSerialNumberStrokeWidth(data: data);
  }
  return _bindingGapBase + strokeWidth / 2;
}

double _resolveElbowBindingGap(bool hasArrowhead) {
  if (!hasArrowhead) {
    return _elbowBindingGapBase;
  }
  return _elbowBindingGapBase * _bindingArrowheadGapMultiplier;
}

bool _isCircularTarget(ElementState target) => target.data is SerialNumberData;

double _resolveCircleRadius(DrawRect rect) =>
    math.min(rect.width.abs(), rect.height.abs()) / 2;

DrawRect _inflateRect(DrawRect rect, double delta) => DrawRect(
  minX: rect.minX - delta,
  minY: rect.minY - delta,
  maxX: rect.maxX + delta,
  maxY: rect.maxY + delta,
);

_BindingHit? _resolveBindingHit({
  required DrawRect rect,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
  required double snapDistance,
  required double gap,
}) {
  if (_isStrictlyInsideRect(rect, localPoint)) {
    final referenceInside =
        localReference != null && _isStrictlyInsideRect(rect, localReference);
    var allowInside = localReference == null || referenceInside;
    if (!allowInside) {
      final insideDepth = _resolveInsideDepth(rect, localPoint);
      final insideThreshold = _resolveInsideBindingThreshold(
        rect: rect,
        snapDistance: snapDistance,
      );
      allowInside = insideDepth >= insideThreshold;
    }
    if (allowInside) {
      return _BindingHit(
        anchorPoint: localPoint,
        snapPoint: localPoint,
        mode: ArrowBindingMode.inside,
        distance: 0,
      );
    }

    final anchorPoint = _resolveOrbitAnchorPoint(
      rect: rect,
      localPoint: localPoint,
      localReference: localReference,
    );
    final snapPoint = _resolveOrbitSnapPoint(
      rect: rect,
      anchorPoint: anchorPoint,
      localReference: localReference,
      gap: gap,
      targetPoint: localPoint,
    );
    return _BindingHit(
      anchorPoint: anchorPoint,
      snapPoint: snapPoint,
      mode: ArrowBindingMode.orbit,
      distance: 0,
    );
  }

  final anchorPoint = _resolveOrbitAnchorPoint(
    rect: rect,
    localPoint: localPoint,
    localReference: localReference,
  );
  final distance = localPoint.distance(anchorPoint);
  if (distance > snapDistance * (1 + _bindingHitToleranceFactor)) {
    return null;
  }

  final snapPoint = _resolveOrbitSnapPoint(
    rect: rect,
    anchorPoint: anchorPoint,
    localReference: localReference,
    gap: gap,
    targetPoint: localPoint,
  );

  return _BindingHit(
    anchorPoint: anchorPoint,
    snapPoint: snapPoint,
    mode: ArrowBindingMode.orbit,
    distance: distance,
  );
}

_BindingHit? _resolveCircleBindingHit({
  required DrawRect rect,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
  required double snapDistance,
  required double gap,
}) {
  final radius = _resolveCircleRadius(rect);
  if (radius <= 0) {
    return null;
  }
  final center = rect.center;
  if (_isStrictlyInsideCircle(
    center: center,
    radius: radius,
    point: localPoint,
  )) {
    final referenceInside =
        localReference != null &&
        _isStrictlyInsideCircle(
          center: center,
          radius: radius,
          point: localReference,
        );
    var allowInside = localReference == null || referenceInside;
    if (!allowInside) {
      final insideDepth = _resolveCircleInsideDepth(
        center: center,
        radius: radius,
        point: localPoint,
      );
      final insideThreshold = _resolveCircleInsideBindingThreshold(
        radius: radius,
        snapDistance: snapDistance,
      );
      allowInside = insideDepth >= insideThreshold;
    }
    if (allowInside) {
      return _BindingHit(
        anchorPoint: localPoint,
        snapPoint: localPoint,
        mode: ArrowBindingMode.inside,
        distance: 0,
      );
    }

    final anchorPoint = _resolveCircleOrbitAnchorPoint(
      center: center,
      radius: radius,
      localPoint: localPoint,
      localReference: localReference,
    );
    final snapPoint = _resolveCircleOrbitSnapPoint(
      center: center,
      radius: radius,
      anchorPoint: anchorPoint,
      localReference: localReference,
      gap: gap,
      targetPoint: localPoint,
    );
    return _BindingHit(
      anchorPoint: anchorPoint,
      snapPoint: snapPoint,
      mode: ArrowBindingMode.orbit,
      distance: 0,
    );
  }

  final anchorPoint = _resolveCircleOrbitAnchorPoint(
    center: center,
    radius: radius,
    localPoint: localPoint,
    localReference: localReference,
  );
  final distance = localPoint.distance(anchorPoint);
  if (distance > snapDistance * (1 + _bindingHitToleranceFactor)) {
    return null;
  }

  final snapPoint = _resolveCircleOrbitSnapPoint(
    center: center,
    radius: radius,
    anchorPoint: anchorPoint,
    localReference: localReference,
    gap: gap,
    targetPoint: localPoint,
  );

  return _BindingHit(
    anchorPoint: anchorPoint,
    snapPoint: snapPoint,
    mode: ArrowBindingMode.orbit,
    distance: distance,
  );
}

ArrowBindingResult? _resolveElbowBindingOnTarget({
  required ElementState target,
  required DrawPoint worldPoint,
  required double snapDistance,
  required bool hasArrowhead,
}) {
  final rect = target.rect;
  if (rect.width == 0 || rect.height == 0) {
    return null;
  }

  final space = ElementSpace(rotation: target.rotation, origin: rect.center);
  final localPoint = space.fromWorld(worldPoint);
  if (_isCircularTarget(target)) {
    final radius = _resolveCircleRadius(rect);
    if (radius <= 0) {
      return null;
    }
    final anchorPoint = _resolveCircleElbowAnchorPoint(
      center: rect.center,
      radius: radius,
      point: localPoint,
    );

    final distance =
        _isStrictlyInsideCircle(
          center: rect.center,
          radius: radius,
          point: localPoint,
        )
        ? 0.0
        : localPoint.distance(anchorPoint);
    if (distance > snapDistance * (1 + _bindingHitToleranceFactor)) {
      return null;
    }

    final binding = ArrowBindingUtils.bindingFromLocalPoint(
      target: target,
      localPoint: anchorPoint,
    );
    if (binding == null) {
      return null;
    }

    final worldAnchor = space.toWorld(anchorPoint);
    final heading = ElbowGeometry.headingForVector(
      worldAnchor.x - rect.centerX,
      worldAnchor.y - rect.centerY,
    );
    final gap = _resolveElbowBindingGap(hasArrowhead);
    final snapPoint = DrawPoint(
      x: worldAnchor.x + heading.dx * gap,
      y: worldAnchor.y + heading.dy * gap,
    );

    return ArrowBindingResult(
      binding: binding,
      snapPoint: snapPoint,
      distance: distance,
      zIndex: target.zIndex,
    );
  }

  final anchorPoint = _resolveElbowAnchorPoint(rect: rect, point: localPoint);

  final distance = _isStrictlyInsideRect(rect, localPoint)
      ? 0.0
      : localPoint.distance(anchorPoint);
  if (distance > snapDistance * (1 + _bindingHitToleranceFactor)) {
    return null;
  }

  final binding = ArrowBindingUtils.bindingFromLocalPoint(
    target: target,
    localPoint: anchorPoint,
  );
  if (binding == null) {
    return null;
  }

  final worldAnchor = space.toWorld(anchorPoint);
  final heading = ElbowGeometry.headingForPointOnBounds(
    SelectionCalculator.computeElementWorldAabb(target),
    worldAnchor,
  );
  final gap = _resolveElbowBindingGap(hasArrowhead);
  final snapPoint = DrawPoint(
    x: worldAnchor.x + heading.dx * gap,
    y: worldAnchor.y + heading.dy * gap,
  );

  return ArrowBindingResult(
    binding: binding,
    snapPoint: snapPoint,
    distance: distance,
    zIndex: target.zIndex,
  );
}

// Prefer the intersection closest to the pointer so penetrations can bind.
DrawPoint _resolveOrbitAnchorPoint({
  required DrawRect rect,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
}) {
  if (localReference != null) {
    final intersection = _intersectRectAlongLine(
      rect: rect,
      reference: localReference,
      target: localPoint,
      preferPoint: localPoint,
    );
    if (intersection != null) {
      return intersection;
    }
  }
  return _nearestPointOnRectBoundary(rect, localPoint);
}

DrawPoint _resolveElbowAnchorPoint({
  required DrawRect rect,
  required DrawPoint point,
}) {
  final center = rect.center;
  final intersection = _intersectRectAlongLine(
    rect: rect,
    reference: center,
    target: point,
    preferRay: true,
  );
  return intersection ?? _nearestPointOnRectBoundary(rect, point);
}

DrawPoint _resolveOrbitSnapPoint({
  required DrawRect rect,
  required DrawPoint anchorPoint,
  required DrawPoint? localReference,
  required double gap,
  DrawPoint? targetPoint,
}) {
  final snapRect = gap <= 0 ? rect : _inflateRect(rect, gap);
  final directionPoint = targetPoint ?? anchorPoint;

  if (localReference != null) {
    final intersection = _intersectRectAlongLine(
      rect: snapRect,
      reference: localReference,
      target: directionPoint,
      preferRay: true,
    );
    if (intersection != null) {
      return intersection;
    }
  }

  return _nearestPointOnRectBoundary(snapRect, directionPoint);
}

DrawPoint _resolveCircleOrbitAnchorPoint({
  required DrawPoint center,
  required double radius,
  required DrawPoint localPoint,
  required DrawPoint? localReference,
}) {
  if (localReference != null) {
    final intersection = _intersectCircleAlongLine(
      center: center,
      radius: radius,
      reference: localReference,
      target: localPoint,
      preferPoint: localPoint,
    );
    if (intersection != null) {
      return intersection;
    }
  }
  return _nearestPointOnCircleBoundary(center, radius, localPoint);
}

DrawPoint _resolveCircleElbowAnchorPoint({
  required DrawPoint center,
  required double radius,
  required DrawPoint point,
}) {
  final dx = point.x - center.x;
  final dy = point.y - center.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= _intersectionEpsilon) {
    return DrawPoint(x: center.x + radius, y: center.y);
  }
  final scale = radius / length;
  return DrawPoint(x: center.x + dx * scale, y: center.y + dy * scale);
}

DrawPoint _resolveCircleOrbitSnapPoint({
  required DrawPoint center,
  required double radius,
  required DrawPoint anchorPoint,
  required DrawPoint? localReference,
  required double gap,
  DrawPoint? targetPoint,
}) {
  final snapRadius = radius + gap;
  final directionPoint = targetPoint ?? anchorPoint;

  if (localReference != null) {
    final intersection = _intersectCircleAlongLine(
      center: center,
      radius: snapRadius,
      reference: localReference,
      target: directionPoint,
      preferRay: true,
    );
    if (intersection != null) {
      return intersection;
    }
  }

  return _nearestPointOnCircleBoundary(center, snapRadius, directionPoint);
}

bool _isStrictlyInsideRect(DrawRect rect, DrawPoint point) =>
    point.x > rect.minX + _insideEpsilon &&
    point.x < rect.maxX - _insideEpsilon &&
    point.y > rect.minY + _insideEpsilon &&
    point.y < rect.maxY - _insideEpsilon;

bool _isStrictlyInsideCircle({
  required DrawPoint center,
  required double radius,
  required DrawPoint point,
}) {
  if (radius <= _insideEpsilon) {
    return false;
  }
  final dx = point.x - center.x;
  final dy = point.y - center.y;
  final distanceSquared = dx * dx + dy * dy;
  final threshold = radius - _insideEpsilon;
  return distanceSquared < threshold * threshold;
}

DrawPoint? _intersectRectAlongLine({
  required DrawRect rect,
  required DrawPoint reference,
  required DrawPoint target,
  DrawPoint? preferPoint,
  bool preferRay = false,
}) {
  final dx = target.x - reference.x;
  final dy = target.y - reference.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= _intersectionEpsilon) {
    return null;
  }

  final dirX = dx / length;
  final dirY = dy / length;
  final maxDim = math.max(rect.width.abs(), rect.height.abs());
  final extend = length + maxDim + _bindingGapBase * 2;

  final start = DrawPoint(
    x: reference.x - dirX * extend,
    y: reference.y - dirY * extend,
  );
  final end = DrawPoint(
    x: reference.x + dirX * extend,
    y: reference.y + dirY * extend,
  );

  final intersections = _segmentRectIntersections(
    rect: rect,
    start: start,
    end: end,
  );
  if (intersections.isEmpty) {
    return null;
  }

  if (preferRay) {
    DrawPoint? best;
    var bestT = double.infinity;
    for (final intersection in intersections) {
      final t =
          (intersection.x - reference.x) * dirX +
          (intersection.y - reference.y) * dirY;
      if (t < -_intersectionEpsilon) {
        continue;
      }
      if (t < bestT) {
        bestT = t;
        best = intersection;
      }
    }
    return best;
  }

  final sortPoint = preferPoint ?? reference;
  intersections.sort(
    (a, b) =>
        sortPoint.distanceSquared(a).compareTo(sortPoint.distanceSquared(b)),
  );
  return intersections.first;
}

DrawPoint? _intersectCircleAlongLine({
  required DrawPoint center,
  required double radius,
  required DrawPoint reference,
  required DrawPoint target,
  DrawPoint? preferPoint,
  bool preferRay = false,
}) {
  if (radius <= 0) {
    return null;
  }
  final dx = target.x - reference.x;
  final dy = target.y - reference.y;
  final a = dx * dx + dy * dy;
  if (a <= _intersectionEpsilon) {
    return null;
  }

  final ox = reference.x - center.x;
  final oy = reference.y - center.y;
  final b = 2 * (dx * ox + dy * oy);
  final c = ox * ox + oy * oy - radius * radius;
  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) {
    return null;
  }

  final sqrtD = math.sqrt(discriminant);
  final t1 = (-b - sqrtD) / (2 * a);
  final t2 = (-b + sqrtD) / (2 * a);

  final candidates = <double>[t1, t2];
  if (preferRay) {
    double? bestT;
    for (final t in candidates) {
      if (t < -_intersectionEpsilon) {
        continue;
      }
      if (bestT == null || t < bestT) {
        bestT = t;
      }
    }
    if (bestT == null) {
      return null;
    }
    return DrawPoint(x: reference.x + dx * bestT, y: reference.y + dy * bestT);
  }

  final sortPoint = preferPoint ?? reference;
  DrawPoint? best;
  var bestDistance = double.infinity;
  for (final t in candidates) {
    final point = DrawPoint(x: reference.x + dx * t, y: reference.y + dy * t);
    final distance = sortPoint.distanceSquared(point);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = point;
    }
  }
  return best;
}

List<DrawPoint> _segmentRectIntersections({
  required DrawRect rect,
  required DrawPoint start,
  required DrawPoint end,
}) {
  final intersections = <DrawPoint>[];
  final dx = end.x - start.x;
  final dy = end.y - start.y;

  void addIfValid(double t, double x, double y) {
    if (t < -_intersectionEpsilon || t > 1 + _intersectionEpsilon) {
      return;
    }
    if (x < rect.minX - _intersectionEpsilon ||
        x > rect.maxX + _intersectionEpsilon ||
        y < rect.minY - _intersectionEpsilon ||
        y > rect.maxY + _intersectionEpsilon) {
      return;
    }
    final point = DrawPoint(x: x, y: y);
    for (final existing in intersections) {
      if (existing.distanceSquared(point) <=
          _intersectionEpsilon * _intersectionEpsilon) {
        return;
      }
    }
    intersections.add(point);
  }

  if (dx.abs() > _intersectionEpsilon) {
    var t = (rect.minX - start.x) / dx;
    var y = start.y + t * dy;
    addIfValid(t, rect.minX, y);

    t = (rect.maxX - start.x) / dx;
    y = start.y + t * dy;
    addIfValid(t, rect.maxX, y);
  }

  if (dy.abs() > _intersectionEpsilon) {
    var t = (rect.minY - start.y) / dy;
    var x = start.x + t * dx;
    addIfValid(t, x, rect.minY);

    t = (rect.maxY - start.y) / dy;
    x = start.x + t * dx;
    addIfValid(t, x, rect.maxY);
  }

  return intersections;
}

double _clamp(double value, double min, double max) =>
    math.min(math.max(value, min), max);

double _clamp01(double value) => _clamp(value, 0, 1);
