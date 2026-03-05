import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_ops.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_ops wrappers', () {
    test('resolveCoreMaxBindingDistance mirrors core maxBindingDistance', () {
      expect(
        resolveCoreMaxBindingDistance(zoom: 0.5),
        closeTo(core.maxBindingDistance(0.5), 1e-9),
      );
      expect(
        resolveCoreMaxBindingDistance(zoom: 1),
        closeTo(core.maxBindingDistance(1), 1e-9),
      );
      expect(
        resolveCoreMaxBindingDistance(zoom: 2),
        closeTo(core.maxBindingDistance(2), 1e-9),
      );
    });

    test('resolveCoreEndpointBindingStrategy defaults to legacy parity', () {
      final arrow = _arrowState(
        startBinding: const core.FixedPointBinding(
          elementId: 'bindable-1',
          fixedPoint: <double>[0.75, 0.5],
          mode: core.bindModeOrbit,
        ),
      );
      final bindable = _bindableState();
      final strategies = resolveCoreEndpointBindingStrategy(
        arrow: arrow,
        draggedPoints: const <int, core.Point>{
          1: <double>[60, 0],
        },
        pointer: const <double>[60, 0],
        bindables: <core.BindableState>[bindable],
        context: buildCoreEngineContext(),
      );

      expect(strategies.start, isNotNull);
      expect(strategies.start!.bindableId, bindable.id);
      expect(strategies.start!.mode, core.bindModeInside);
      expect(strategies.end, isNotNull);
      expect(strategies.end!.bindableId, bindable.id);
      expect(strategies.end!.mode, core.bindModeInside);
    });

    test('bind/unbind relation wrappers preserve relation patches', () {
      final arrow = _arrowState();
      final bindable = _bindableState();
      final relations = <core.BindableRelationState>[
        const core.BindableRelationState(
          id: 'bindable-1',
          boundArrowIds: <String>[],
        ),
      ];

      final bindMutation = bindCoreArrowEndpointWithRelations(
        arrow: arrow,
        edge: core.arrowEndpointStart,
        bindable: bindable,
        relations: relations,
        mode: core.bindModeInside,
        focusPoint: const <double>[60, 0],
      );
      expect(bindMutation.arrowPatch, isNotEmpty);
      expect(bindMutation.relationPatches, hasLength(1));
      expect(
        bindMutation.relationPatches.first.boundArrowIds,
        contains('arrow-1'),
      );

      final boundArrow = core.applyArrowPatch(arrow, bindMutation.arrowPatch);
      final unbindMutation = unbindCoreArrowEndpointWithRelations(
        arrow: boundArrow,
        edge: core.arrowEndpointStart,
        relations: <core.BindableRelationState>[
          const core.BindableRelationState(
            id: 'bindable-1',
            boundArrowIds: <String>['arrow-1'],
          ),
        ],
      );
      expect(unbindMutation.arrowPatch, isNotEmpty);
      expect(unbindMutation.relationPatches, hasLength(1));
      expect(unbindMutation.relationPatches.first.boundArrowIds, isEmpty);
    });

    test('updateCoreBoundPoint resolves inside-binding endpoint position', () {
      final arrow = _arrowState(startBinding: _insideBinding());
      final bindable = _bindableState();
      final point = updateCoreBoundPoint(
        arrow: arrow,
        edge: 'startBinding',
        binding: _insideBinding(),
        bindable: bindable,
        bindablesById: <core.BindableState>[bindable],
      );

      expect(point, isNotNull);
      expect(point![0], closeTo(60.004, 1e-6));
      expect(point[1], closeTo(0.004, 1e-6));
    });
  });
}

core.ArrowState _arrowState({core.FixedPointBinding? startBinding}) =>
    core.ArrowState(
      id: 'arrow-1',
      x: 0,
      y: 0,
      width: 100,
      height: 0,
      points: const <core.Point>[
        <double>[0, 0],
        <double>[100, 0],
      ],
      startBinding: startBinding,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: 'arrow',
      elbowed: false,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );

core.BindableState _bindableState() => const core.BindableState(
  id: 'bindable-1',
  shape: 'rectangle',
  x: 40,
  y: -20,
  width: 40,
  height: 40,
  angle: 0,
  strokeWidth: 2,
  zIndex: 1,
  backgroundOpaque: true,
  bindingEnabled: true,
  interiorHitEnabled: true,
);

core.FixedPointBinding _insideBinding() => const core.FixedPointBinding(
  elementId: 'bindable-1',
  fixedPoint: <double>[0.5, 0.5],
  mode: core.bindModeInside,
);
