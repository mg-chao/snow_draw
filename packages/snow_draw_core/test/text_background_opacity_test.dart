import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_renderer.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'text background keeps consistent alpha in overlapped line boxes',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      const imageSize = ui.Size(220, 220);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

      const elementRect = DrawRect(minX: 10, minY: 10, maxX: 190, maxY: 190);
      const data = TextData(
        text: 'AAAA\nAAAA',
        color: ui.Color(0x00000000),
        fillColor: ui.Color(0x80FF0000),
      );
      const element = ElementState(
        id: 'text-bg-opacity',
        rect: elementRect,
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: data,
      );

      final fillLayout = layoutText(
        data: data,
        maxWidth: elementRect.width,
        minWidth: elementRect.width,
        widthBasis: TextWidthBasis.parent,
        styleOverride: buildTextStyle(data: data, colorOverride: data.color),
      );
      final boxes = fillLayout.paragraph.getBoxesForRange(
        0,
        data.text.length,
        boxHeightStyle: ui.BoxHeightStyle.strut,
      );
      expect(boxes.length, greaterThanOrEqualTo(2));

      final verticalPadding = resolveTextBackgroundVerticalPadding(
        fillLayout.lineHeight,
      );
      final horizontalPadding = resolveTextBackgroundHorizontalPadding(
        fillLayout.lineHeight,
      );
      final textDy = (elementRect.height - fillLayout.size.height) / 2;

      final firstLineRect = ui.Rect.fromLTRB(
        boxes[0].left - horizontalPadding,
        boxes[0].top - verticalPadding,
        boxes[0].right + horizontalPadding,
        boxes[0].bottom + verticalPadding,
      ).shift(ui.Offset(0, textDy));
      final secondLineRect = ui.Rect.fromLTRB(
        boxes[1].left - horizontalPadding,
        boxes[1].top - verticalPadding,
        boxes[1].right + horizontalPadding,
        boxes[1].bottom + verticalPadding,
      ).shift(ui.Offset(0, textDy));

      final overlappedRect = firstLineRect.intersect(secondLineRect);
      expect(overlappedRect.height, greaterThan(0));
      expect(overlappedRect.width, greaterThan(0));

      final singleAreaTop = firstLineRect.top;
      final singleAreaBottom = overlappedRect.top;
      expect(singleAreaBottom - singleAreaTop, greaterThan(2));

      final sampleOverlap = ui.Offset(
        elementRect.minX + overlappedRect.center.dx,
        elementRect.minY + overlappedRect.center.dy,
      );
      final sampleSingle = ui.Offset(
        elementRect.minX + overlappedRect.center.dx,
        elementRect.minY + (singleAreaTop + singleAreaBottom) / 2,
      );

      const TextRenderer().render(
        canvas: canvas,
        element: element,
        scaleFactor: 1,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        imageSize.width.toInt(),
        imageSize.height.toInt(),
      );
      final byteData = await image.toByteData();
      expect(byteData, isNotNull);

      final overlapColor = _readPixel(
        byteData!,
        imageSize.width.toInt(),
        sampleOverlap,
      );
      final singleColor = _readPixel(
        byteData,
        imageSize.width.toInt(),
        sampleSingle,
      );
      final singleGreen = _toChannel8(singleColor.g);
      final overlapGreen = _toChannel8(overlapColor.g);
      final singleBlue = _toChannel8(singleColor.b);
      final overlapBlue = _toChannel8(overlapColor.b);

      expect(singleGreen, inInclusiveRange(120, 140));
      expect((overlapGreen - singleGreen).abs(), lessThanOrEqualTo(1));
      expect((overlapBlue - singleBlue).abs(), lessThanOrEqualTo(1));
    },
  );
}

int _toChannel8(double normalizedChannel) =>
    (normalizedChannel * 255).round().clamp(0, 255);

ui.Color _readPixel(ByteData data, int width, ui.Offset offset) {
  final x = offset.dx.round();
  final y = offset.dy.round();
  final index = ((y * width) + x) * 4;
  final r = data.getUint8(index);
  final g = data.getUint8(index + 1);
  final b = data.getUint8(index + 2);
  final a = data.getUint8(index + 3);
  return ui.Color.fromARGB(a, r, g, b);
}
