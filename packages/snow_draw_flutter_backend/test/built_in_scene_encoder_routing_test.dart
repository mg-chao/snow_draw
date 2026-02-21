import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_definition.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_definition.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_definition.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_definition.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_definition.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_definition.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_definition.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_definition.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_flutter_backend/render/element_renderer.dart';

void main() {
  test('renders rectangle scene with dotted stroke and hatch fill', () {
    expect(
      () => _render(
        const ElementState(
          id: 'rect',
          rect: DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 80),
          rotation: 0.2,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(
            fillColor: ui.Color(0xFFCCDDEE),
            color: ui.Color(0xFF112233),
            strokeStyle: StrokeStyle.dotted,
            fillStyle: FillStyle.crossLine,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders line scene with dotted stroke and hatch fill', () {
    expect(
      () => _render(
        const ElementState(
          id: 'line',
          rect: DrawRect(minX: 10, minY: 10, maxX: 210, maxY: 120),
          rotation: 0.3,
          opacity: 1,
          zIndex: 0,
          data: LineData(
            points: <DrawPoint>[
              DrawPoint(x: 0, y: 0.1),
              DrawPoint(x: 0.5, y: 0.9),
              DrawPoint(x: 1, y: 0.2),
            ],
            strokeStyle: StrokeStyle.dotted,
            fillStyle: FillStyle.line,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders arrow scene for curved dotted arrows', () {
    expect(
      () => _render(
        const ElementState(
          id: 'arrow',
          rect: DrawRect(minX: 10, minY: 10, maxX: 210, maxY: 120),
          rotation: 0.1,
          opacity: 1,
          zIndex: 0,
          data: ArrowData(
            arrowType: ArrowType.curved,
            strokeStyle: StrokeStyle.dotted,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders free-draw scene with dotted stroke and hatch fill', () {
    expect(
      () => _render(
        const ElementState(
          id: 'free',
          rect: DrawRect(minX: 10, minY: 10, maxX: 160, maxY: 90),
          rotation: 0.25,
          opacity: 1,
          zIndex: 0,
          data: FreeDrawData(
            points: <DrawPoint>[
              DrawPoint.zero,
              DrawPoint(x: 0.2, y: 0.8),
              DrawPoint(x: 0.4, y: 0.2),
              DrawPoint(x: 0.8, y: 0.9),
              DrawPoint(x: 1, y: 0.3),
            ],
            strokeStyle: StrokeStyle.dotted,
            fillStyle: FillStyle.crossLine,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders highlight scene', () {
    expect(
      () => _render(
        const ElementState(
          id: 'highlight',
          rect: DrawRect(minX: 10, minY: 10, maxX: 180, maxY: 120),
          rotation: 0.15,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(
            shape: HighlightShape.ellipse,
            strokeColor: ui.Color(0xFF123456),
            strokeWidth: 2,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders filter scene without throwing', () {
    expect(
      () => _render(
        const ElementState(
          id: 'filter',
          rect: DrawRect(minX: 10, minY: 10, maxX: 180, maxY: 120),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: FilterData(),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders text scene with stroke and hatch fill', () {
    expect(
      () => _render(
        const ElementState(
          id: 'text',
          rect: DrawRect(minX: 10, minY: 10, maxX: 220, maxY: 120),
          rotation: 0.05,
          opacity: 1,
          zIndex: 0,
          data: TextData(
            text: 'Scene',
            color: ui.Color(0xFF123456),
            strokeColor: ui.Color(0xFF102030),
            strokeWidth: 1.5,
            fillStyle: FillStyle.line,
          ),
        ),
      ),
      returnsNormally,
    );
  });

  test('renders serial-number scene with dotted stroke and hatch fill', () {
    expect(
      () => _render(
        const ElementState(
          id: 'serial',
          rect: DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
          rotation: 0.1,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(
            number: 8,
            color: ui.Color(0xFF102030),
            fillColor: ui.Color(0xFFCCDDEE),
            strokeStyle: StrokeStyle.dotted,
            fillStyle: FillStyle.crossLine,
          ),
        ),
      ),
      returnsNormally,
    );
  });
}

void _render(ElementState element) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  elementRenderer.renderElement(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
    elementRegistry: _elementRegistry,
  );

  recorder.endRecording().dispose();
}

final _elementRegistry = DefaultElementRegistry()
  ..register<RectangleData>(rectangleDefinition)
  ..register<LineData>(lineDefinition)
  ..register<ArrowData>(arrowDefinition)
  ..register<FreeDrawData>(freeDrawDefinition)
  ..register<HighlightData>(highlightDefinition)
  ..register<FilterData>(filterDefinition)
  ..register<TextData>(textDefinition)
  ..register<SerialNumberData>(serialNumberDefinition);
