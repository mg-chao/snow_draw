import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('highlight mask clears holes for highlight shapes', () async {
    const element = ElementState(
      id: 'h1',
      rect: DrawRect(minX: 5, minY: 5, maxX: 15, maxY: 15),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(),
    );

    final initial = DrawState.initial();
    final state = DrawState(
      domain: initial.domain.copyWith(
        document: initial.domain.document.copyWith(elements: [element]),
      ),
      application: initial.application.copyWith(interaction: const IdleState()),
    );
    final view = DrawStateView.fromState(state);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    paintHighlightMask(
      canvas: canvas,
      stateView: view,
      viewportRect: const DrawRect(maxX: 20, maxY: 20),
      maskConfig: const HighlightMaskConfig(maskOpacity: 1),
      creatingElement: null,
    );

    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    final data = bytes!;
    int pixelAt(int x, int y, int channel) =>
        data.getUint8(((y * 20) + x) * 4 + channel);

    expect(pixelAt(1, 1, 3), 255);
    expect(pixelAt(10, 10, 3), 0);
  });
}
