import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_scene_optimization.dart';

void main() {
  group('resolveDynamicSceneOptimizationPlan', () {
    test('optimizes single-rectangle edit previews', () {
      final rectangle = _rectangle(
        id: 'rect-1',
        rect: const DrawRect(maxX: 120, maxY: 80),
        zIndex: 0,
      );
      final background = _rectangle(
        id: 'rect-2',
        rect: const DrawRect(minX: 200, maxX: 320, maxY: 80),
        zIndex: 1,
      );
      final state = _editingState(
        elements: [rectangle, background],
        selectedIds: {'rect-1'},
      );
      final preview = rectangle.copyWith(
        rect: const DrawRect(minX: 32, minY: 24, maxX: 152, maxY: 104),
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: {'rect-1': preview},
        effectiveSelection: EffectiveSelection(
          bounds: preview.rect,
          center: preview.rect.center,
          rotation: preview.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(
        view: view,
        activeToolTypeId: RectangleData.typeIdToken,
      );

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'rect-1'});
      expect(plan.staticHiddenElementIds, {'rect-1'});
    });

    test(
      'skips localized optimization when blend-sensitive elements overlap',
      () {
        final rectangle = _rectangle(
          id: 'rect-1',
          rect: const DrawRect(maxX: 120, maxY: 80),
          zIndex: 0,
        );
        final highlight = _highlight(
          id: 'hl-1',
          rect: const DrawRect(minX: 80, maxX: 180, maxY: 80),
          zIndex: 1,
        );
        final state = _editingState(
          elements: [rectangle, highlight],
          selectedIds: {'rect-1'},
        );
        final preview = rectangle.copyWith(
          rect: const DrawRect(minX: 24, minY: 16, maxX: 144, maxY: 96),
        );
        final view = DrawStateView.withPreview(
          state: state,
          previewElementsById: {'rect-1': preview},
          effectiveSelection: EffectiveSelection(
            bounds: preview.rect,
            center: preview.rect.center,
            rotation: preview.rotation,
            hasSelection: true,
          ),
          snapGuides: const [],
        );

        final plan = resolveDynamicSceneOptimizationPlan(
          view: view,
          activeToolTypeId: RectangleData.typeIdToken,
        );

        expect(plan, isNull);
      },
    );

    test(
      'keeps serial-number companion text in localized optimization set',
      () {
        final text = _text(
          id: 'text-1',
          rect: const DrawRect(minX: 140, minY: 20, maxX: 260, maxY: 80),
          zIndex: 0,
        );
        final serial = _serial(
          id: 'serial-1',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 100, maxY: 100),
          zIndex: 1,
          textElementId: 'text-1',
        );
        final state = _editingState(
          elements: [text, serial],
          selectedIds: {'serial-1'},
        );
        final preview = serial.copyWith(
          rect: const DrawRect(minX: 40, minY: 40, maxX: 120, maxY: 120),
        );
        final view = DrawStateView.withPreview(
          state: state,
          previewElementsById: {'serial-1': preview},
          effectiveSelection: EffectiveSelection(
            bounds: preview.rect,
            center: preview.rect.center,
            rotation: preview.rotation,
            hasSelection: true,
          ),
          snapGuides: const [],
        );

        final plan = resolveDynamicSceneOptimizationPlan(
          view: view,
          activeToolTypeId: SerialNumberData.typeIdToken,
        );

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'serial-1', 'text-1'});
        expect(plan.staticHiddenElementIds, {'serial-1', 'text-1'});
      },
    );

    test(
      'keeps serial-number companion text during generic single-edit fallback',
      () {
        final text = _text(
          id: 'text-1',
          rect: const DrawRect(minX: 140, minY: 20, maxX: 260, maxY: 80),
          zIndex: 0,
        );
        final serial = _serial(
          id: 'serial-1',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 100, maxY: 100),
          zIndex: 1,
          textElementId: 'text-1',
        );
        final state = _editingState(
          elements: [text, serial],
          selectedIds: {'serial-1'},
        );
        final preview = serial.copyWith(
          rect: const DrawRect(minX: 40, minY: 40, maxX: 120, maxY: 120),
        );
        final view = DrawStateView.withPreview(
          state: state,
          previewElementsById: {'serial-1': preview},
          effectiveSelection: EffectiveSelection(
            bounds: preview.rect,
            center: preview.rect.center,
            rotation: preview.rotation,
            hasSelection: true,
          ),
          snapGuides: const [],
        );

        final plan = resolveDynamicSceneOptimizationPlan(
          view: view,
          activeToolTypeId: RectangleData.typeIdToken,
        );

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'serial-1', 'text-1'});
        expect(plan.staticHiddenElementIds, {'serial-1', 'text-1'});
      },
    );
  });
}

DrawState _editingState({
  required List<ElementState> elements,
  required Set<String> selectedIds,
}) {
  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(selectedIds: selectedIds),
    ),
    application: ApplicationState.initial(),
  );
  final context = _TestEditContext(
    selectedIdsAtStart: selectedIds,
    elementsVersion: base.domain.document.elementsVersion,
    selectionVersion: base.domain.selection.selectionVersion,
    startBounds: elements
        .firstWhere((element) => selectedIds.contains(element.id))
        .rect,
  );
  return base.copyWith(
    application: base.application.copyWith(
      interaction: EditingState(
        operationId: 'test-edit-op',
        sessionId: 'edit-session-1',
        context: context,
        currentTransform: MoveTransform.zero,
      ),
    ),
  );
}

ElementState _rectangle({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _highlight({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const HighlightData(),
);

ElementState _text({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const TextData(text: 'serial text'),
);

ElementState _serial({
  required String id,
  required DrawRect rect,
  required int zIndex,
  required String textElementId,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: SerialNumberData(textElementId: textElementId),
);

class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required super.startBounds,
  }) : super(startPosition: DrawPoint.zero);
}
