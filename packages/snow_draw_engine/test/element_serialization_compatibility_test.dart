import 'package:snow_draw_engine/draw/elements/core/element_data.dart';
import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_engine/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/types/draw_color.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('built-in element serialization compatibility', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    const cases = <_SerializationCase>[
      _SerializationCase(
        name: 'rectangle',
        element: RectangleData(
          cornerRadius: 14,
          fillColor: DrawColor(0x11010203),
          color: DrawColor(0xFF0A0B0C),
          strokeWidth: 3.5,
          strokeStyle: StrokeStyle.dotted,
          fillStyle: FillStyle.crossLine,
        ),
        colorFields: {'fillColor': 0x11010203, 'color': 0xFF0A0B0C},
      ),
      _SerializationCase(
        name: 'line',
        element: LineData(
          points: [
            DrawPoint.zero,
            DrawPoint(x: 0.35, y: 0.65),
            DrawPoint(x: 1, y: 1),
          ],
          color: DrawColor(0xAA112233),
          fillColor: DrawColor(0x55112233),
          fillStyle: FillStyle.line,
          strokeWidth: 4,
          strokeStyle: StrokeStyle.dashed,
          startBinding: ArrowBinding(
            elementId: 'target-a',
            anchor: DrawPoint(x: 0.2, y: 0.3),
            mode: ArrowBindingMode.inside,
          ),
          endBinding: ArrowBinding(
            elementId: 'target-b',
            anchor: DrawPoint(x: 0.7, y: 0.8),
          ),
          fixedSegments: [
            ElbowFixedSegment(
              index: 1,
              start: DrawPoint(x: 0.2, y: 0.2),
              end: DrawPoint(x: 0.8, y: 0.2),
            ),
          ],
          startIsSpecial: true,
          endIsSpecial: false,
        ),
        colorFields: {'color': 0xAA112233, 'fillColor': 0x55112233},
      ),
      _SerializationCase(
        name: 'arrow',
        element: ArrowData(
          points: [
            DrawPoint(x: 0, y: 0.1),
            DrawPoint(x: 0.5, y: 0.5),
            DrawPoint(x: 1, y: 0.9),
          ],
          color: DrawColor(0xCC334455),
          strokeWidth: 2.5,
          strokeStyle: StrokeStyle.dotted,
          arrowType: ArrowType.elbow,
          startArrowhead: ArrowheadStyle.circle,
          endArrowhead: ArrowheadStyle.diamond,
          startBinding: ArrowBinding(
            elementId: 'target-c',
            anchor: DrawPoint(x: 0.1, y: 0.9),
          ),
          endBinding: ArrowBinding(
            elementId: 'target-d',
            anchor: DrawPoint(x: 0.9, y: 0.1),
            mode: ArrowBindingMode.inside,
          ),
          fixedSegments: [
            ElbowFixedSegment(
              index: 1,
              start: DrawPoint(x: 0.25, y: 0.5),
              end: DrawPoint(x: 0.75, y: 0.5),
            ),
          ],
          startIsSpecial: true,
          endIsSpecial: true,
        ),
        colorFields: {'color': 0xCC334455},
      ),
      _SerializationCase(
        name: 'free_draw',
        element: FreeDrawData(
          points: [
            DrawPoint.zero,
            DrawPoint(x: 0.4, y: 0.5, pressure: 0.6),
            DrawPoint(x: 1, y: 1, pressure: 0.9),
          ],
          color: DrawColor(0xFF556677),
          fillColor: DrawColor(0x33556677),
          fillStyle: FillStyle.crossLine,
          strokeWidth: 5,
          strokeStyle: StrokeStyle.dashed,
        ),
        colorFields: {'color': 0xFF556677, 'fillColor': 0x33556677},
      ),
      _SerializationCase(
        name: 'filter',
        element: FilterData(
          type: CanvasFilterType.gaussianBlur,
          strength: 0.73,
        ),
      ),
      _SerializationCase(
        name: 'highlight',
        element: HighlightData(
          shape: HighlightShape.ellipse,
          color: DrawColor(0x99AA5500),
          strokeColor: DrawColor(0xFF331100),
          strokeWidth: 2.25,
        ),
        colorFields: {'color': 0x99AA5500, 'strokeColor': 0xFF331100},
      ),
      _SerializationCase(
        name: 'text',
        element: TextData(
          text: 'backend split',
          color: DrawColor(0xFF123456),
          fontSize: 27,
          fontFamily: 'Noto Sans',
          horizontalAlign: TextHorizontalAlign.right,
          verticalAlign: TextVerticalAlign.bottom,
          fillColor: DrawColor(0x88112233),
          fillStyle: FillStyle.line,
          strokeColor: DrawColor(0xFF654321),
          strokeWidth: 1.75,
          cornerRadius: 8,
          autoResize: false,
        ),
        colorFields: {
          'color': 0xFF123456,
          'fillColor': 0x88112233,
          'strokeColor': 0xFF654321,
        },
      ),
      _SerializationCase(
        name: 'serial_number',
        element: SerialNumberData(
          number: 42,
          color: DrawColor(0xFF0F0F0F),
          fillColor: DrawColor(0x6600CCFF),
          fillStyle: FillStyle.crossLine,
          fontSize: 19,
          fontFamily: 'Noto Sans',
          strokeWidth: 2.2,
          strokeStyle: StrokeStyle.dotted,
          textElementId: 'text-42',
        ),
        colorFields: {'color': 0xFF0F0F0F, 'fillColor': 0x6600CCFF},
      ),
    ];

    for (final testCase in cases) {
      test('${testCase.name} roundtrip keeps JSON payload stable', () {
        final definition = registry.getDefinitionByValue(
          testCase.element.typeId.value,
        );
        expect(
          definition,
          isNotNull,
          reason: 'Missing definition for ${testCase.element.typeId.value}',
        );

        final encoded = testCase.element.toJson();
        for (final entry in testCase.colorFields.entries) {
          final encodedValue = encoded[entry.key];
          expect(
            encodedValue,
            isA<int>(),
            reason: '${testCase.name}.${entry.key} must serialize as ARGB int',
          );
          expect(
            encodedValue,
            equals(entry.value),
            reason: '${testCase.name}.${entry.key} changed unexpectedly',
          );
        }

        final decoded = definition!.fromJson(encoded);
        expect(
          decoded.toJson(),
          equals(encoded),
          reason: '${testCase.name} JSON roundtrip changed payload',
        );
      });
    }
  });
}

final class _SerializationCase {
  const _SerializationCase({
    required this.name,
    required this.element,
    this.colorFields = const {},
  });

  final String name;
  final ElementData element;
  final Map<String, int> colorFields;
}
