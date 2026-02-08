import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_renderer.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

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
      rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(
        shape: HighlightShape.rectangle,
        color: ui.Color(0xFFFF0000),
        strokeWidth: 0,
      ),
    );

    const renderer = HighlightRenderer();
    renderer.render(canvas: canvas, element: element, scaleFactor: 1);

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    final data = bytes!;
    final offset = ((5 * 10) + 5) * 4;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);

    expect(r, 128);
    expect(g, 0);
    expect(b, 0);
  });
}
