import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  group('resolveNextSteppedValue', () {
    test('ignores near-equal higher steps when increasing', () {
      final next = resolveNextSteppedValue(10, const [
        8,
        10.005,
        11.5,
      ], decrease: false);

      expect(next, 11.5);
    });

    test('ignores near-equal lower steps when decreasing', () {
      final next = resolveNextSteppedValue(10, const [
        8.5,
        9.995,
        12,
      ], decrease: true);

      expect(next, 8.5);
    });

    test('clamps to list edges when no farther step exists', () {
      final high = resolveNextSteppedValue(12, const [
        2,
        4,
        6,
      ], decrease: false);
      final low = resolveNextSteppedValue(2, const [2, 4, 6], decrease: true);

      expect(high, 6);
      expect(low, 2);
    });
  });

  group('selected style averages', () {
    test('aggregates per-type stroke widths and text font sizes', () {
      final state = _buildState(
        selectedIds: const {'rect', 'arrow', 'line', 'draw', 'text', 'serial'},
        elements: const [
          ElementState(
            id: 'rect',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: RectangleData(strokeWidth: 3),
          ),
          ElementState(
            id: 'arrow',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: ArrowData(strokeWidth: 4),
          ),
          ElementState(
            id: 'line',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: LineData(strokeWidth: 6),
          ),
          ElementState(
            id: 'draw',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: FreeDrawData(strokeWidth: 8),
          ),
          ElementState(
            id: 'text',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: TextData(text: 'A', fontSize: 10),
          ),
          ElementState(
            id: 'serial',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: SerialNumberData(number: 7, fontSize: 12),
          ),
        ],
      );

      expect(resolveAverageSelectedRectangleStrokeWidth(state), 3);
      expect(resolveAverageSelectedArrowStrokeWidth(state), 4);
      expect(resolveAverageSelectedLineStrokeWidth(state), 6);
      expect(resolveAverageSelectedFreeDrawStrokeWidth(state), 8);
      expect(resolveAverageSelectedFontSize(state), 11);
    });

    test('returns null when selected set has no matching element type', () {
      final state = _buildState(
        selectedIds: const {'text'},
        elements: const [
          ElementState(
            id: 'text',
            rect: DrawRect(maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: TextData(text: 'A', fontSize: 16),
          ),
        ],
      );

      expect(resolveAverageSelectedArrowStrokeWidth(state), isNull);
      expect(resolveAverageSelectedRectangleStrokeWidth(state), isNull);
      expect(resolveAverageSelectedLineStrokeWidth(state), isNull);
      expect(resolveAverageSelectedFreeDrawStrokeWidth(state), isNull);
      expect(resolveAverageSelectedFontSize(state), 16);
    });
  });
}

DrawState _buildState({
  required Set<String> selectedIds,
  required List<ElementState> elements,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);
