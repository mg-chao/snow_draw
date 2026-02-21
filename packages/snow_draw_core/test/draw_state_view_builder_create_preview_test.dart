import 'package:test/test.dart';
import 'package:snow_draw_core/draw/edit/edit_operations.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('free-draw creation view skips preview element projection', () {
    final creatingState = CreatingState(
      element: const ElementState(
        id: 'creating-free-draw',
        rect: DrawRect(minX: 20, minY: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(),
      ),
      startPosition: const DrawPoint(x: 20, y: 10),
      currentRect: const DrawRect(minX: 20, minY: 10, maxX: 80, maxY: 40),
      creationMode: const FreeDrawCreationMode(revision: 12),
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
