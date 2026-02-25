import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final selectionConfig = DrawConfig.defaultConfig.selection.copyWith(
    padding: DrawConfig.defaultConfig.selection.padding + 16,
  );

  test('single selected text prioritizes move area over resize handles', () {
    final stateView = DrawStateView.fromState(
      _selectedState(
        const ElementState(
          id: 'text-1',
          rect: DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 160),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: TextData(text: 'hello'),
        ),
      ),
    );

    const pointer = DrawPoint(x: 84, y: 84);
    final result = hitTest.test(
      stateView: stateView,
      position: pointer,
      config: selectionConfig,
      registry: registry,
    );

    expect(result.target, HitTestTarget.selectionPadding);
    expect(result.isHandleHit, isFalse);
    expect(result.elementId, 'text-1');
  });

  test(
    'text move-area hit resolves to StartMoveIntent, not StartResizeIntent',
    () {
      final stateView = DrawStateView.fromState(
        _selectedState(
          const ElementState(
            id: 'text-1',
            rect: DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 160),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: TextData(text: 'hello'),
          ),
        ),
      );

      final intent = editIntentDetector.detectIntent(
        stateView: stateView,
        position: const DrawPoint(x: 84, y: 84),
        isShiftPressed: false,
        config: selectionConfig,
        registry: registry,
      );

      expect(intent, isA<StartMoveIntent>());
    },
  );

  test('single selected text still allows resize when pointer is '
      'outside move area', () {
    final stateView = DrawStateView.fromState(
      _selectedState(
        const ElementState(
          id: 'text-1',
          rect: DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 160),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: TextData(text: 'hello'),
        ),
      ),
    );

    final result = hitTest.test(
      stateView: stateView,
      position: const DrawPoint(x: 78, y: 78),
      config: selectionConfig,
      registry: registry,
    );

    expect(result.isHandleHit, isTrue);
    expect(result.handleType, HandleType.topLeft);
  });

  test('non-text selection keeps resize-handle priority', () {
    final stateView = DrawStateView.fromState(
      _selectedState(
        const ElementState(
          id: 'rect-1',
          rect: DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 160),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ),
    );

    final result = hitTest.test(
      stateView: stateView,
      position: const DrawPoint(x: 84, y: 84),
      config: selectionConfig,
      registry: registry,
    );

    expect(result.isHandleHit, isTrue);
    expect(result.handleType, HandleType.topLeft);
  });
}

DrawState _selectedState(ElementState selectedElement) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: [selectedElement]),
    selection: SelectionState(selectedIds: {selectedElement.id}),
  ),
);
