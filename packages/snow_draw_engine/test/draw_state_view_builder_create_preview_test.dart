import 'package:snow_draw_engine/draw/edit/edit_operations.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_engine/draw/models/application_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  test('free-draw creation view skips preview element projection', () {
    const creatingState = CreatingState(
      element: ElementState(
        id: 'creating-free-draw',
        rect: DrawRect(minX: 20, minY: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(),
      ),
      startPosition: DrawPoint(x: 20, y: 10),
      currentRect: DrawRect(minX: 20, minY: 10, maxX: 80, maxY: 40),
      creationMode: FreeDrawCreationMode(revision: 12),
    );
    final view =
        DrawStateViewBuilder(
          editOperations: DefaultEditOperationRegistry.empty(),
        ).build(
          DrawState(
            application: ApplicationState.initial().copyWith(
              interaction: creatingState,
            ),
          ),
        );

    expect(view.previewElementsById, isEmpty);
    expect(view.snapGuides, creatingState.snapGuides);
    expect(view.state.application.interaction, isA<CreatingState>());
  });
}
