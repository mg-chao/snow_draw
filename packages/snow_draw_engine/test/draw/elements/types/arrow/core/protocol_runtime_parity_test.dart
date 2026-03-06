import 'dart:convert';
import 'dart:io';

import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart';
import 'package:test/test.dart';

void main() {
  group('protocol runtime parity', () {
    test('dart protocol responses match excalidraw fixtures', () {
      final fixtureFile = _resolveProtocolParityFixtureFile();
      expect(
        fixtureFile.existsSync(),
        isTrue,
        reason:
            'Missing protocol parity fixture. Run '
            '`node tool/generate_arrow_protocol_parity_fixtures.mjs` in '
            '`packages/snow_draw_engine`.',
      );

      final decoded = jsonDecode(fixtureFile.readAsStringSync());
      expect(decoded, isA<Map<dynamic, dynamic>>());
      final root = decoded as Map<dynamic, dynamic>;
      final cases = root['cases'];
      expect(cases, isA<List<dynamic>>());

      for (final entry in cases as List<dynamic>) {
        expect(entry, isA<Map<dynamic, dynamic>>());
        final parityCase = entry as Map<dynamic, dynamic>;
        final id = parityCase['id'];
        final request = parityCase['request'];
        final expected = parityCase['expected'];
        expect(id, isA<String>());
        expect(request, isA<Map<dynamic, dynamic>>());

        final actual = _canonicalizeJsonLike(
          executeArrowOperationSafe(request),
        );
        final canonicalExpected = _canonicalizeJsonLike(expected);
        final diff = _diffJsonLike(canonicalExpected, actual, path: r'$');
        expect(
          diff,
          isNull,
          reason: 'Case `$id` diverged from Excalidraw fixture: $diff',
        );
      }
    });
  });
}

Object? _canonicalizeJsonLike(Object? value) {
  if (value == null || value is num || value is String || value is bool) {
    return value;
  }

  if (value is List) {
    return value.map(_canonicalizeJsonLike).toList(growable: false);
  }

  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized['${entry.key}'] = _canonicalizeJsonLike(entry.value);
    }
    return _dropNullValues(normalized);
  }

  if (value is BindableRoundness) {
    return _dropNullValues(<String, Object?>{
      'type': _canonicalizeJsonLike(value.type),
      'value': _canonicalizeJsonLike(value.value),
    });
  }
  if (value is CurvePathOp) {
    return _dropNullValues(<String, Object?>{
      'op': value.op,
      'data': _canonicalizeJsonLike(value.data),
    });
  }
  if (value is FixedPointBinding) {
    return _dropNullValues(<String, Object?>{
      'elementId': value.elementId,
      'fixedPoint': _canonicalizeJsonLike(value.fixedPoint),
      'mode': value.mode,
    });
  }
  if (value is FixedSegment) {
    return _dropNullValues(<String, Object?>{
      'index': value.index,
      'start': _canonicalizeJsonLike(value.start),
      'end': _canonicalizeJsonLike(value.end),
    });
  }
  if (value is BindableState) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'shape': value.shape,
      'x': value.x,
      'y': value.y,
      'width': value.width,
      'height': value.height,
      'angle': value.angle,
      'strokeWidth': value.strokeWidth,
      'roundness': _canonicalizeJsonLike(value.roundness),
      'zIndex': value.zIndex,
      'backgroundOpaque': value.backgroundOpaque,
      'bindingEnabled': value.bindingEnabled,
      'interiorHitEnabled': value.interiorHitEnabled,
      'visibilityBounds': _canonicalizeJsonLike(value.visibilityBounds),
    });
  }
  if (value is ArrowState) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'x': value.x,
      'y': value.y,
      'width': value.width,
      'height': value.height,
      'points': _canonicalizeJsonLike(value.points),
      'startBinding': _canonicalizeJsonLike(value.startBinding),
      'endBinding': _canonicalizeJsonLike(value.endBinding),
      'startArrowhead': value.startArrowhead,
      'endArrowhead': value.endArrowhead,
      'elbowed': value.elbowed,
      'fixedSegments': _canonicalizeJsonLike(value.fixedSegments),
      'startIsSpecial': value.startIsSpecial,
      'endIsSpecial': value.endIsSpecial,
    });
  }
  if (value is EngineContext) {
    return _dropNullValues(<String, Object?>{
      'zoom': value.zoom,
      'isBindingEnabled': value.isBindingEnabled,
      'bindMode': value.bindMode,
      'maxCoordinate': value.maxCoordinate,
    });
  }
  if (value is BindablePatch) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'addBoundArrowId': value.addBoundArrowId,
      'removeBoundArrowId': value.removeBoundArrowId,
    });
  }
  if (value is ArrowBindingState) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'startBinding': _canonicalizeJsonLike(value.startBinding),
      'endBinding': _canonicalizeJsonLike(value.endBinding),
    });
  }
  if (value is BindableRelationState) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'boundArrowIds': _canonicalizeJsonLike(value.boundArrowIds),
    });
  }
  if (value is BindableRelationPatch) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'boundArrowIds': _canonicalizeJsonLike(value.boundArrowIds),
    });
  }
  if (value is IdMapEntry) {
    return _dropNullValues(<String, Object?>{
      'from': value.from,
      'to': value.to,
    });
  }
  if (value is ArrowStatePatchWithId) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'patch': _canonicalizeJsonLike(value.patch),
    });
  }
  if (value is LifecycleSyncResult) {
    return _dropNullValues(<String, Object?>{
      'arrows': _canonicalizeJsonLike(value.arrows),
      'bindables': _canonicalizeJsonLike(value.bindables),
      'arrowPatches': _canonicalizeJsonLike(value.arrowPatches),
      'relationPatches': _canonicalizeJsonLike(value.relationPatches),
      'events': _canonicalizeJsonLike(value.events),
    });
  }
  if (value is SuggestedBinding) {
    return _dropNullValues(<String, Object?>{'bindableId': value.bindableId});
  }
  if (value is ReorderArrowEvent) {
    return _dropNullValues(<String, Object?>{
      'type': value.type,
      'arrowId': value.arrowId,
      'bindableId': value.bindableId,
    });
  }
  if (value is BindingBrokenEvent) {
    return _dropNullValues(<String, Object?>{
      'type': value.type,
      'arrowId': value.arrowId,
      'edge': value.edge,
    });
  }
  if (value is EngineResult) {
    return _dropNullValues(<String, Object?>{
      'arrowPatch': _canonicalizeJsonLike(value.arrowPatch),
      'bindablePatches': _canonicalizeJsonLike(value.bindablePatches),
      'suggestedBinding': _canonicalizeJsonLike(value.suggestedBinding),
      'events': _canonicalizeJsonLike(value.events),
    });
  }
  if (value is ReduceArrowEngineEventsToOrderResult) {
    return _dropNullValues(<String, Object?>{
      'orderedElementIds': _canonicalizeJsonLike(value.orderedElementIds),
      'moved': value.moved,
      'reorderOperations': _canonicalizeJsonLike(value.reorderOperations),
      'bindingBrokenEvents': _canonicalizeJsonLike(value.bindingBrokenEvents),
    });
  }
  if (value is ApplyEngineResultValue) {
    return _dropNullValues(<String, Object?>{
      'arrow': _canonicalizeJsonLike(value.arrow),
      'bindables': _canonicalizeJsonLike(value.bindables),
      'relationPatches': _canonicalizeJsonLike(value.relationPatches),
      'orderedElementIds': _canonicalizeJsonLike(value.orderedElementIds),
      'orderChanged': value.orderChanged,
      'reorderOperations': _canonicalizeJsonLike(value.reorderOperations),
      'bindingBrokenEvents': _canonicalizeJsonLike(value.bindingBrokenEvents),
    });
  }
  if (value is ValidationReport) {
    return _dropNullValues(<String, Object?>{
      'valid': value.valid,
      'violations': _canonicalizeJsonLike(value.violations),
    });
  }
  if (value is EndpointBindingStrategy) {
    return _dropNullValues(<String, Object?>{
      'mode': value.mode,
      'bindableId': value.bindableId,
      'element': _canonicalizeJsonLike(value.element),
      'focusPoint': _canonicalizeJsonLike(value.focusPoint),
    });
  }
  if (value is PointUpdate) {
    return _dropNullValues(<String, Object?>{
      'index': value.index,
      'point': _canonicalizeJsonLike(value.point),
    });
  }
  if (value is RecomputeBindingsForChangedBindablesResult) {
    return _dropNullValues(<String, Object?>{
      'arrows': _canonicalizeJsonLike(value.arrows),
      'bindables': _canonicalizeJsonLike(value.bindables),
      'arrowPatches': _canonicalizeJsonLike(value.arrowPatches),
      'relationPatches': _canonicalizeJsonLike(value.relationPatches),
      'events': _canonicalizeJsonLike(value.events),
    });
  }
  if (value is MoveFixedSegmentToPointResult) {
    return _dropNullValues(<String, Object?>{
      'patch': _canonicalizeJsonLike(value.patch),
      'activeSegmentIndex': value.activeSegmentIndex,
      'activeSegmentMidPoint': _canonicalizeJsonLike(
        value.activeSegmentMidPoint,
      ),
    });
  }
  if (value is DirectionalLinkBounds) {
    return _dropNullValues(<String, Object?>{
      'x': value.x,
      'y': value.y,
      'width': value.width,
      'height': value.height,
    });
  }
  if (value is DirectionalLinkArrow) {
    return _dropNullValues(<String, Object?>{
      'x': value.x,
      'y': value.y,
      'points': _canonicalizeJsonLike(value.points),
    });
  }
  if (value is BoundRelationEntry) {
    return _dropNullValues(<String, Object?>{
      'id': value.id,
      'type': value.type,
    });
  }
  if (value is FocusPointDescriptor) {
    return _dropNullValues(<String, Object?>{
      'edge': value.edge,
      'point': _canonicalizeJsonLike(value.point),
      'binding': _canonicalizeJsonLike(value.binding),
    });
  }
  if (value is FocusPointHit) {
    return _dropNullValues(<String, Object?>{
      'edge': value.edge,
      'pointerOffset': _canonicalizeJsonLike(value.pointerOffset),
    });
  }
  if (value is ReorderArrowAboveElementsResult) {
    return _dropNullValues(<String, Object?>{
      'orderedElementIds': _canonicalizeJsonLike(value.orderedElementIds),
      'moved': value.moved,
      'fromIndex': value.fromIndex,
      'toIndex': value.toIndex,
      if (value is ReorderArrowAboveHoveredBindableResult)
        'hoveredBindableId': value.hoveredBindableId,
      if (value is ReorderArrowAboveHoveredBindableResult)
        'anchorElementIds': _canonicalizeJsonLike(value.anchorElementIds),
    });
  }
  if (value case (
    start: final EndpointBindingStrategy? start,
    end: final EndpointBindingStrategy? end,
  )) {
    return <String, Object?>{
      'start': start == null
          ? <String, Object?>{}
          : _canonicalizeJsonLike(start),
      'end': end == null ? <String, Object?>{} : _canonicalizeJsonLike(end),
    };
  }
  if (value case (
    rect: final Bounds rect,
    normalizedPoints: final List<Point> normalizedPoints,
  )) {
    return _dropNullValues(<String, Object?>{
      'rect': _canonicalizeJsonLike(rect),
      'normalizedPoints': _canonicalizeJsonLike(normalizedPoints),
    });
  }
  if (value case (
    rect: final Bounds rect,
    localPoints: final List<Point> localPoints,
  )) {
    return _dropNullValues(<String, Object?>{
      'rect': _canonicalizeJsonLike(rect),
      'localPoints': _canonicalizeJsonLike(localPoints),
    });
  }
  if (value case (x: final double x, y: final double y)) {
    return _dropNullValues(<String, Object?>{'x': x, 'y': y});
  }

  throw StateError(
    'Unsupported runtime value for parity canonicalization: $value',
  );
}

Map<String, Object?> _dropNullValues(Map<String, Object?> input) {
  final output = <String, Object?>{};
  for (final entry in input.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    output[entry.key] = value;
  }
  return output;
}

String? _diffJsonLike(
  Object? expected,
  Object? actual, {
  required String path,
}) {
  if (expected == null || actual == null) {
    return expected == actual
        ? null
        : '$path expected=$expected actual=$actual';
  }

  if (expected is num && actual is num) {
    final expectedValue = expected.toDouble();
    final actualValue = actual.toDouble();
    if ((expectedValue - actualValue).abs() <= 1e-6) {
      return null;
    }
    return '$path expected=$expectedValue actual=$actualValue';
  }

  if (expected is String || expected is bool) {
    return expected == actual
        ? null
        : '$path expected=$expected actual=$actual';
  }

  if (expected is List && actual is List) {
    if (expected.length != actual.length) {
      return '$path length expected=${expected.length} actual=${actual.length}';
    }
    for (var index = 0; index < expected.length; index += 1) {
      final childPath = '$path[$index]';
      final mismatch = _diffJsonLike(
        expected[index],
        actual[index],
        path: childPath,
      );
      if (mismatch != null) {
        return mismatch;
      }
    }
    return null;
  }

  if (expected is Map && actual is Map) {
    final expectedKeys = expected.keys.toSet();
    final actualKeys = actual.keys.toSet();
    if (expectedKeys.length != actualKeys.length ||
        !expectedKeys.containsAll(actualKeys) ||
        !actualKeys.containsAll(expectedKeys)) {
      return '$path keys expected=$expectedKeys actual=$actualKeys';
    }
    for (final key in expectedKeys) {
      final childPath = '$path.$key';
      final mismatch = _diffJsonLike(
        expected[key],
        actual[key],
        path: childPath,
      );
      if (mismatch != null) {
        return mismatch;
      }
    }
    return null;
  }

  return '$path expected=$expected actual=$actual';
}

File _resolveProtocolParityFixtureFile() {
  const candidates = <String>[
    'test/draw/elements/types/arrow/core/fixtures/protocol_parity_cases.json',
    'packages/snow_draw_engine/test/draw/elements/types/arrow/core/fixtures/protocol_parity_cases.json',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file;
    }
  }
  return File(candidates.first);
}
