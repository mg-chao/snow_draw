import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
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
  @override
  DrawConfig get config => DrawConfig();

  @override
  EventBus? get eventBus => null;

  @override
  String Function() get idGenerator =>
      () => 'unused';

  @override
  LogService get log => LogService.fallback;
}

void main() {
  final deps = _TestDeps();

  group('handleDeleteElements', () {
    test('deleting a bound target clears arrow binding', () {
      final state = _stateWithElements([
        _filterElement(id: 'target', zIndex: 0),
        const ElementState(
          id: 'arrow',
          rect: DrawRect(minX: 60, maxX: 120, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: ArrowData(
            startBinding: ArrowBinding(
              elementId: 'target',
              anchor: DrawPoint(x: 0.5, y: 0.5),
            ),
          ),
        ),
      ]);

      final next = handleDeleteElements(
        state,
        DeleteElements(elementIds: ['target']),
        deps,
      );

      expect(next.domain.document.getElementById('target'), isNull);
      final arrow = next.domain.document.getElementById('arrow');
      expect(arrow, isNotNull);
      final data = arrow!.data as ArrowData;
      expect(data.startBinding, isNull);
    });

    test('deleting a bound target clears line end binding flags', () {
      final state = _stateWithElements([
        _filterElement(id: 'target', zIndex: 0),
        const ElementState(
          id: 'line',
          rect: DrawRect(minX: 10, maxX: 80, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(
            endBinding: ArrowBinding(
              elementId: 'target',
              anchor: DrawPoint(x: 0.2, y: 0.8),
            ),
            endIsSpecial: true,
          ),
        ),
      ]);

      final next = handleDeleteElements(
        state,
        DeleteElements(elementIds: ['target']),
        deps,
      );

      final line = next.domain.document.getElementById('line');
      expect(line, isNotNull);
      final data = line!.data as LineData;
      expect(data.endBinding, isNull);
      expect(data.endIsSpecial, isNull);
    });

    test(
      'serial updates are order independent when deleting shared bound text',
      () {
        const sharedTextId = 'text-shared';
        final state = _stateWithElements(const [
          ElementState(
            id: 'serial-keep',
            rect: DrawRect(maxX: 30, maxY: 30),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: SerialNumberData(textElementId: sharedTextId),
          ),
          ElementState(
            id: 'serial-delete',
            rect: DrawRect(minX: 40, maxX: 70, maxY: 30),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: SerialNumberData(number: 2, textElementId: sharedTextId),
          ),
          ElementState(
            id: sharedTextId,
            rect: DrawRect(minY: 40, maxX: 50, maxY: 70),
            rotation: 0,
            opacity: 1,
            zIndex: 2,
            data: TextData(text: 'shared'),
          ),
        ]);

        final next = handleDeleteElements(
          state,
          DeleteElements(elementIds: ['serial-delete']),
          deps,
        );

        final kept = next.domain.document.getElementById('serial-keep');
        expect(kept, isNotNull);
        expect((kept!.data as SerialNumberData).textElementId, isNull);
        expect(next.domain.document.getElementById('serial-delete'), isNull);
        expect(next.domain.document.getElementById(sharedTextId), isNull);
      },
    );

    test('delete expansion preserves transitive serial->text references', () {
      final state = _stateWithElements(const [
        ElementState(
          id: 'serial-a',
          rect: DrawRect(maxX: 30, maxY: 30),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(textElementId: 'serial-b'),
        ),
        ElementState(
          id: 'serial-b',
          rect: DrawRect(minX: 40, maxX: 70, maxY: 30),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: SerialNumberData(textElementId: 'text-c'),
        ),
        ElementState(
          id: 'text-c',
          rect: DrawRect(minY: 40, maxX: 50, maxY: 70),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: TextData(text: 'leaf'),
        ),
      ]);

      final next = handleDeleteElements(
        state,
        DeleteElements(elementIds: ['serial-a']),
        deps,
      );

      expect(next.domain.document.getElementById('serial-a'), isNull);
      expect(next.domain.document.getElementById('serial-b'), isNull);
      expect(next.domain.document.getElementById('text-c'), isNull);
    });
  });
}

DrawState _stateWithElements(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

ElementState _filterElement({required String id, required int zIndex}) =>
    ElementState(
      id: id,
      rect: const DrawRect(maxX: 50, maxY: 50),
      rotation: 0,
      opacity: 1,
      zIndex: zIndex,
      data: const FilterData(),
    );
