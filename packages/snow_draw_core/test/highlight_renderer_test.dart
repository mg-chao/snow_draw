import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_renderer.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('highlight renderer uses multiply blend', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(10, 10);

    final bgPaint = ui.Paint()..color = const ui.Color(0xFF808080);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    const element = ElementState(
      id: 'h1',
      rect: DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(color: ui.Color(0xFFFF0000)),
    );

    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    final data = bytes!;
    const offset = ((5 * 10) + 5) * 4;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);

    expect(r, 128);
    expect(g, 0);
    expect(b, 0);
  });

  test('highlight stroke does not use multiply blend', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(10, 10);

    final bgPaint = ui.Paint()..color = const ui.Color(0xFF808080);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    const element = ElementState(
      id: 'h2',
      rect: DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(
        color: ui.Color(0x00FF0000),
        strokeColor: ui.Color(0xFFFF0000),
        strokeWidth: 4,
      ),
    );

    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    final data = bytes!;
    const offset = ((5 * 10) + 1) * 4;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);

    expect(r, 255);
    expect(g, 0);
    expect(b, 0);
  });
}
