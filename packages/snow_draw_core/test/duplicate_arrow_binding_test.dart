import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/reducers/element/delete_element_handler.dart';
import 'package:snow_draw_core/draw/services/log/log_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

class _TestDeps implements ElementReducerDeps {
  _TestDeps() : _counter = 0;
  int _counter;

  @override
  LogService get log => LogService.fallback;

  @override
  EventBus? get eventBus => null;

  @override
  String Function() get idGenerator =>
      () => 'dup-${_counter++}';

  @override
  DrawConfig get config => DrawConfig();
}

void main() {
  late _TestDeps deps;

  setUp(() {
    deps = _TestDeps();
  });

  group('handleDuplicateElements arrow binding remapping', () {
    test('arrow startBinding.elementId is remapped to duplicated target', () {
      final rect = _rect('rect-1');
      final arrow = _arrowBoundTo(id: 'arrow-1', startTargetId: 'rect-1');
      final state = _stateWith([rect, arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      expect(duplicatedArrow, isNotNull);
      final data = duplicatedArrow!.data as ArrowData;
      expect(data.startBinding, isNotNull);
      // The binding should point to the duplicated rectangle, not the
      // original.
      expect(data.startBinding!.elementId, isNot('rect-1'));
      // It should point to one of the new IDs.
      final duplicatedRect = _findDuplicated(
        result,
        originalId: 'rect-1',
        state: state,
      );
      expect(duplicatedRect, isNotNull);
      expect(data.startBinding!.elementId, duplicatedRect!.id);
    });

    test('arrow endBinding.elementId is remapped to duplicated target', () {
      final rect = _rect('rect-1');
      final arrow = _arrowBoundTo(id: 'arrow-1', endTargetId: 'rect-1');
      final state = _stateWith([rect, arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      expect(duplicatedArrow, isNotNull);
      final data = duplicatedArrow!.data as ArrowData;
      expect(data.endBinding, isNotNull);
      expect(data.endBinding!.elementId, isNot('rect-1'));
    });

    test('both start and end bindings are remapped', () {
      final rect1 = _rect('rect-1');
      final rect2 = _rect(
        'rect-2',
        rect: const DrawRect(minX: 200, maxX: 300, maxY: 100),
      );
      final arrow = _arrowBoundTo(
        id: 'arrow-1',
        startTargetId: 'rect-1',
        endTargetId: 'rect-2',
      );
      final state = _stateWith([rect1, rect2, arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'rect-2', 'arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      final data = duplicatedArrow!.data as ArrowData;
      final dupRect1 = _findDuplicated(
        result,
        originalId: 'rect-1',
        state: state,
      );
      final dupRect2 = _findDuplicated(
        result,
        originalId: 'rect-2',
        state: state,
      );
      expect(data.startBinding!.elementId, dupRect1!.id);
      expect(data.endBinding!.elementId, dupRect2!.id);
    });

    test('binding to non-duplicated target is cleared', () {
      // rect-outside is NOT in the duplication set.
      final rectOutside = _rect('rect-outside');
      final arrow = _arrowBoundTo(id: 'arrow-1', startTargetId: 'rect-outside');
      final state = _stateWith([rectOutside, arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      expect(duplicatedArrow, isNotNull);
      final data = duplicatedArrow!.data as ArrowData;
      // Binding target was not duplicated, so binding should be
      // cleared.
      expect(data.startBinding, isNull);
    });

    test('line bindings are also remapped', () {
      final rect = _rect('rect-1');
      final line = _lineBoundTo(id: 'line-1', startTargetId: 'rect-1');
      final state = _stateWith([rect, line]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'line-1']),
        deps,
      );

      final duplicatedLine = _findDuplicated(
        result,
        originalId: 'line-1',
        state: state,
      );
      expect(duplicatedLine, isNotNull);
      final data = duplicatedLine!.data as LineData;
      expect(data.startBinding, isNotNull);
      expect(data.startBinding!.elementId, isNot('rect-1'));
    });

    test('anchor is preserved during binding remapping', () {
      final rect = _rect('rect-1');
      const anchor = DrawPoint(x: 0.3, y: 0.7);
      const arrow = ElementState(
        id: 'arrow-1',
        rect: DrawRect(minX: 50, minY: 50, maxX: 150, maxY: 150),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: ArrowData(
          startBinding: ArrowBinding(elementId: 'rect-1', anchor: anchor),
        ),
      );
      final state = _stateWith([rect, arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      final data = duplicatedArrow!.data as ArrowData;
      expect(data.startBinding!.anchor, anchor);
    });

    test('serial number textElementId is still remapped correctly', () {
      // Ensure the existing serial number remapping still works.
      const textElement = ElementState(
        id: 'text-1',
        rect: DrawRect(maxX: 50, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(text: '1'),
      );
      const serial = ElementState(
        id: 'serial-1',
        rect: DrawRect(maxX: 30, maxY: 30),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: SerialNumberData(textElementId: 'text-1'),
      );
      final state = _stateWith([textElement, serial]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['serial-1']),
        deps,
      );

      final duplicatedSerial = _findDuplicated(
        result,
        originalId: 'serial-1',
        state: state,
      );
      expect(duplicatedSerial, isNotNull);
      final data = duplicatedSerial!.data as SerialNumberData;
      // The bound text was also duplicated (auto-included).
      final duplicatedText = _findDuplicated(
        result,
        originalId: 'text-1',
        state: state,
      );
      expect(duplicatedText, isNotNull);
      expect(data.textElementId, duplicatedText!.id);
    });

    test('arrow with no bindings is duplicated unchanged', () {
      const arrow = ElementState(
        id: 'arrow-1',
        rect: DrawRect(maxX: 100, maxY: 100),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: ArrowData(),
      );
      final state = _stateWith([arrow]);

      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['arrow-1']),
        deps,
      );

      final duplicated = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      expect(duplicated, isNotNull);
      final data = duplicated!.data as ArrowData;
      expect(data.startBinding, isNull);
      expect(data.endBinding, isNull);
    });

    test('mixed: one binding remapped, other cleared', () {
      final rect1 = _rect('rect-1');
      final rectOutside = _rect(
        'rect-outside',
        rect: const DrawRect(minX: 300, maxX: 400, maxY: 100),
      );
      final arrow = _arrowBoundTo(
        id: 'arrow-1',
        startTargetId: 'rect-1',
        endTargetId: 'rect-outside',
      );
      final state = _stateWith([rect1, rectOutside, arrow]);

      // Only rect-1 and arrow-1 are duplicated, not rect-outside.
      final result = handleDuplicateElements(
        state,
        const DuplicateElements(elementIds: ['rect-1', 'arrow-1']),
        deps,
      );

      final duplicatedArrow = _findDuplicated(
        result,
        originalId: 'arrow-1',
        state: state,
      );
      final data = duplicatedArrow!.data as ArrowData;
      final dupRect1 = _findDuplicated(
        result,
        originalId: 'rect-1',
        state: state,
      );
      // Start binding target was duplicated → remapped.
      expect(data.startBinding!.elementId, dupRect1!.id);
      // End binding target was NOT duplicated → cleared.
      expect(data.endBinding, isNull);
    });
  });
}

// -- Helpers --

ElementState _rect(String id, {DrawRect? rect}) => ElementState(
  id: id,
  rect: rect ?? const DrawRect(maxX: 100, maxY: 100),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

ElementState _arrowBoundTo({
  required String id,
  String? startTargetId,
  String? endTargetId,
}) => ElementState(
  id: id,
  rect: const DrawRect(minX: 50, minY: 50, maxX: 150, maxY: 150),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: ArrowData(
    startBinding: startTargetId == null
        ? null
        : ArrowBinding(
            elementId: startTargetId,
            anchor: const DrawPoint(x: 0.5, y: 0.5),
          ),
    endBinding: endTargetId == null
        ? null
        : ArrowBinding(
            elementId: endTargetId,
            anchor: const DrawPoint(x: 0.5, y: 0.5),
          ),
  ),
);

ElementState _lineBoundTo({
  required String id,
  String? startTargetId,
  String? endTargetId,
}) => ElementState(
  id: id,
  rect: const DrawRect(minX: 50, minY: 50, maxX: 150, maxY: 150),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: LineData(
    startBinding: startTargetId == null
        ? null
        : ArrowBinding(
            elementId: startTargetId,
            anchor: const DrawPoint(x: 0.5, y: 0.5),
          ),
    endBinding: endTargetId == null
        ? null
        : ArrowBinding(
            elementId: endTargetId,
            anchor: const DrawPoint(x: 0.5, y: 0.5),
          ),
  ),
);

DrawState _stateWith(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

/// Finds the duplicated copy of an original element by looking for new
/// elements that weren't in the original state.
ElementState? _findDuplicated(
  DrawState result, {
  required String originalId,
  required DrawState state,
}) {
  final originalIds = state.domain.document.elements.map((e) => e.id).toSet();
  final newElements = result.domain.document.elements.where(
    (e) => !originalIds.contains(e.id),
  );
  // Match by data type and position offset pattern.
  for (final element in newElements) {
    final original = state.domain.document.getElementById(originalId);
    if (original == null) {
      continue;
    }
    if (element.data.typeId == original.data.typeId) {
      // Verify it's offset from the original (default offset is 10,10).
      final dx = element.rect.minX - original.rect.minX;
      final dy = element.rect.minY - original.rect.minY;
      if ((dx - 10).abs() < 0.01 && (dy - 10).abs() < 0.01) {
        return element;
      }
    }
  }
  return null;
}
