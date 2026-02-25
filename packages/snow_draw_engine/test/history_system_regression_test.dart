import 'package:snow_draw_engine/draw/actions/actions.dart';
import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/store/draw_store.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('History system regression', () {
    test('undo and redo keep global elements update behavior stable', () async {
      final store = _createStore(initialState: DrawState());
      addTearDown(store.dispose);

      await store.dispatch(
        const UpdateGlobalElements(
          highlightMask: HighlightMaskConfig(maskOpacity: 0.4),
          watermark: WatermarkConfig(text: 'INTERNAL', opacity: 0.2),
        ),
      );
      expect(
        store.state.domain.document.globalElements.highlightMask.maskOpacity,
        0.4,
      );
      expect(
        store.state.domain.document.globalElements.watermark.text,
        'INTERNAL',
      );

      await store.dispatch(const Undo());
      expect(
        store.state.domain.document.globalElements.highlightMask.maskOpacity,
        0.0,
      );
      expect(store.state.domain.document.globalElements.watermark.text, '');

      await store.dispatch(const Redo());
      expect(
        store.state.domain.document.globalElements.highlightMask.maskOpacity,
        0.4,
      );
      expect(
        store.state.domain.document.globalElements.watermark.text,
        'INTERNAL',
      );
    });

    test('undo and redo keep UpdateElementsStyle behavior stable', () async {
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'styled',
                  rect: DrawRect(maxX: 20, maxY: 20),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: FilterData(),
                ),
              ],
            ),
            selection: const SelectionState(selectedIds: {'styled'}),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        UpdateElementsStyle(elementIds: ['styled'], opacity: 0.4),
      );
      expect(
        store.state.domain.document.getElementById('styled')?.opacity,
        0.4,
      );

      await store.dispatch(const Undo());
      expect(
        store.state.domain.document.getElementById('styled')?.opacity,
        1.0,
      );

      await store.dispatch(const Redo());
      expect(
        store.state.domain.document.getElementById('styled')?.opacity,
        0.4,
      );
    });

    test(
      'coalesces rapid UpdateElementsStyle opacity history entries',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'styled',
                    rect: DrawRect(maxX: 20, maxY: 20),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: FilterData(),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'styled'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        const coalescing = HistoryCoalescing(
          key: 'style_toolbar:opacity',
          window: Duration(seconds: 1),
        );

        await store.dispatch(
          UpdateElementsStyle(
            elementIds: ['styled'],
            opacity: 0.7,
            historyCoalescing: coalescing,
          ),
        );
        await store.dispatch(
          UpdateElementsStyle(
            elementIds: ['styled'],
            opacity: 0.3,
            historyCoalescing: coalescing,
          ),
        );

        expect(
          store.state.domain.document.getElementById('styled')?.opacity,
          0.3,
        );
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());
        expect(
          store.state.domain.document.getElementById('styled')?.opacity,
          1.0,
        );
        expect(store.canUndo, isFalse);
        expect(store.canRedo, isTrue);

        await store.dispatch(const Redo());
        expect(
          store.state.domain.document.getElementById('styled')?.opacity,
          0.3,
        );
      },
    );

    test(
      'coalesces rapid UpdateGlobalElements watermark angle history entries',
      () async {
        final store = _createStore(initialState: DrawState());
        addTearDown(store.dispose);

        const coalescing = HistoryCoalescing(
          key: 'style_toolbar:watermarkAngle',
          window: Duration(seconds: 1),
        );

        await store.dispatch(
          const UpdateGlobalElements(
            watermark: WatermarkConfig(angle: 12),
            historyCoalescing: coalescing,
          ),
        );
        await store.dispatch(
          const UpdateGlobalElements(
            watermark: WatermarkConfig(angle: 36),
            historyCoalescing: coalescing,
          ),
        );

        expect(store.state.domain.document.globalElements.watermark.angle, 36);
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());
        expect(
          store.state.domain.document.globalElements.watermark.angle,
          ConfigDefaults.defaultWatermarkAngle,
        );
        expect(store.canUndo, isFalse);
        expect(store.canRedo, isTrue);

        await store.dispatch(const Redo());
        expect(store.state.domain.document.globalElements.watermark.angle, 36);
      },
    );

    test('coalesced watermark updates preserve unrelated elements', () async {
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'a',
                  rect: DrawRect(maxX: 20, maxY: 20),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: FilterData(),
                ),
                ElementState(
                  id: 'b',
                  rect: DrawRect(maxX: 30, maxY: 20),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 1,
                  data: FilterData(),
                ),
              ],
            ),
          ),
        ),
      );
      addTearDown(store.dispose);

      const coalescing = HistoryCoalescing(
        key: 'style_toolbar:watermarkOpacity',
        window: Duration(seconds: 1),
      );

      await store.dispatch(
        const UpdateGlobalElements(
          watermark: WatermarkConfig(opacity: 0.1),
          historyCoalescing: coalescing,
        ),
      );
      await store.dispatch(
        const UpdateGlobalElements(
          watermark: WatermarkConfig(opacity: 0.3),
          historyCoalescing: coalescing,
        ),
      );

      expect(
        store.state.domain.document.elements.map((element) => element.id),
        ['a', 'b'],
      );
      expect(store.state.domain.document.globalElements.watermark.opacity, 0.3);

      await store.dispatch(const Undo());
      expect(
        store.state.domain.document.elements.map((element) => element.id),
        ['a', 'b'],
      );
      expect(
        store.state.domain.document.globalElements.watermark.opacity,
        ConfigDefaults.defaultWatermarkOpacity,
      );
    });

    test(
      'coalesces rapid UpdateElementsStyle serial number history entries',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'serial',
                    rect: DrawRect(maxX: 24, maxY: 24),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: SerialNumberData(),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'serial'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        const coalescing = HistoryCoalescing(
          key: 'style_toolbar:serialNumber',
          window: Duration(seconds: 1),
        );

        await store.dispatch(
          UpdateElementsStyle(
            elementIds: ['serial'],
            serialNumber: 7,
            historyCoalescing: coalescing,
          ),
        );
        await store.dispatch(
          UpdateElementsStyle(
            elementIds: ['serial'],
            serialNumber: 12,
            historyCoalescing: coalescing,
          ),
        );

        final current = store.state.domain.document.getElementById('serial');
        expect(current, isNotNull);
        expect((current!.data as SerialNumberData).number, 12);
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());
        final restored = store.state.domain.document.getElementById('serial');
        expect(restored, isNotNull);
        expect((restored!.data as SerialNumberData).number, 1);
        expect(store.canUndo, isFalse);
        expect(store.canRedo, isTrue);

        await store.dispatch(const Redo());
        final redone = store.state.domain.document.getElementById('serial');
        expect(redone, isNotNull);
        expect((redone!.data as SerialNumberData).number, 12);
      },
    );

    test('coalesced style updates preserve unrelated elements', () async {
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'styled',
                  rect: DrawRect(maxX: 20, maxY: 20),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: FilterData(),
                ),
                ElementState(
                  id: 'other',
                  rect: DrawRect(maxX: 40, maxY: 20),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 1,
                  data: FilterData(),
                ),
              ],
            ),
          ),
        ),
      );
      addTearDown(store.dispose);

      const coalescing = HistoryCoalescing(
        key: 'style_toolbar:opacity',
        window: Duration(seconds: 1),
      );

      await store.dispatch(
        UpdateElementsStyle(
          elementIds: ['styled'],
          opacity: 0.7,
          historyCoalescing: coalescing,
        ),
      );
      await store.dispatch(
        UpdateElementsStyle(
          elementIds: ['styled'],
          opacity: 0.2,
          historyCoalescing: coalescing,
        ),
      );

      expect(
        store.state.domain.document.getElementById('styled')?.opacity,
        0.2,
      );
      expect(store.state.domain.document.getElementById('other')?.opacity, 1.0);

      await store.dispatch(const Undo());
      expect(
        store.state.domain.document.getElementById('styled')?.opacity,
        1.0,
      );
      expect(store.state.domain.document.getElementById('other')?.opacity, 1.0);
    });

    test(
      'coalesces rapid UpdateGlobalElements watermark text history entries',
      () async {
        final store = _createStore(initialState: DrawState());
        addTearDown(store.dispose);

        const coalescing = HistoryCoalescing(
          key: 'style_toolbar:watermarkText',
          window: Duration(seconds: 1),
        );

        await store.dispatch(
          const UpdateGlobalElements(
            watermark: WatermarkConfig(text: 'W'),
            historyCoalescing: coalescing,
          ),
        );
        await store.dispatch(
          const UpdateGlobalElements(
            watermark: WatermarkConfig(text: 'WATERMARK'),
            historyCoalescing: coalescing,
          ),
        );

        expect(
          store.state.domain.document.globalElements.watermark.text,
          'WATERMARK',
        );
        expect(store.canUndo, isTrue);

        await store.dispatch(const Undo());
        expect(
          store.state.domain.document.globalElements.watermark.text,
          ConfigDefaults.defaultWatermarkText,
        );
        expect(store.canUndo, isFalse);
        expect(store.canRedo, isTrue);

        await store.dispatch(const Redo());
        expect(
          store.state.domain.document.globalElements.watermark.text,
          'WATERMARK',
        );
      },
    );

    test('undo and redo keep ChangeElementsZIndex behavior stable', () async {
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const [
                ElementState(
                  id: 'a',
                  rect: DrawRect(maxX: 10, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 0,
                  data: FilterData(),
                ),
                ElementState(
                  id: 'b',
                  rect: DrawRect(maxX: 20, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 1,
                  data: FilterData(),
                ),
                ElementState(
                  id: 'c',
                  rect: DrawRect(maxX: 30, maxY: 10),
                  rotation: 0,
                  opacity: 1,
                  zIndex: 2,
                  data: FilterData(),
                ),
              ],
            ),
            selection: const SelectionState(selectedIds: {'a', 'b'}),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        ChangeElementsZIndex(
          elementIds: ['a', 'b'],
          operation: ZIndexOperation.bringToFront,
        ),
      );
      expect(
        store.state.domain.document.elements.map((element) => element.id),
        ['c', 'a', 'b'],
      );

      await store.dispatch(const Undo());
      expect(
        store.state.domain.document.elements.map((element) => element.id),
        ['a', 'b', 'c'],
      );

      await store.dispatch(const Redo());
      expect(
        store.state.domain.document.elements.map((element) => element.id),
        ['c', 'a', 'b'],
      );
    });

    test(
      'undo restores consistent zIndex values after ChangeElementZIndex',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'a',
                    rect: DrawRect(maxX: 10, maxY: 10),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: FilterData(),
                  ),
                  ElementState(
                    id: 'b',
                    rect: DrawRect(maxX: 20, maxY: 10),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 1,
                    data: FilterData(),
                  ),
                  ElementState(
                    id: 'c',
                    rect: DrawRect(maxX: 30, maxY: 10),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 2,
                    data: FilterData(),
                  ),
                ],
              ),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const ChangeElementZIndex(
            elementId: 'a',
            operation: ZIndexOperation.bringToFront,
          ),
        );
        await store.dispatch(const Undo());

        final elements = store.state.domain.document.elements;
        expect(elements.map((element) => element.id), ['a', 'b', 'c']);
        expect(elements.map((element) => element.zIndex), [0, 1, 2]);
      },
    );

    test(
      'undo restores serial bound text when deleting the serial element',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'serial',
                    rect: DrawRect(maxX: 50, maxY: 50),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: SerialNumberData(textElementId: 'text'),
                  ),
                  ElementState(
                    id: 'text',
                    rect: DrawRect(minY: 60, maxX: 50, maxY: 90),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 1,
                    data: TextData(text: '1'),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'serial'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(DeleteElements(elementIds: ['serial']));
        await store.dispatch(const Undo());

        final document = store.state.domain.document;
        final serial = document.getElementById('serial');
        final text = document.getElementById('text');

        expect(serial, isNotNull);
        expect(text, isNotNull);
        expect(serial!.data, isA<SerialNumberData>());
        expect((serial.data as SerialNumberData).textElementId, 'text');
      },
    );

    test(
      'undo restores serial binding when deleting the bound text element',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'serial',
                    rect: DrawRect(maxX: 50, maxY: 50),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: SerialNumberData(number: 2, textElementId: 'text'),
                  ),
                  ElementState(
                    id: 'text',
                    rect: DrawRect(minY: 60, maxX: 50, maxY: 90),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 1,
                    data: TextData(text: '2'),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'text'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(DeleteElements(elementIds: ['text']));
        await store.dispatch(const Undo());

        final document = store.state.domain.document;
        final serial = document.getElementById('serial');
        final text = document.getElementById('text');

        expect(serial, isNotNull);
        expect(text, isNotNull);
        expect(serial!.data, isA<SerialNumberData>());
        expect((serial.data as SerialNumberData).textElementId, 'text');
      },
    );

    test(
      'undo restores serial binding when deleting bound text in multi-delete',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'serial',
                    rect: DrawRect(maxX: 50, maxY: 50),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: SerialNumberData(number: 3, textElementId: 'text'),
                  ),
                  ElementState(
                    id: 'text',
                    rect: DrawRect(minY: 60, maxX: 50, maxY: 90),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 1,
                    data: TextData(text: '3'),
                  ),
                  ElementState(
                    id: 'other',
                    rect: DrawRect(minX: 80, maxX: 120, maxY: 40),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 2,
                    data: FilterData(),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'text', 'other'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(DeleteElements(elementIds: ['text', 'other']));
        await store.dispatch(const Undo());

        final document = store.state.domain.document;
        final serial = document.getElementById('serial');
        final text = document.getElementById('text');
        final other = document.getElementById('other');

        expect(serial, isNotNull);
        expect(text, isNotNull);
        expect(other, isNotNull);
        expect(serial!.data, isA<SerialNumberData>());
        expect((serial.data as SerialNumberData).textElementId, 'text');
      },
    );

    test(
      'undo restores arrow binding when deleting a bound target element',
      () async {
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(
                elements: const [
                  ElementState(
                    id: 'target',
                    rect: DrawRect(maxX: 50, maxY: 50),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 0,
                    data: FilterData(),
                  ),
                  ElementState(
                    id: 'arrow',
                    rect: DrawRect(minX: 60, maxX: 120, maxY: 40),
                    rotation: 0,
                    opacity: 1,
                    zIndex: 1,
                    data: ArrowData(
                      startBinding: ArrowBinding(
                        elementId: 'target',
                        anchor: DrawPoint(x: 0.5, y: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
              selection: const SelectionState(selectedIds: {'target'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(DeleteElements(elementIds: ['target']));

        final afterDeleteArrow = store.state.domain.document.getElementById(
          'arrow',
        );
        expect(afterDeleteArrow, isNotNull);
        expect(afterDeleteArrow!.data, isA<ArrowData>());
        expect((afterDeleteArrow.data as ArrowData).startBinding, isNull);

        await store.dispatch(const Undo());

        final restoredArrow = store.state.domain.document.getElementById(
          'arrow',
        );
        expect(restoredArrow, isNotNull);
        final restoredData = restoredArrow!.data as ArrowData;
        expect(restoredData.startBinding, isNotNull);
        expect(restoredData.startBinding!.elementId, 'target');
        expect(store.state.domain.document.getElementById('target'), isNotNull);
      },
    );
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}
