import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/render/tasks/flutter_render_task_executor.dart';

void main() {
  test(
    'executes all built-in element task families without scene encoders',
    () {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      final tasks = <RenderTask>[
        RectangleRenderTask(
          element: _element(
            id: 'rect',
            rect: const DrawRect(maxX: 120, maxY: 80),
            data: const RectangleData(
              color: DrawColor(0xFF1576FE),
              fillColor: DrawColor(0x221576FE),
            ),
          ),
          data: const RectangleData(
            color: DrawColor(0xFF1576FE),
            fillColor: DrawColor(0x221576FE),
          ),
        ),
        LineRenderTask(
          element: _element(
            id: 'line',
            rect: const DrawRect(minX: 10, minY: 10, maxX: 160, maxY: 100),
            data: const LineData(),
          ),
          data: const LineData(),
        ),
        ArrowRenderTask(
          element: _element(
            id: 'arrow',
            rect: const DrawRect(minX: 20, minY: 20, maxX: 180, maxY: 120),
            data: const ArrowData(),
          ),
          data: const ArrowData(),
        ),
        FreeDrawRenderTask(
          element: _element(
            id: 'free',
            rect: const DrawRect(minX: 30, minY: 20, maxX: 200, maxY: 140),
            data: const FreeDrawData(),
          ),
          data: const FreeDrawData(),
        ),
        TextRenderTask(
          element: _element(
            id: 'text',
            rect: const DrawRect(minX: 20, minY: 150, maxX: 220, maxY: 220),
            data: const TextData(text: 'Hello'),
          ),
          data: const TextData(text: 'Hello'),
        ),
        SerialNumberRenderTask(
          element: _element(
            id: 'serial',
            rect: const DrawRect(minX: 230, minY: 20, maxX: 280, maxY: 70),
            data: const SerialNumberData(number: 7),
          ),
          data: const SerialNumberData(number: 7),
        ),
        HighlightRenderTask(
          element: _element(
            id: 'highlight',
            rect: const DrawRect(minX: 230, minY: 90, maxX: 320, maxY: 170),
            data: const HighlightData(),
          ),
          data: const HighlightData(),
        ),
        FilterRenderTask(
          element: _element(
            id: 'filter',
            rect: const DrawRect(minX: 230, minY: 180, maxX: 320, maxY: 260),
            data: const FilterData(),
          ),
          data: const FilterData(),
        ),
      ];

      expect(
        () => flutterRenderTaskExecutor.executeTasks(
          canvas: canvas,
          tasks: tasks,
        ),
        returnsNormally,
      );

      recorder.endRecording().dispose();
    },
  );
}

ElementState _element({
  required String id,
  required DrawRect rect,
  required ElementData data,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: data,
);
