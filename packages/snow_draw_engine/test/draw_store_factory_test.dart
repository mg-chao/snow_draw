import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  DrawContext createContext() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    return DrawContext.withDefaults(elementRegistry: registry);
  }

  test('rust backend propagates initialization error', () {
    final context = createContext();
    final nonEmptyState = DrawState(
      domain: DomainState(
        document: DocumentState(
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
          ],
        ),
      ),
    );

    expect(
      () => createDrawStore(
        context: context,
        initialState: nonEmptyState,
        backend: DrawStoreBackend.rust,
      ),
      throwsA(
        anyOf(
          isA<UnsupportedError>(),
          isA<ArgumentError>(),
          isA<RustCanvasEngineException>(),
        ),
      ),
    );
  });
}
