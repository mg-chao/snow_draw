import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  DrawContext createContext() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    return DrawContext.withDefaults(elementRegistry: registry);
  }

  test('auto backend falls back to legacy store when Rust init fails', () {
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

    final store = createDrawStore(
      context: context,
      initialState: nonEmptyState,
    );

    expect(store, isA<DefaultDrawStore>());
    (store as DefaultDrawStore).dispose();
  });

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

  test('legacy backend always creates DefaultDrawStore', () {
    final context = createContext();
    final store = createDrawStore(
      context: context,
      backend: DrawStoreBackend.legacyDart,
    );
    expect(store, isA<DefaultDrawStore>());
    (store as DefaultDrawStore).dispose();
  });
}
