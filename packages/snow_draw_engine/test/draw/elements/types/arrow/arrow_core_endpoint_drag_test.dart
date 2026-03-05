import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_endpoint_drag.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
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
          allowNewBinding: false,
          bindingDistance: 0,
          coreEngineContext: buildCoreEngineContext(),
          orderedElementIds: const <String>['arrow-1', 'rect-target'],
        );

        expect(result, isNotNull);
        expect(result!.orderedElementIds, <String>['rect-target', 'arrow-1']);
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
