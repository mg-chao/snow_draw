import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart'
    as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bindable_query.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_endpoint_drag.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_ops.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_endpoint_drag', () {
    test(
      'computeArrowCoreEndpointDragResult snaps endpoint via arrow-core',
      () {
        final bindable = _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 60, y: 60),
            DrawPoint(x: 160, y: 60),
          ],
          zIndex: 2,
        );
        final state = _stateWithElements(<ElementState>[bindable, arrow]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 240, y: 60),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
        );

        expect(result, isNotNull);
        expect(result!.endBinding, isNotNull);
        expect(result.endBinding!.elementId, bindable.id);
        expect(result.localPoints, hasLength(2));
      },
    );

    test(
      'finalizeArrowCoreEndpointDragResult supports point fallback reorder',
      () {
        final bindable = _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, minY: 20, maxX: 320, maxY: 120),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 60, y: 60),
            DrawPoint(x: 220, y: 60),
          ],
          zIndex: 0,
          endBinding: const ArrowBinding(
            elementId: 'rect-target',
            anchor: DrawPoint(x: 0, y: 0.5),
          ),
        );
        final state = _stateWithElements(<ElementState>[arrow, bindable]);
        final data = arrow.data as ArrowData;

        final result = finalizeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 220, y: 60),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 0,
          coreEngineContext: buildCoreEngineContext(),
          orderedElementIds: const <String>['arrow-1', 'rect-target'],
        );

        expect(result, isNotNull);
        expect(result!.orderedElementIds, <String>['rect-target', 'arrow-1']);
      },
    );

    test(
      'computeArrowCoreEndpointDragResult disables existing binding when new bindings are disallowed',
      () {
        final bindable = _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, minY: 20, maxX: 320, maxY: 120),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 60, y: 60),
            DrawPoint(x: 220, y: 60),
          ],
          zIndex: 0,
          endBinding: const ArrowBinding(
            elementId: 'rect-target',
            anchor: DrawPoint(x: 0, y: 0.5),
          ),
        );
        final state = _stateWithElements(<ElementState>[arrow, bindable]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 220, y: 60),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: false,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
        );

        expect(result, isNotNull);
        expect(result!.endBinding, isNull);
      },
    );

    test(
      'computeArrowCoreEndpointDragResult keeps opposite endpoint binding when new bindings are disallowed',
      () {
        final startTarget = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final endTarget = _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(minX: 220, minY: 20, maxX: 320, maxY: 120),
          zIndex: 2,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 70, y: 70),
            DrawPoint(x: 270, y: 70),
          ],
          zIndex: 0,
          startBinding: const ArrowBinding(
            elementId: 'rect-start',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
          endBinding: const ArrowBinding(
            elementId: 'rect-end',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
        );
        final state = _stateWithElements(<ElementState>[
          arrow,
          startTarget,
          endTarget,
        ]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 420, y: 300),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: false,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
        );

        expect(result, isNotNull);
        expect(result!.startBinding?.elementId, 'rect-start');
        expect(result.endBinding, isNull);
      },
    );

    test('new-arrow drag keeps dragged endpoint anchor at pointer focus', () {
      final bindable = _rectangleElement(
        id: 'rect-target',
        rect: const DrawRect(minX: 300, minY: 100, maxX: 500, maxY: 200),
        zIndex: 0,
      );
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 200, y: 0),
        ],
        zIndex: 1,
      );
      final state = _stateWithElements(<ElementState>[bindable, arrow]);
      final data = arrow.data as ArrowData;

      final result = computeArrowCoreEndpointDragResult(
        state: state,
        element: arrow,
        data: data,
        localPoints: _resolveLocalPoints(arrow, data),
        draggedIndex: 1,
        worldPointer: const DrawPoint(x: 350, y: 120),
        startBinding: data.startBinding,
        endBinding: data.endBinding,
        excludedElementId: arrow.id,
        shouldLookupBindings: true,
        allowNewBinding: true,
        bindingDistance: 80,
        coreEngineContext: buildCoreEngineContext(),
        options: const <String, dynamic>{'newArrow': true},
      );

      expect(result, isNotNull);
      final binding = result!.endBinding;
      expect(binding, isNotNull);
      expect(binding!.elementId, bindable.id);
      expect(binding.anchor.x, closeTo(0.25, 1e-6));
      expect(binding.anchor.y, closeTo(0.2, 1e-6));
    });

    test(
      'strategy reorder suggestion ignores opposite endpoint binding strategy',
      () {
        final startTarget = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 0, minY: 0, maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 40, y: 40),
            DrawPoint(x: 220, y: 40),
          ],
          zIndex: 0,
          startBinding: const ArrowBinding(
            elementId: 'rect-start',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
            mode: ArrowBindingMode.inside,
          ),
        );
        final state = _stateWithElements(<ElementState>[arrow, startTarget]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 420, y: 220),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
          orderedElementIds: const <String>['arrow-1', 'rect-start'],
          options: const <String, dynamic>{
            'newArrow': true,
            'preserveOppositeInsideBinding': true,
          },
        );

        expect(result, isNotNull);
        expect(result!.orderedElementIds, isNull);
      },
    );

    test(
      'computeArrowCoreEndpointDragResult keeps opposite elbow endpoint binding',
      () {
        final startTarget = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final endTarget = _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
          zIndex: 2,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 70, y: 70),
            DrawPoint(x: 220, y: 70),
          ],
          zIndex: 0,
          arrowType: ArrowType.elbow,
          startBinding: const ArrowBinding(
            elementId: 'rect-start',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
        );
        final state = _stateWithElements(<ElementState>[
          arrow,
          startTarget,
          endTarget,
        ]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 280, y: 70),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
          orderedElementIds: const <String>[
            'arrow-1',
            'rect-start',
            'rect-end',
          ],
        );

        expect(result, isNotNull);
        expect(result!.startBinding?.elementId, 'rect-start');
        expect(result.endBinding?.elementId, 'rect-end');
      },
    );

    test(
      'computeArrowCoreEndpointDragResult unbinds dragged elbow endpoint when no hovered bindable',
      () {
        final startTarget = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final endTarget = _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
          zIndex: 2,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 70, y: 70),
            DrawPoint(x: 280, y: 70),
          ],
          zIndex: 0,
          arrowType: ArrowType.elbow,
          startBinding: const ArrowBinding(
            elementId: 'rect-start',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
          endBinding: const ArrowBinding(
            elementId: 'rect-end',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
        );
        final state = _stateWithElements(<ElementState>[
          arrow,
          startTarget,
          endTarget,
        ]);
        final data = arrow.data as ArrowData;

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: const DrawPoint(x: 520, y: 340),
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 40,
          coreEngineContext: buildCoreEngineContext(),
        );

        expect(result, isNotNull);
        expect(result!.startBinding?.elementId, 'rect-start');
        expect(result.endBinding, isNull);
      },
    );

    test(
      'computeArrowCoreEndpointDragResult mirrors core endpoint patch application for complex overlap drag',
      () {
        final startTarget = _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
          zIndex: 1,
        );
        final endTarget = _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(minX: 240, minY: 20, maxX: 340, maxY: 120),
          zIndex: 2,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 70, y: 70),
            DrawPoint(x: 290, y: 70),
          ],
          zIndex: 0,
          startBinding: const ArrowBinding(
            elementId: 'rect-start',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
          endBinding: const ArrowBinding(
            elementId: 'rect-end',
            anchor: DrawPoint(x: 0.5001, y: 0.5001),
          ),
        );
        final state = _stateWithElements(<ElementState>[
          arrow,
          startTarget,
          endTarget,
        ]);
        final data = arrow.data as ArrowData;
        const worldPointer = DrawPoint(x: 90, y: 70);

        final result = computeArrowCoreEndpointDragResult(
          state: state,
          element: arrow,
          data: data,
          localPoints: _resolveLocalPoints(arrow, data),
          draggedIndex: 1,
          worldPointer: worldPointer,
          startBinding: data.startBinding,
          endBinding: data.endBinding,
          excludedElementId: arrow.id,
          shouldLookupBindings: true,
          allowNewBinding: true,
          bindingDistance: 80,
          coreEngineContext: buildCoreEngineContext(),
          options: const <String, dynamic>{'complexBindings': true},
        );

        expect(result, isNotNull);

        final coreArrow = toCoreArrowState(
          element: arrow,
          data: data,
          localPointsOverride: _resolveLocalPoints(arrow, data),
          startBindingOverride: data.startBinding,
          endBindingOverride: data.endBinding,
        );
        final candidates = resolveCoreBindableCandidatesForEndpointStrategy(
          document: state.domain.document,
          allowNewBinding: true,
          activeBinding: data.endBinding,
          oppositeBinding: data.startBinding,
          excludedElementId: arrow.id,
        );
        final engineResult = computeCoreEndpointDrag(
          arrow: coreArrow,
          draggedPoints: <int, core.Point>{
            1: <double>[
              worldPointer.x - coreArrow.x,
              worldPointer.y - coreArrow.y,
            ],
          },
          pointer: <double>[worldPointer.x, worldPointer.y],
          bindables: candidates.bindables,
          context: buildCoreEngineContext(),
          options: const <String, dynamic>{'complexBindings': true},
        );
        final expectedArrow = core.applyArrowPatch(
          coreArrow,
          engineResult.arrowPatch,
        );

        expect(result!.arrow.x, closeTo(expectedArrow.x, 1e-9));
        expect(result.arrow.y, closeTo(expectedArrow.y, 1e-9));
        expect(result.arrow.width, closeTo(expectedArrow.width, 1e-9));
        expect(result.arrow.height, closeTo(expectedArrow.height, 1e-9));
        expect(result.arrow.points.length, expectedArrow.points.length);
        for (var index = 0; index < expectedArrow.points.length; index += 1) {
          expect(
            result.arrow.points[index][0],
            closeTo(expectedArrow.points[index][0], 1e-9),
          );
          expect(
            result.arrow.points[index][1],
            closeTo(expectedArrow.points[index][1], 1e-9),
          );
        }
        expect(
          result.arrow.startBinding?.elementId,
          expectedArrow.startBinding?.elementId,
        );
        expect(
          result.arrow.endBinding?.elementId,
          expectedArrow.endBinding?.elementId,
        );
      },
    );
  });
}

DrawState _stateWithElements(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowType arrowType = ArrowType.straight,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      arrowType: arrowType,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) =>
    ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
