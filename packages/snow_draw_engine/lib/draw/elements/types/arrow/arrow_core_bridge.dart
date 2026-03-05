import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../highlight/highlight_data.dart';
import '../rectangle/rectangle_data.dart';
import '../serial_number/serial_number_data.dart';
import '../serial_number/serial_number_layout.dart';
import '../text/text_data.dart';
import 'arrow_binding.dart';
import 'arrow_geometry.dart';
import 'arrow_layout.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

@immutable
final class ArrowCoreDocumentProjection {
  const ArrowCoreDocumentProjection({
    required this.bindables,
    required this.bindableRelations,
    required this.arrows,
    required this.arrowSources,
    required this.orderedElementIds,
    required this.anchorElementIdsByBindableId,
  });

  final List<core.BindableState> bindables;
  final List<core.BindableRelationState> bindableRelations;
  final List<core.ArrowState> arrows;
  final Map<String, (ElementState, ArrowLikeData)> arrowSources;
  final List<String> orderedElementIds;
  final Map<String, List<String>> anchorElementIdsByBindableId;
}

const _defaultMaxCoordinate = 1e6;

core.EngineContext buildCoreEngineContext({
  double zoom = 1,
  bool isBindingEnabled = true,
  String bindMode = core.bindModeOrbit,
  double maxCoordinate = _defaultMaxCoordinate,
}) => core.normalizeEngineContext(<String, dynamic>{
  'zoom': zoom,
  'isBindingEnabled': isBindingEnabled,
  'bindMode': bindMode,
  'maxCoordinate': maxCoordinate,
});

core.Point toCorePoint(DrawPoint point) => <double>[point.x, point.y];

DrawPoint toDrawPoint(core.Point point) => DrawPoint(x: point[0], y: point[1]);

List<core.Point> toCorePoints(Iterable<DrawPoint> points) =>
    points.map(toCorePoint).toList(growable: false);

List<DrawPoint> toDrawPoints(Iterable<core.Point> points) =>
    points.map(toDrawPoint).toList(growable: false);

String _toCoreBindingMode(ArrowBindingMode mode) =>
    mode == ArrowBindingMode.inside ? core.bindModeInside : core.bindModeOrbit;

ArrowBindingMode _fromCoreBindingMode(String mode) =>
    mode == core.bindModeInside
    ? ArrowBindingMode.inside
    : ArrowBindingMode.orbit;

core.FixedPointBinding? toCoreBinding(ArrowBinding? binding) {
  if (binding == null) {
    return null;
  }
  return core.FixedPointBinding(
    elementId: binding.elementId,
    fixedPoint: <double>[binding.anchor.x, binding.anchor.y],
    mode: _toCoreBindingMode(binding.mode),
  );
}

ArrowBinding? fromCoreBinding(core.FixedPointBinding? binding) {
  if (binding == null) {
    return null;
  }
  return ArrowBinding(
    elementId: binding.elementId,
    anchor: DrawPoint(
      x: _clamp01(binding.fixedPoint[0]),
      y: _clamp01(binding.fixedPoint[1]),
    ),
    mode: _fromCoreBindingMode(binding.mode),
  );
}

String? toCoreArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.none:
      return null;
    case ArrowheadStyle.standard:
      return 'arrow';
    case ArrowheadStyle.triangle:
      return 'triangle';
    case ArrowheadStyle.triangleOutline:
      return 'triangle_outline';
    case ArrowheadStyle.square:
      return 'square';
    case ArrowheadStyle.dot:
      return 'dot';
    case ArrowheadStyle.circle:
      return 'circle';
    case ArrowheadStyle.circleOutline:
      return 'circle_outline';
    case ArrowheadStyle.diamond:
      return 'diamond';
    case ArrowheadStyle.diamondOutline:
      return 'diamond_outline';
    case ArrowheadStyle.crowfootOne:
      return 'crowfoot_one';
    case ArrowheadStyle.crowfootMany:
      return 'crowfoot_many';
    case ArrowheadStyle.crowfootOneOrMany:
      return 'crowfoot_one_or_many';
    case ArrowheadStyle.invertedTriangle:
      return 'inverted_triangle';
    case ArrowheadStyle.verticalLine:
      return 'bar';
  }
}

bool isArrowBindableElement(ElementState element) {
  final data = element.data;
  return data is RectangleData ||
      data is TextData ||
      data is SerialNumberData ||
      data is HighlightData;
}

core.BindableState? toCoreBindableState(ElementState element) {
  final data = element.data;
  if (data is RectangleData) {
    return _buildCoreBindableState(
      element: element,
      shape: 'rectangle',
      strokeWidth: data.strokeWidth,
      roundness: _adaptiveRoundness(data.cornerRadius),
      backgroundOpaque: data.fillColor.a > 0,
    );
  }
  if (data is TextData) {
    return _buildCoreBindableState(
      element: element,
      shape: 'rectangle',
      strokeWidth: data.strokeWidth,
      roundness: _adaptiveRoundness(data.cornerRadius),
      backgroundOpaque: data.fillColor.a > 0,
    );
  }
  if (data is SerialNumberData) {
    return _buildCoreBindableState(
      element: element,
      shape: 'ellipse',
      strokeWidth: resolveSerialNumberStrokeWidth(data: data),
      backgroundOpaque: data.fillColor.a > 0,
    );
  }
  if (data is HighlightData) {
    return _buildCoreBindableState(
      element: element,
      shape: data.shape == HighlightShape.ellipse ? 'ellipse' : 'rectangle',
      strokeWidth: data.strokeWidth,
      backgroundOpaque: data.color.a > 0,
    );
  }
  return null;
}

core.BindableRoundness? _adaptiveRoundness(double radius) =>
    radius > 0 ? core.BindableRoundness(type: 'adaptive', value: radius) : null;

core.BindableState _buildCoreBindableState({
  required ElementState element,
  required String shape,
  required double strokeWidth,
  required bool backgroundOpaque,
  core.BindableRoundness? roundness,
}) => core.BindableState(
  id: element.id,
  shape: shape,
  x: element.rect.minX,
  y: element.rect.minY,
  width: element.rect.width,
  height: element.rect.height,
  angle: element.rotation,
  strokeWidth: strokeWidth,
  roundness: roundness,
  zIndex: element.zIndex.toDouble(),
  backgroundOpaque: backgroundOpaque,
  bindingEnabled: true,
  interiorHitEnabled: true,
);

List<core.BindableState> collectCoreBindables(
  Iterable<ElementState> elements,
) => elements
    .map(toCoreBindableState)
    .whereType<core.BindableState>()
    .toList(growable: false);

List<core.BindableRelationState> collectCoreBindableRelations(
  Iterable<ElementState> elements,
) {
  final orderedBindableIds = <String>[];
  final bindableIdSet = <String>{};
  final boundArrowIdsByBindable = <String, Set<String>>{};

  for (final element in elements) {
    if (isArrowBindableElement(element) && bindableIdSet.add(element.id)) {
      orderedBindableIds.add(element.id);
      boundArrowIdsByBindable[element.id] = <String>{};
    }
  }

  for (final element in elements) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      continue;
    }
    final arrowId = element.id;

    void addArrowBinding(String? bindableId) {
      if (bindableId == null || !bindableIdSet.contains(bindableId)) {
        return;
      }
      final boundArrowIds = boundArrowIdsByBindable[bindableId];
      if (boundArrowIds == null) {
        return;
      }
      boundArrowIds.add(arrowId);
    }

    addArrowBinding(data.startBinding?.elementId);
    addArrowBinding(data.endBinding?.elementId);
  }

  return orderedBindableIds
      .map(
        (bindableId) => core.BindableRelationState(
          id: bindableId,
          boundArrowIds: List<String>.unmodifiable(
            (boundArrowIdsByBindable[bindableId] ?? <String>{}).toList()
              ..sort(),
          ),
        ),
      )
      .toList(growable: false);
}

/// Returns bindable id -> ordered anchor element ids for order reductions.
///
/// The first id is always the bindable itself. Additional ids represent
/// element-local anchors that should remain below a bound arrow when reorder
/// events are reduced (for example serial-number bound text).
Map<String, List<String>> collectCoreAnchorElementIdsByBindableId(
  Iterable<ElementState> elements,
) {
  final elementById = <String, ElementState>{
    for (final element in elements) element.id: element,
  };
  if (elementById.isEmpty) {
    return const <String, List<String>>{};
  }

  final anchorIdsByBindableId = <String, List<String>>{};
  for (final element in elementById.values) {
    if (!isArrowBindableElement(element)) {
      continue;
    }

    final anchorIds = <String>[element.id];
    final data = element.data;
    if (data is SerialNumberData) {
      final textElementId = data.textElementId;
      if (textElementId != null &&
          textElementId.isNotEmpty &&
          elementById.containsKey(textElementId) &&
          !anchorIds.contains(textElementId)) {
        anchorIds.add(textElementId);
      }
    }

    anchorIdsByBindableId[element.id] = List<String>.unmodifiable(anchorIds);
  }

  return Map<String, List<String>>.unmodifiable(anchorIdsByBindableId);
}

/// Collects arrow-like elements projected into arrow-core state plus source
/// engine elements for patch application.
///
/// When [onlyBoundArrows] is true, arrows with neither endpoint binding are
/// skipped.
({
  List<core.ArrowState> arrows,
  Map<String, (ElementState, ArrowLikeData)> sources,
})
collectCoreArrowStatesWithSources(
  Iterable<ElementState> elements, {
  bool onlyBoundArrows = false,
}) {
  final arrows = <core.ArrowState>[];
  final sources = <String, (ElementState, ArrowLikeData)>{};

  for (final element in elements) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      continue;
    }
    if (onlyBoundArrows &&
        data.startBinding == null &&
        data.endBinding == null) {
      continue;
    }
    arrows.add(toCoreArrowState(element: element, data: data));
    sources[element.id] = (element, data);
  }

  return (
    arrows: List<core.ArrowState>.unmodifiable(arrows),
    sources: Map<String, (ElementState, ArrowLikeData)>.unmodifiable(sources),
  );
}

/// Builds a consistent arrow-core projection from engine element snapshots.
ArrowCoreDocumentProjection projectCoreDocument(
  Iterable<ElementState> elements, {
  bool onlyBoundArrows = false,
  List<String>? orderedElementIds,
}) {
  final materialized = List<ElementState>.unmodifiable(
    elements.toList(growable: false),
  );
  final arrowsWithSources = collectCoreArrowStatesWithSources(
    materialized,
    onlyBoundArrows: onlyBoundArrows,
  );

  return ArrowCoreDocumentProjection(
    bindables: List<core.BindableState>.unmodifiable(
      collectCoreBindables(materialized),
    ),
    bindableRelations: List<core.BindableRelationState>.unmodifiable(
      collectCoreBindableRelations(materialized),
    ),
    arrows: arrowsWithSources.arrows,
    arrowSources: arrowsWithSources.sources,
    orderedElementIds: List<String>.unmodifiable(
      orderedElementIds ??
          materialized.map((element) => element.id).toList(growable: false),
    ),
    anchorElementIdsByBindableId: collectCoreAnchorElementIdsByBindableId(
      materialized,
    ),
  );
}

List<DrawPoint> resolveArrowLocalPoints(
  ElementState element,
  ArrowLikeData data, [
  List<DrawPoint>? localPointsOverride,
]) =>
    localPointsOverride ??
    ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );

List<DrawPoint> localToWorldPoints(
  ElementState element,
  List<DrawPoint> local,
) {
  if (element.rotation == 0) {
    return local
        .map((point) => DrawPoint(x: point.x, y: point.y))
        .toList(growable: false);
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  return local.map(space.toWorld).toList(growable: false);
}

List<DrawPoint> worldToLocalPoints(
  ElementState element,
  List<DrawPoint> world,
) {
  if (element.rotation == 0) {
    return world
        .map((point) => DrawPoint(x: point.x, y: point.y))
        .toList(growable: false);
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  return world.map(space.fromWorld).toList(growable: false);
}

List<ElbowFixedSegment>? toLocalFixedSegmentsFromCoreArrow(
  core.ArrowState arrow,
  ElementState element,
) {
  final segments = arrow.fixedSegments;
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final converted = segments
      .map((segment) {
        final globalStart = DrawPoint(
          x: arrow.x + segment.start[0],
          y: arrow.y + segment.start[1],
        );
        final globalEnd = DrawPoint(
          x: arrow.x + segment.end[0],
          y: arrow.y + segment.end[1],
        );
        return ElbowFixedSegment(
          index: segment.index,
          start: space.fromWorld(globalStart),
          end: space.fromWorld(globalEnd),
        );
      })
      .toList(growable: false);
  return converted.isEmpty ? null : converted;
}

List<core.FixedSegment>? _toCoreFixedSegments(
  ElementState element,
  List<ElbowFixedSegment>? segments,
  core.NormalizedArrowFromGlobalPoints normalized,
) {
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final converted = segments
      .map((segment) {
        final worldStart = space.toWorld(segment.start);
        final worldEnd = space.toWorld(segment.end);
        return core.FixedSegment(
          start: <double>[
            worldStart.x - normalized.x,
            worldStart.y - normalized.y,
          ],
          end: <double>[worldEnd.x - normalized.x, worldEnd.y - normalized.y],
          index: segment.index,
        );
      })
      .toList(growable: false);
  return converted.isEmpty ? null : converted;
}

core.ArrowState toCoreArrowState({
  required ElementState element,
  required ArrowLikeData data,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) {
  final localPoints = resolveArrowLocalPoints(
    element,
    data,
    localPointsOverride,
  );
  final worldPoints = localToWorldPoints(element, localPoints);
  final normalized = core.normalizeArrowFromGlobalPoints(
    toCorePoints(worldPoints),
    _defaultMaxCoordinate,
  );

  return core.ArrowState(
    id: element.id,
    x: normalized.x,
    y: normalized.y,
    width: normalized.width,
    height: normalized.height,
    points: normalized.points,
    startBinding: toCoreBinding(startBindingOverride ?? data.startBinding),
    endBinding: toCoreBinding(endBindingOverride ?? data.endBinding),
    startArrowhead: toCoreArrowhead(data.startArrowhead),
    endArrowhead: toCoreArrowhead(data.endArrowhead),
    elbowed: data.arrowType == ArrowType.elbow,
    fixedSegments: _toCoreFixedSegments(
      element,
      fixedSegmentsOverride ?? data.fixedSegments,
      normalized,
    ),
    startIsSpecial: data.startIsSpecial,
    endIsSpecial: data.endIsSpecial,
  );
}

List<DrawPoint> coreArrowWorldPoints(core.ArrowState arrow) => arrow.points
    .map((point) => DrawPoint(x: arrow.x + point[0], y: arrow.y + point[1]))
    .toList(growable: false);

List<ElbowFixedSegment>? coreArrowWorldFixedSegments(core.ArrowState arrow) {
  final segments = arrow.fixedSegments;
  if (segments == null || segments.isEmpty) {
    return null;
  }

  final converted = segments
      .map(
        (segment) => ElbowFixedSegment(
          index: segment.index,
          start: DrawPoint(
            x: arrow.x + segment.start[0],
            y: arrow.y + segment.start[1],
          ),
          end: DrawPoint(
            x: arrow.x + segment.end[0],
            y: arrow.y + segment.end[1],
          ),
        ),
      )
      .toList(growable: false);

  return converted.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(converted);
}

ElementState applyCoreArrowStateToElement({
  required ElementState element,
  required ArrowLikeData data,
  required core.ArrowState nextArrow,
}) {
  final nextWorldPoints = coreArrowWorldPoints(nextArrow);
  final localPointsInOldFrame = worldToLocalPoints(element, nextWorldPoints);
  final geometry = resolveArrowGeometryUpdate(
    localPoints: localPointsInOldFrame,
    oldRect: element.rect,
    rotation: element.rotation,
    arrowType: data.arrowType,
  );

  final fixedSegmentsInOldFrame = toLocalFixedSegmentsFromCoreArrow(
    nextArrow,
    element,
  );
  final transformedFixedSegments = transformArrowLocalFixedSegments(
    segments: fixedSegmentsInOldFrame,
    oldRect: element.rect,
    newRect: geometry.rect,
    rotation: element.rotation,
  );

  final nextData = data.copyWith(
    points: geometry.normalizedPoints,
    startBinding: fromCoreBinding(nextArrow.startBinding),
    endBinding: fromCoreBinding(nextArrow.endBinding),
    fixedSegments: transformedFixedSegments,
    startIsSpecial: nextArrow.startIsSpecial,
    endIsSpecial: nextArrow.endIsSpecial,
  );

  return element.copyWith(rect: geometry.rect, data: nextData);
}

ElementState applyCoreArrowPatchToElement({
  required ElementState element,
  required ArrowLikeData data,
  required core.ArrowPatch patch,
}) {
  final currentArrow = toCoreArrowState(element: element, data: data);
  final nextArrow = core.applyArrowPatch(currentArrow, patch);
  return applyCoreArrowStateToElement(
    element: element,
    data: data,
    nextArrow: nextArrow,
  );
}

/// Applies arrow-core patches onto [sources], returning only changed elements.
Map<String, ElementState> applyCoreArrowPatchesToSources({
  required Iterable<core.ArrowStatePatchWithId> patches,
  required Map<String, (ElementState, ArrowLikeData)> sources,
}) {
  final patchedById = <String, ElementState>{};
  for (final arrowPatch in patches) {
    final source = sources[arrowPatch.id];
    if (source == null) {
      continue;
    }
    final (element, data) = source;
    final patched = applyCoreArrowPatchToElement(
      element: element,
      data: data,
      patch: arrowPatch.patch,
    );
    if (patched != element) {
      patchedById[patched.id] = patched;
    }
  }
  return Map<String, ElementState>.unmodifiable(patchedById);
}

List<ElbowFixedSegment>? transformArrowLocalFixedSegments({
  required List<ElbowFixedSegment>? segments,
  required DrawRect oldRect,
  required DrawRect newRect,
  required double rotation,
}) {
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final newSpace = ElementSpace(rotation: rotation, origin: newRect.center);
  final transformed = segments
      .map((segment) {
        final worldStart = oldSpace.toWorld(segment.start);
        final worldEnd = oldSpace.toWorld(segment.end);
        return segment.copyWith(
          start: newSpace.fromWorld(worldStart),
          end: newSpace.fromWorld(worldEnd),
        );
      })
      .toList(growable: false);
  return transformed.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(transformed);
}

double _clamp01(double value) {
  if (value.isNaN) {
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
