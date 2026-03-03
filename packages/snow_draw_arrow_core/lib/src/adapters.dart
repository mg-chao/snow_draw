import 'arrow_engine.dart';
import 'arrow_types.dart';

abstract interface class ArrowEngineAdapter {
  List<BindableState> zOrderBindables();

  BindableState? resolveBindable(String id) => null;

  void onArrowNeedsReorder(String arrowId, String bindableId) {}

  void onBindingBroken(String arrowId, ArrowEndpointEdge edge) {}
}

ArrowState applyArrowPatch(ArrowState arrow, ArrowPatch patch) {
  final hasX = patch.containsKey('x');
  final hasY = patch.containsKey('y');
  final hasWidth = patch.containsKey('width');
  final hasHeight = patch.containsKey('height');
  final hasPoints = patch.containsKey('points');
  final hasStartBinding = patch.containsKey('startBinding');
  final hasEndBinding = patch.containsKey('endBinding');
  final hasFixedSegments = patch.containsKey('fixedSegments');
  final hasStartIsSpecial = patch.containsKey('startIsSpecial');
  final hasEndIsSpecial = patch.containsKey('endIsSpecial');

  return arrow.copyWith(
    x: hasX && patch['x'] is num ? (patch['x'] as num).toDouble() : null,
    y: hasY && patch['y'] is num ? (patch['y'] as num).toDouble() : null,
    width: hasWidth && patch['width'] is num
        ? (patch['width'] as num).toDouble()
        : null,
    height: hasHeight && patch['height'] is num
        ? (patch['height'] as num).toDouble()
        : null,
    points: hasPoints && patch['points'] is List
        ? (patch['points'] as List)
              .map((point) => (point as List).cast<double>())
              .toList(growable: false)
        : null,
    startBinding: hasStartBinding
        ? patch['startBinding'] as FixedPointBinding?
        : null,
    setStartBinding: hasStartBinding,
    endBinding: hasEndBinding
        ? patch['endBinding'] as FixedPointBinding?
        : null,
    setEndBinding: hasEndBinding,
    fixedSegments: hasFixedSegments
        ? (patch['fixedSegments'] as List?)
              ?.map((segment) => segment as FixedSegment)
              .toList(growable: false)
        : null,
    setFixedSegments: hasFixedSegments,
    startIsSpecial: hasStartIsSpecial ? patch['startIsSpecial'] as bool? : null,
    setStartIsSpecial: hasStartIsSpecial,
    endIsSpecial: hasEndIsSpecial ? patch['endIsSpecial'] as bool? : null,
    setEndIsSpecial: hasEndIsSpecial,
  );
}

void forwardAdapterEvents(
  ArrowEngineAdapter adapter,
  List<ArrowEngineEvent> events,
) {
  for (final event in events) {
    if (event is ReorderArrowEvent) {
      adapter.onArrowNeedsReorder(event.arrowId, event.bindableId);
      continue;
    }
    if (event is BindingBrokenEvent) {
      adapter.onBindingBroken(event.arrowId, event.edge);
      continue;
    }
    throw StateError('Unsupported ArrowEngineEvent: ${event.runtimeType}');
  }
}

EngineResult executeWithAdapter(
  ArrowEngineAdapter adapter,
  EngineResult Function(List<BindableState> bindables) run,
) {
  final bindables = adapter.zOrderBindables();
  final result = run(bindables);
  forwardAdapterEvents(adapter, result.events);
  return result;
}

final ArrowEngineV1 = (
  create: createArrowEngine,
  applyArrowPatch: applyArrowPatch,
  executeWithAdapter: executeWithAdapter,
);
