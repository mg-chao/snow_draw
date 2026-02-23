import 'package:test/test.dart';
import 'package:snow_draw_core/draw/edit/edit_operations.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/snap_guides.dart';

void main() {
  test('creating rectangle state view avoids preview element duplication', () {
    const guides = [
      SnapGuide(
        kind: SnapGuideKind.point,
        axis: SnapGuideAxis.vertical,
        start: DrawPoint(x: 20, y: 0),
        end: DrawPoint(x: 20, y: 60),
        markers: [DrawPoint(x: 20, y: 30)],
      ),
    ];
    final view =
        DrawStateViewBuilder(
          editOperations: DefaultEditOperationRegistry.empty(),
        ).build(
          DrawState(
            application: ApplicationState.initial().copyWith(
              interaction: CreatingState(
                element: const ElementState(
                  id: 'creating-rectangle',
                  rect: DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: RectangleData(),
                ),
                startPosition: const DrawPoint(x: 10, y: 10),
                currentRect: const DrawRect(
                  minX: 10,
                  minY: 10,
                  maxX: 120,
                  maxY: 80,
                ),
                snapGuides: guides,
              ),
            ),
          ),
        );

    expect(view.previewElementsById, isEmpty);
    expect(view.snapGuides, guides);
    expect(view.effectiveSelection, same(EffectiveSelection.none));
  });
}
