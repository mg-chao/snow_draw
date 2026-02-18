import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
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
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
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

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'rect-1'});
      expect(plan.staticHiddenElementIds, {'rect-1'});
    });

    test('optimizes arrow-point edits even without preview deltas', () {
      final arrow = _arrow(
        id: 'arrow-1',
        points: const [DrawPoint(x: 40, y: 40), DrawPoint(x: 180, y: 120)],
        zIndex: 0,
      );
      final background = _rectangle(
        id: 'rect-2',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 340, maxY: 120),
        zIndex: 1,
      );
      final state = _arrowPointEditingState(
        elements: [arrow, background],
        elementId: 'arrow-1',
        selectedIds: {'arrow-1'},
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: const {},
        effectiveSelection: EffectiveSelection(
          bounds: arrow.rect,
          center: arrow.rect.center,
          rotation: arrow.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'arrow-1'});
      expect(plan.staticHiddenElementIds, {'arrow-1'});
    });

    test('optimizes lightweight line point edits to a localized scene', () {
      final line = _line(
        id: 'line-1',
        points: const [DrawPoint(x: 40, y: 40), DrawPoint(x: 180, y: 120)],
        zIndex: 0,
      );
      final background = _rectangle(
        id: 'rect-2',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 340, maxY: 120),
        zIndex: 1,
      );
      final state = _linePointEditingState(
        elements: [line, background],
        elementId: 'line-1',
        selectedIds: {'line-1'},
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: const {},
        effectiveSelection: EffectiveSelection(
          bounds: line.rect,
          center: line.rect.center,
          rotation: line.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'line-1'});
      expect(plan.staticHiddenElementIds, {'line-1'});
    });

    test('optimizes free-draw move edits to a localized scene', () {
      final freeDraw = _freeDraw(
        id: 'free-1',
        points: const [DrawPoint(x: 40, y: 40), DrawPoint(x: 180, y: 120)],
        zIndex: 0,
      );
      final background = _rectangle(
        id: 'rect-2',
        rect: const DrawRect(minX: 220, minY: 20, maxX: 340, maxY: 120),
        zIndex: 1,
      );
      final state = _editingState(
        elements: [freeDraw, background],
        selectedIds: {'free-1'},
      );
      final preview = freeDraw.copyWith(
        rect: const DrawRect(minX: 56, minY: 52, maxX: 196, maxY: 132),
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: {'free-1': preview},
        effectiveSelection: EffectiveSelection(
          bounds: preview.rect,
          center: preview.rect.center,
          rotation: preview.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'free-1'});
      expect(plan.staticHiddenElementIds, {'free-1'});
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

        final plan = resolveDynamicSceneOptimizationPlan(view: view);

        expect(plan, isNull);
      },
    );

    test(
      'ignores transparent blend-sensitive elements above the edited element',
      () {
        final rectangle = _rectangle(
          id: 'rect-1',
          rect: const DrawRect(maxX: 120, maxY: 80),
          zIndex: 0,
        );
        final transparentHighlight = _highlight(
          id: 'hl-1',
          rect: const DrawRect(minX: 80, maxX: 180, maxY: 80),
          zIndex: 1,
          opacity: 0,
        );
        final state = _editingState(
          elements: [rectangle, transparentHighlight],
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

        final plan = resolveDynamicSceneOptimizationPlan(view: view);

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'rect-1'});
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

        final plan = resolveDynamicSceneOptimizationPlan(view: view);

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'serial-1', 'text-1'});
        expect(plan.staticHiddenElementIds, {'serial-1', 'text-1'});
      },
    );

    test(
      'keeps serial optimization active when preview map exceeds generic limit',
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
        final extras = List<ElementState>.generate(
          28,
          (index) => _rectangle(
            id: 'extra-$index',
            rect: DrawRect(
              minX: 20 + index * 14,
              minY: 140,
              maxX: 32 + index * 14,
              maxY: 152,
            ),
            zIndex: 2 + index,
          ),
        );
        final state = _editingState(
          elements: [text, serial, ...extras],
          selectedIds: {'serial-1'},
        );
        final serialPreview = serial.copyWith(
          rect: const DrawRect(minX: 40, minY: 40, maxX: 120, maxY: 120),
        );
        final previewElements = <String, ElementState>{
          'serial-1': serialPreview,
          for (final extra in extras)
            extra.id: extra.copyWith(
              rect: extra.rect.translate(const DrawPoint(x: 1, y: 0)),
            ),
        };
        final view = DrawStateView.withPreview(
          state: state,
          previewElementsById: previewElements,
          effectiveSelection: EffectiveSelection(
            bounds: serialPreview.rect,
            center: serialPreview.rect.center,
            rotation: serialPreview.rotation,
            hasSelection: true,
          ),
          snapGuides: const [],
        );

        final plan = resolveDynamicSceneOptimizationPlan(view: view);

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'serial-1', 'text-1'});
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

        final plan = resolveDynamicSceneOptimizationPlan(view: view);

        expect(plan, isNotNull);
        expect(plan!.optimizedElementIds, {'serial-1', 'text-1'});
        expect(plan.staticHiddenElementIds, {'serial-1', 'text-1'});
      },
    );

    test('optimizes existing text-edit previews to a localized scene', () {
      final text = _text(
        id: 'text-1',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 160, maxY: 100),
        zIndex: 0,
      );
      final background = _rectangle(
        id: 'rect-1',
        rect: const DrawRect(minX: 220, minY: 40, maxX: 340, maxY: 140),
        zIndex: 1,
      );
      final state = _textEditingState(
        elements: [text, background],
        elementId: 'text-1',
        selectedIds: {'text-1'},
      );
      final preview = text.copyWith(
        data: const TextData(text: 'edited'),
        rect: const DrawRect(minX: 20, minY: 20, maxX: 220, maxY: 100),
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: {'text-1': preview},
        effectiveSelection: EffectiveSelection(
          bounds: preview.rect,
          center: preview.rect.center,
          rotation: preview.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNotNull);
      expect(plan!.optimizedElementIds, {'text-1'});
      expect(plan.staticHiddenElementIds, {'text-1'});
    });

    test('skips text-edit optimization for new text drafts', () {
      final state = _textEditingState(
        elements: const [],
        elementId: 'text-new',
        selectedIds: const {},
        isNew: true,
      );
      const preview = ElementState(
        id: 'text-new',
        rect: DrawRect(minX: 10, minY: 10, maxX: 120, maxY: 80),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(text: 'draft'),
      );
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: const {'text-new': preview},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNull);
    });

    test('skips text-edit optimization for non-text persisted elements', () {
      final rectangle = _rectangle(
        id: 'rect-1',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 180, maxY: 120),
        zIndex: 0,
      );
      final state = _textEditingState(
        elements: [rectangle],
        elementId: 'rect-1',
        selectedIds: {'rect-1'},
      );
      final preview = rectangle.copyWith(data: const TextData(text: 'edited'));
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

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNull);
    });

    test('falls back when text-edit dynamic range contains highlight', () {
      final text = _text(
        id: 'text-1',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 160, maxY: 100),
        zIndex: 0,
      );
      final highlight = _highlight(
        id: 'hl-1',
        rect: const DrawRect(minX: 40, minY: 20, maxX: 220, maxY: 120),
        zIndex: 1,
      );
      final state = _textEditingState(
        elements: [text, highlight],
        elementId: 'text-1',
        selectedIds: {'text-1'},
      );
      final preview = text.copyWith(data: const TextData(text: 'edited'));
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: {'text-1': preview},
        effectiveSelection: EffectiveSelection(
          bounds: preview.rect,
          center: preview.rect.center,
          rotation: preview.rotation,
          hasSelection: true,
        ),
        snapGuides: const [],
      );

      final plan = resolveDynamicSceneOptimizationPlan(view: view);

      expect(plan, isNull);
    });
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

DrawState _textEditingState({
  required List<ElementState> elements,
  required String elementId,
  required Set<String> selectedIds,
  bool isNew = false,
}) {
  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(selectedIds: selectedIds),
    ),
    application: ApplicationState.initial(),
  );
  return base.copyWith(
    application: base.application.copyWith(
      interaction: TextEditingState(
        elementId: elementId,
        draftData: const TextData(text: 'draft'),
        rect: const DrawRect(minX: 20, minY: 20, maxX: 160, maxY: 100),
        isNew: isNew,
        opacity: 1,
        rotation: 0,
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
  double opacity = 1,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: opacity,
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

ElementState _arrow({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
}) {
  final minX = points
      .map((point) => point.x)
      .reduce((value, element) => value < element ? value : element);
  final maxX = points
      .map((point) => point.x)
      .reduce((value, element) => value > element ? value : element);
  final minY = points
      .map((point) => point.y)
      .reduce((value, element) => value < element ? value : element);
  final maxY = points
      .map((point) => point.y)
      .reduce((value, element) => value > element ? value : element);
  final rect = DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );

  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(points: normalizedPoints),
  );
}

ElementState _line({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
}) {
  final minX = points
      .map((point) => point.x)
      .reduce((value, element) => value < element ? value : element);
  final maxX = points
      .map((point) => point.x)
      .reduce((value, element) => value > element ? value : element);
  final minY = points
      .map((point) => point.y)
      .reduce((value, element) => value < element ? value : element);
  final maxY = points
      .map((point) => point.y)
      .reduce((value, element) => value > element ? value : element);
  final rect = DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );

  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: LineData(points: normalizedPoints),
  );
}

ElementState _freeDraw({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
}) {
  final minX = points
      .map((point) => point.x)
      .reduce((value, element) => value < element ? value : element);
  final maxX = points
      .map((point) => point.x)
      .reduce((value, element) => value > element ? value : element);
  final minY = points
      .map((point) => point.y)
      .reduce((value, element) => value < element ? value : element);
  final maxY = points
      .map((point) => point.y)
      .reduce((value, element) => value > element ? value : element);
  final rect = DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );

  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: FreeDrawData(points: normalizedPoints),
  );
}

DrawState _arrowPointEditingState({
  required List<ElementState> elements,
  required String elementId,
  required Set<String> selectedIds,
}) {
  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(selectedIds: selectedIds),
    ),
    application: ApplicationState.initial(),
  );
  final element = base.domain.document.getElementById(elementId)!;
  final data = element.data as ArrowData;
  final initialPoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ).map((point) => DrawPoint(x: point.dx, y: point.dy)).toList(growable: false);

  final context = ArrowPointEditContext(
    startPosition: initialPoints.first,
    startBounds: element.rect,
    selectedIdsAtStart: selectedIds,
    selectionVersion: base.domain.selection.selectionVersion,
    elementsVersion: base.domain.document.elementsVersion,
    elementId: element.id,
    elementRect: element.rect,
    rotation: element.rotation,
    initialPoints: initialPoints,
    initialFixedSegments: const [],
    arrowType: data.arrowType,
    pointKind: ArrowPointKind.turning,
    pointIndex: 0,
    dragOffset: DrawPoint.zero,
    baseElement: element,
    elementSpace: null,
    releaseFixedSegment: false,
    deletePointOnStart: false,
    bindingTargetCache: ArrowBindingTargetCache(),
    startArrowhead: ArrowheadStyle.none,
    endArrowhead: ArrowheadStyle.standard,
    initialStartBinding: data.startBinding,
    initialEndBinding: data.endBinding,
    hasBindableTargets: base.domain.document.hasArrowBindableElements,
  );

  return base.copyWith(
    application: base.application.copyWith(
      interaction: EditingState(
        operationId: EditOperationIds.arrowPoint,
        sessionId: 'arrow-edit-session',
        context: context,
        currentTransform: ArrowPointTransform(
          currentPosition: initialPoints.first,
          points: initialPoints,
          startBinding: data.startBinding,
          endBinding: data.endBinding,
        ),
      ),
    ),
  );
}

DrawState _linePointEditingState({
  required List<ElementState> elements,
  required String elementId,
  required Set<String> selectedIds,
}) {
  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: SelectionState(selectedIds: selectedIds),
    ),
    application: ApplicationState.initial(),
  );
  final element = base.domain.document.getElementById(elementId)!;
  final data = element.data as LineData;
  final initialPoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ).map((point) => DrawPoint(x: point.dx, y: point.dy)).toList(growable: false);

  final context = ArrowPointEditContext(
    startPosition: initialPoints.first,
    startBounds: element.rect,
    selectedIdsAtStart: selectedIds,
    selectionVersion: base.domain.selection.selectionVersion,
    elementsVersion: base.domain.document.elementsVersion,
    elementId: element.id,
    elementRect: element.rect,
    rotation: element.rotation,
    initialPoints: initialPoints,
    initialFixedSegments: const [],
    arrowType: data.arrowType,
    pointKind: ArrowPointKind.turning,
    pointIndex: 0,
    dragOffset: DrawPoint.zero,
    baseElement: element,
    elementSpace: null,
    releaseFixedSegment: false,
    deletePointOnStart: false,
    bindingTargetCache: ArrowBindingTargetCache(),
    startArrowhead: ArrowheadStyle.none,
    endArrowhead: ArrowheadStyle.none,
    initialStartBinding: data.startBinding,
    initialEndBinding: data.endBinding,
    hasBindableTargets: base.domain.document.hasArrowBindableElements,
    isLineElement: true,
  );

  return base.copyWith(
    application: base.application.copyWith(
      interaction: EditingState(
        operationId: EditOperationIds.arrowPoint,
        sessionId: 'line-edit-session',
        context: context,
        currentTransform: ArrowPointTransform(
          currentPosition: initialPoints.first,
          points: initialPoints,
          startBinding: data.startBinding,
          endBinding: data.endBinding,
        ),
      ),
    ),
  );
}

class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required super.startBounds,
  }) : super(startPosition: DrawPoint.zero);
}
