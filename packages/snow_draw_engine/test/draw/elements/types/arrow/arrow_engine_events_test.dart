import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart'
    as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_engine_events.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_engine_events', () {
    test(
      'reduceArrowEngineEventsToOrderedIds reorders arrow above bindable',
      () {
        final ordered = reduceArrowEngineEventsToOrderedIds(
          orderedElementIds: const <String>['arrow-1', 'rect-1'],
          events: const <core.ArrowEngineEvent>[
            core.ReorderArrowEvent(arrowId: 'arrow-1', bindableId: 'rect-1'),
          ],
        );

        expect(ordered, isNotNull);
        expect(ordered, <String>['rect-1', 'arrow-1']);
      },
    );

    test(
      'reduceArrowEngineEventsToOrderedIds supports anchor ids for bindables',
      () {
        final ordered = reduceArrowEngineEventsToOrderedIds(
          orderedElementIds: const <String>['arrow-1', 'rect-1', 'text-1'],
          events: const <core.ArrowEngineEvent>[
            core.ReorderArrowEvent(arrowId: 'arrow-1', bindableId: 'rect-1'),
          ],
          anchorElementIdsByBindableId: const <String, List<String>>{
            'rect-1': <String>['rect-1', 'text-1'],
          },
        );

        expect(ordered, isNotNull);
        expect(ordered, <String>['rect-1', 'arrow-1', 'text-1']);
      },
    );

    test('reduceArrowEngineEventsToOrderedIds ignores non-order events', () {
      final ordered = reduceArrowEngineEventsToOrderedIds(
        orderedElementIds: const <String>['arrow-1', 'rect-1'],
        events: const <core.ArrowEngineEvent>[
          core.BindingBrokenEvent(
            arrowId: 'arrow-1',
            edge: core.arrowEndpointStart,
          ),
        ],
      );

      expect(ordered, isNull);
    });
  });
}
