import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

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
            fillColor: DrawColor(0xFFCCDDEE),
            color: DrawColor(0xFF112233),
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
            strokeColor: DrawColor(0xFF123456),
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
            color: DrawColor(0xFF123456),
            strokeColor: DrawColor(0xFF102030),
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
            color: DrawColor(0xFF102030),
            fillColor: DrawColor(0xFFCCDDEE),
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

final DefaultElementRegistry _elementRegistry = (() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  return registry;
})();
