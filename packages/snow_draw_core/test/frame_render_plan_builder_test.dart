import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('FrameRenderPlanBuilder', () {
    const builder = FrameRenderPlanBuilder();

    test('omits element render tasks even when document has elements', () {
      final view = DrawStateView.fromState(
        DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'line-1',
                  rect: DrawRect(maxX: 80, maxY: 40),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: LineData(),
                ),
              ],
            ),
          ),
          application: const ApplicationState(view: ViewState()),
        ),
      );

      final plan = builder.build(
        view: view,
        scaleFactor: 1,
        transientState: const FrameRenderTransientState(
          canvasConfig: CanvasConfig(),
        ),
      );

      expect(plan.tasks.whereType<ElementRenderTask>().isEmpty, isTrue);
      expect(plan.tasks.whereType<BackgroundRenderTask>().length, 1);
      expect(plan.sceneRevision, view.state.domain.document.elementsVersion);
    });

    test('uses preview geometry for overlay tasks', () {
      const persisted = ElementState(
        id: 'line-1',
        rect: DrawRect(maxX: 80, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: LineData(),
      );
      const preview = ElementState(
        id: 'line-1',
        rect: DrawRect(minX: 24, minY: 12, maxX: 120, maxY: 64),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: LineData(),
      );

      final view = DrawStateView.fromState(
        DrawState(
          domain: DomainState(
            document: DocumentState(elements: const [persisted]),
          ),
          application: const ApplicationState(view: ViewState()),
        ),
      );

      final plan = builder.build(
        view: view,
        scaleFactor: 1,
        transientState: const FrameRenderTransientState(
          hoveredElementId: 'line-1',
          hoverSelectionConfig: SelectionConfig(),
          previewElementsById: {'line-1': preview},
        ),
      );

      final hoverTask = plan.tasks.whereType<HoverOutlineRenderTask>().single;
      expect(hoverTask.element.rect, preview.rect);
    });

    test('normalizes invalid scale factors to a stable fallback', () {
      final view = DrawStateView.fromState(
        DrawState(
          domain: DomainState(document: DocumentState()),
          application: const ApplicationState(view: ViewState()),
        ),
      );
      const invalidScales = <double>[0, -1, double.nan, double.infinity];

      for (final scale in invalidScales) {
        final plan = builder.build(view: view, scaleFactor: scale);
        expect(plan.scaleFactor, 1.0, reason: 'Expected fallback for $scale');
      }
    });
  });
}
