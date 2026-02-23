import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('FrameRenderPlanBuilder', () {
    const builder = FrameRenderPlanBuilder();

    test('encodes preview-only elements from transient render inputs', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);

      const persistedElement = ElementState(
        id: 'persisted-line',
        rect: DrawRect(maxX: 80, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: LineData(),
      );
      const previewOnlyElement = ElementState(
        id: 'preview-rect',
        rect: DrawRect(minX: 24, minY: 12, maxX: 120, maxY: 64),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: RectangleData(),
      );

      final view = DrawStateView.fromState(
        DrawState(
          domain: DomainState(
            document: DocumentState(elements: const [persistedElement]),
          ),
          application: const ApplicationState(view: ViewState()),
        ),
      );

      final plan = builder.build(
        view: view,
        elementRegistry: registry,
        scaleFactor: 1,
        transientState: const FrameRenderTransientState(
          previewElementsById: {'preview-rect': previewOnlyElement},
        ),
      );

      final encodedIds = <String>[
        for (final task in plan.tasks)
          if (task case ElementRenderTask(:final element)) element.id,
      ];
      expect(
        encodedIds,
        containsAllInOrder(<String>['persisted-line', 'preview-rect']),
      );
      expect(encodedIds.where((id) => id == 'preview-rect').length, 1);
    });

    test(
      'does not duplicate persisted elements from transient preview map',
      () {
        final registry = DefaultElementRegistry();
        registerBuiltInElements(registry);

        const persistedElement = ElementState(
          id: 'line-1',
          rect: DrawRect(maxX: 80, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: LineData(),
        );

        final view = DrawStateView.fromState(
          DrawState(
            domain: DomainState(
              document: DocumentState(elements: const [persistedElement]),
            ),
            application: const ApplicationState(view: ViewState()),
          ),
        );

        final plan = builder.build(
          view: view,
          elementRegistry: registry,
          scaleFactor: 1,
          transientState: const FrameRenderTransientState(
            previewElementsById: {'line-1': persistedElement},
          ),
        );

        final encodedIds = <String>[
          for (final task in plan.tasks)
            if (task case ElementRenderTask(:final element)) element.id,
        ];
        expect(encodedIds.where((id) => id == 'line-1').length, 1);
      },
    );

    test('normalizes invalid scale factors to a stable fallback', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);

      final view = DrawStateView.fromState(
        DrawState(
          domain: DomainState(document: DocumentState()),
          application: const ApplicationState(view: ViewState()),
        ),
      );
      const invalidScales = <double>[0, -1, double.nan, double.infinity];

      for (final scale in invalidScales) {
        final plan = builder.build(
          view: view,
          elementRegistry: registry,
          scaleFactor: scale,
        );
        expect(plan.scaleFactor, 1.0, reason: 'Expected fallback for $scale');
      }
    });
  });
}
