import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_engine/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_engine/draw/edit/rotate/rotate_operation.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_geometry.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('RotateOperation elbow arrows', () {
    test('does not rotate selected elbow arrows', () {
      final arrow = _elbowArrowElement(
        id: 'arrow-elbow',
        points: const <DrawPoint>[
          DrawPoint(x: 40, y: 50),
          DrawPoint(x: 60, y: 50),
          DrawPoint(x: 60, y: 70),
        ],
      );
      final state = _stateWithElements(
        <ElementState>[arrow],
        selectedIds: <String>{arrow.id},
      );
      const operation = RotateOperation();
      const startPointer = DrawPoint(x: 60, y: 60);
      const currentPointer = DrawPoint(x: 50, y: 70);

      final context = operation.createContext(
        state: state,
        position: startPointer,
        params: const RotateOperationParams(),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: startPointer,
      );
      final update = operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: currentPointer,
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final nextState = operation.finish(
        state: state,
        context: context,
        transform: update.transform,
      );

      final rotated = nextState.domain.document.getElementById(arrow.id)!;
      expect(rotated.rotation, equals(0));
      expect(rotated.rect, equals(arrow.rect));
      expect(rotated.data, equals(arrow.data));
    });
  });
}

DrawState _stateWithElements(
  List<ElementState> elements, {
  required Set<String> selectedIds,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

ElementState _elbowArrowElement({
  required String id,
  required List<DrawPoint> points,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: ArrowData(
      points: normalized,
      arrowType: ArrowType.elbow,
      startArrowhead: ArrowheadStyle.standard,
    ),
  );
}
