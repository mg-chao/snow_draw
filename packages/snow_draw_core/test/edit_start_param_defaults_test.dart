import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';
import 'package:test/test.dart';

void main() {
  group('StartEdit parameter defaults', () {
    test(
      'resize uses DrawConfig.selection.padding when not provided',
      () async {
        final store = _createStore(selectionPadding: 14);
        addTearDown(store.dispose);

        await store.dispatch(
          const StartEdit(
            operationId: EditOperationIds.resize,
            position: DrawPoint(x: 100, y: 100),
            params: ResizeOperationParams(resizeMode: ResizeMode.bottomRight),
          ),
        );

        final interaction = store.state.application.interaction;
        expect(interaction, isA<EditingState>());
        final context = (interaction as EditingState).context;
        expect(context, isA<ResizeEditContext>());
        expect((context as ResizeEditContext).selectionPadding, 14);
      },
    );

    test('rotate falls back to shared ConfigDefaults snap angle', () async {
      final store = _createStore(selectionPadding: 6);
      addTearDown(store.dispose);

      await store.dispatch(
        const StartEdit(
          operationId: EditOperationIds.rotate,
          position: DrawPoint(x: 100, y: 0),
          params: RotateOperationParams(),
        ),
      );

      final interaction = store.state.application.interaction;
      expect(interaction, isA<EditingState>());
      final context = (interaction as EditingState).context;
      expect(context, isA<RotateEditContext>());
      expect(
        (context as RotateEditContext).rotationSnapAngle,
        ConfigDefaults.rotationSnapAngle,
      );
    });
  });
}

DefaultDrawStore _createStore({required double selectionPadding}) {
  final config = DrawConfig(
    selection: SelectionConfig(padding: selectionPadding),
  );
  final context = DrawContext.withDefaults(
    configManager: ConfigManager(config),
  );
  return DefaultDrawStore(
    context: context,
    initialState: DrawState(
      domain: DomainState(
        document: DocumentState(elements: [_selectionElement]),
        selection: const SelectionState(selectedIds: {'rect-1'}),
      ),
    ),
  );
}

const _selectionElement = ElementState(
  id: 'rect-1',
  rect: DrawRect(maxX: 100, maxY: 100),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);
