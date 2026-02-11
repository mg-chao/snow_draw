import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_path_utils.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_visual_cache.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('layoutText paragraph cache respects paint attributes', () {
    const data = TextData(
      text: 'layout-cache-color-regression',
      color: Colors.black,
    );

    final redLayout = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.red,
      widthBasis: TextWidthBasis.parent,
    );
    final blueLayout = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.blue,
      widthBasis: TextWidthBasis.parent,
    );
    final redLayoutAgain = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.red,
      widthBasis: TextWidthBasis.parent,
    );

    expect(identical(redLayout.paragraph, blueLayout.paragraph), isFalse);
    expect(identical(redLayout.paragraph, redLayoutAgain.paragraph), isTrue);
  });

  test('incremental free-draw path keeps boundary segment continuity', () {
    final points = <ui.Offset>[
      ui.Offset.zero,
      const ui.Offset(10, 50),
      const ui.Offset(20, -50),
      const ui.Offset(30, 50),
      const ui.Offset(40, -50),
      const ui.Offset(50, 0),
    ];

    final base = buildFreeDrawSmoothPath(points.sublist(0, 5));
    final full = buildFreeDrawSmoothPath(points);
    final incremental = buildFreeDrawSmoothPathIncremental(
      allPoints: points,
      basePath: base,
      basePointCount: 5,
    );

    expect(incremental, isNotNull);
    final fullLength = _pathLength(full);
    final incrementalLength = _pathLength(incremental!);
    expect((fullLength - incrementalLength).abs(), lessThan(0.001));
  });

  test('replacing free-draw cache entry clears old cached picture', () {
    final cache = FreeDrawVisualCache.instance;

    const data = FreeDrawData(
      points: [
        DrawPoint.zero,
        DrawPoint(x: 0.4, y: 0.2),
        DrawPoint(x: 0.8, y: 0.8),
      ],
    );

    const element = ElementState(
      id: 'free-draw-picture-dispose-regression',
      rect: DrawRect(maxX: 100, maxY: 100),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: data,
    );

    final entry = cache.resolve(element: element, data: data)
      ..setCachedPicture(_recordPicture(), 1);
    expect(entry.getCachedPicture(1), isNotNull);

    final updatedData = data.copyWith(strokeWidth: data.strokeWidth + 1);
    final updatedElement = element.copyWith(data: updatedData);
    cache.resolve(element: updatedElement, data: updatedData);

    expect(entry.getCachedPicture(1), isNull);
  });
}

double _pathLength(ui.Path path) {
  var totalLength = 0.0;
  for (final metric in path.computeMetrics()) {
    totalLength += metric.length;
  }
  return totalLength;
}

ui.Picture _recordPicture() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.black;
  canvas.drawLine(ui.Offset.zero, const ui.Offset(10, 10), paint);
  return recorder.endRecording();
}
