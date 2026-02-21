import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/serial_number_connection_painter.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/serial_number_connector_cache.dart';

void main() {
  setUp(SerialNumberConnectorCache.instance.invalidate);

  test('reuses unaffected cached connectors during preview updates', () {
    const textA = ElementState(
      id: 'text-a',
      rect: DrawRect(minX: 120, minY: 80, maxX: 200, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const serialA = ElementState(
      id: 'serial-a',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text-a'),
    );
    const textB = ElementState(
      id: 'text-b',
      rect: DrawRect(minX: 320, minY: 180, maxX: 420, maxY: 220),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: TextData(text: 'B'),
    );
    const serialB = ElementState(
      id: 'serial-b',
      rect: DrawRect(minX: 240, minY: 190, maxX: 272, maxY: 222),
      rotation: 0,
      opacity: 1,
      zIndex: 3,
      data: SerialNumberData(textElementId: 'text-b'),
    );

    final state = _stateWithElements([textA, serialA, textB, serialB]);

    final stable = resolveSerialNumberConnectorMap(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: const {},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );
    final unaffectedBefore = stable['text-b']!.single;
    final affectedBefore = stable['text-a']!.single;

    final movedSerialA = serialA.copyWith(
      rect: const DrawRect(minX: 60, minY: 110, maxX: 92, maxY: 142),
    );
    final preview = resolveSerialNumberConnectorMap(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {movedSerialA.id: movedSerialA},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );
    final unaffectedAfter = preview['text-b']!.single;
    final affectedAfter = preview['text-a']!.single;

    expect(identical(unaffectedAfter, unaffectedBefore), isTrue);
    expect(identical(affectedAfter, affectedBefore), isFalse);
  });

  test('marks only affected text connectors as dynamic', () {
    const textA = ElementState(
      id: 'text-a',
      rect: DrawRect(minX: 120, minY: 80, maxX: 200, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const serialA = ElementState(
      id: 'serial-a',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text-a'),
    );
    const textB = ElementState(
      id: 'text-b',
      rect: DrawRect(minX: 320, minY: 180, maxX: 420, maxY: 220),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: TextData(text: 'B'),
    );
    const serialB = ElementState(
      id: 'serial-b',
      rect: DrawRect(minX: 240, minY: 190, maxX: 272, maxY: 222),
      rotation: 0,
      opacity: 1,
      zIndex: 3,
      data: SerialNumberData(textElementId: 'text-b'),
    );

    final state = _stateWithElements([textA, serialA, textB, serialB]);
    final view = DrawStateView.withPreview(
      state: state,
      previewElementsById: const {},
      effectiveSelection: EffectiveSelection.none,
      snapGuides: const [],
    );

    // Warm stable connector cache first.
    resolveSerialNumberConnectorSnapshot(view);

    final movedSerialA = serialA.copyWith(
      rect: const DrawRect(minX: 60, minY: 110, maxX: 92, maxY: 142),
    );
    final snapshot = resolveSerialNumberConnectorSnapshot(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {movedSerialA.id: movedSerialA},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );

    expect(snapshot.dynamicTextElementIds, {'text-a'});
    expect(snapshot.connectorsByTextId.keys, {'text-a', 'text-b'});
  });

  test(
    'ignores value-equal preview elements for dynamic connector tracking',
    () {
      const text = ElementState(
        id: 'text',
        rect: DrawRect(minX: 120, minY: 80, maxX: 200, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: TextData(text: 'A'),
      );
      const serial = ElementState(
        id: 'serial',
        rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: SerialNumberData(textElementId: 'text'),
      );

      final state = _stateWithElements([text, serial]);
      final unchangedPreview = serial.copyWith();
      final snapshot = resolveSerialNumberConnectorSnapshot(
        DrawStateView.withPreview(
          state: state,
          previewElementsById: {unchangedPreview.id: unchangedPreview},
          effectiveSelection: EffectiveSelection.none,
          snapGuides: const [],
        ),
      );

      expect(snapshot.dynamicTextElementIds, isEmpty);
      expect(snapshot.connectorsByTextId.keys, {'text'});
    },
  );

  test('limits connector resolution to visible text ids', () {
    const textA = ElementState(
      id: 'text-a',
      rect: DrawRect(minX: 120, minY: 80, maxX: 200, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const serialA = ElementState(
      id: 'serial-a',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text-a'),
    );
    const textB = ElementState(
      id: 'text-b',
      rect: DrawRect(minX: 320, minY: 180, maxX: 420, maxY: 220),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: TextData(text: 'B'),
    );
    const serialB = ElementState(
      id: 'serial-b',
      rect: DrawRect(minX: 240, minY: 190, maxX: 272, maxY: 222),
      rotation: 0,
      opacity: 1,
      zIndex: 3,
      data: SerialNumberData(textElementId: 'text-b'),
    );

    final state = _stateWithElements([textA, serialA, textB, serialB]);
    final view = DrawStateView.withPreview(
      state: state,
      previewElementsById: const {},
      effectiveSelection: EffectiveSelection.none,
      snapGuides: const [],
    );

    final connectors = resolveSerialNumberConnectorMap(
      view,
      visibleTextElementIds: {'text-a'},
    );

    expect(connectors.keys, {'text-a'});
    expect(connectors['text-a'], isNotEmpty);
    expect(connectors['text-b'], isNull);
  });

  test('allows explicitly requested preview-hidden text ids', () {
    const text = ElementState(
      id: 'text',
      rect: DrawRect(minX: 120, minY: 80, maxX: 220, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const serial = ElementState(
      id: 'serial',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text'),
    );

    final state = _stateWithElements([text, serial]);
    final hiddenText = text.copyWith(opacity: 0);
    final view = DrawStateView.withPreview(
      state: state,
      previewElementsById: {hiddenText.id: hiddenText},
      effectiveSelection: EffectiveSelection.none,
      snapGuides: const [],
    );

    final explicitConnectors = resolveSerialNumberConnectorMap(
      view,
      visibleTextElementIds: {'text'},
    );
    final inferredConnectors = resolveSerialNumberConnectorMap(view);

    expect(explicitConnectors['text'], isNotNull);
    expect(explicitConnectors['text']!.length, 1);
    expect(inferredConnectors, isEmpty);
  });

  test('uses preview serial bindings when text target changes', () {
    const textA = ElementState(
      id: 'text-a',
      rect: DrawRect(minX: 120, minY: 80, maxX: 220, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const textB = ElementState(
      id: 'text-b',
      rect: DrawRect(minX: 320, minY: 80, maxX: 420, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: TextData(text: 'B'),
    );
    const serial = ElementState(
      id: 'serial',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: SerialNumberData(textElementId: 'text-a'),
    );

    final state = _stateWithElements([textA, textB, serial]);

    final reboundSerial = serial.copyWith(
      data: const SerialNumberData(textElementId: 'text-b'),
    );
    final connectors = resolveSerialNumberConnectorMap(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {reboundSerial.id: reboundSerial},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );

    expect(connectors['text-a'], isNull);
    expect(connectors['text-b'], isNotNull);
    expect(connectors['text-b']!.length, 1);
  });

  test('drops connector when preview clears the text target', () {
    const text = ElementState(
      id: 'text',
      rect: DrawRect(minX: 120, minY: 80, maxX: 220, maxY: 120),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'A'),
    );
    const serial = ElementState(
      id: 'serial',
      rect: DrawRect(minX: 40, minY: 90, maxX: 72, maxY: 122),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text'),
    );

    final state = _stateWithElements([text, serial]);

    final unboundSerial = serial.copyWith(
      data: (serial.data as SerialNumberData).copyWith(textElementId: null),
    );
    final connectors = resolveSerialNumberConnectorMap(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {unboundSerial.id: unboundSerial},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );

    expect(connectors, isEmpty);

    final snapshot = resolveSerialNumberConnectorSnapshot(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {unboundSerial.id: unboundSerial},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );
    expect(snapshot.dynamicTextElementIds, {'text'});
  });

  test('includes preview-only serial bindings', () {
    const text = ElementState(
      id: 'text',
      rect: DrawRect(minX: 160, minY: 140, maxX: 240, maxY: 180),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'Preview Target'),
    );

    final state = _stateWithElements([text]);

    const previewSerial = ElementState(
      id: 'preview-serial',
      rect: DrawRect(minX: 60, minY: 150, maxX: 92, maxY: 182),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: SerialNumberData(textElementId: 'text'),
    );

    final connectors = resolveSerialNumberConnectorMap(
      DrawStateView.withPreview(
        state: state,
        previewElementsById: {previewSerial.id: previewSerial},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      ),
    );

    expect(connectors['text'], isNotNull);
    expect(connectors['text']!.length, 1);
  });
}

DrawState _stateWithElements(List<ElementState> elements) {
  final initial = DrawState.initial();
  return initial.copyWith(
    domain: DomainState(
      document: DocumentState(elements: elements),
      selection: initial.domain.selection,
    ),
  );
}
