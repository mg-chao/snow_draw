import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation.dart';
import 'package:snow_draw_core/draw/edit/edit_operation_registry_interface.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';

void main() {
  test('free-draw creation view skips preview element projection', () {
    final builder = DrawStateViewBuilder(
      editOperations: _EmptyEditOperationRegistry(),
    );
    const element = ElementState(
      id: 'creating-free-draw',
      rect: DrawRect(minX: 20, minY: 10, maxX: 20, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FreeDrawData(),
    );
    final base = DrawState();
    final creatingState = CreatingState(
      element: element,
      startPosition: const DrawPoint(x: 20, y: 10),
      currentRect: const DrawRect(minX: 20, minY: 10, maxX: 80, maxY: 40),
      creationMode: const FreeDrawCreationMode(revision: 12),
    );
    final state = base.copyWith(
      application: base.application.copyWith(interaction: creatingState),
    );

    final view = builder.build(state);

    expect(view.previewElementsById, isEmpty);
    expect(view.snapGuides, creatingState.snapGuides);
    expect(view.state.application.interaction, isA<CreatingState>());
  });
}

class _EmptyEditOperationRegistry implements EditOperationRegistry {
  @override
  Iterable<EditOperation> get allOperations => const <EditOperation>[];

  @override
  Iterable<EditOperationId> get allOperationIds => const <EditOperationId>[];

  @override
  EditOperation? getOperation(EditOperationId operationId) => null;
}
