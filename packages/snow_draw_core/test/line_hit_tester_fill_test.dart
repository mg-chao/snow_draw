import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_hit_tester.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

const _tester = LineHitTester();
const _rect = DrawRect(maxX: 100, maxY: 100);
const _closedPoints = [
  DrawPoint(x: 0.1, y: 0.1),
  DrawPoint(x: 0.9, y: 0.15),
  DrawPoint(x: 0.85, y: 0.85),
  DrawPoint(x: 0.15, y: 0.9),
  DrawPoint(x: 0.1, y: 0.1),
];

void main() {
  test('closed line fill hit works without stroke', () {
    final data = LineData(
      points: _closedPoints,
      strokeWidth: 0,
      fillColor: const DrawColor(0xAA1576FE),
    );
    final element = _lineElement(data);

    final hit = _tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isTrue);
  });

  test('open line does not report fill hit', () {
    final data = LineData(
      points: const [
        DrawPoint(x: 0.1, y: 0.1),
        DrawPoint(x: 0.9, y: 0.15),
        DrawPoint(x: 0.85, y: 0.85),
        DrawPoint(x: 0.15, y: 0.9),
      ],
      strokeWidth: 0,
      fillColor: const DrawColor(0xAA1576FE),
    );
    final element = _lineElement(data);

    final hit = _tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isFalse);
  });

  test('closed line fill hit works for rotated elements', () {
    final data = LineData(
      points: _closedPoints,
      strokeWidth: 0,
      fillColor: const DrawColor(0xAA1576FE),
    );
    final element = _lineElement(data, rotation: math.pi / 4);

    final hit = _tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );

    expect(hit, isTrue);
  });
}

ElementState _lineElement(LineData data, {double rotation = 0}) => ElementState(
  id: 'line_fill',
  rect: _rect,
  rotation: rotation,
  opacity: 1,
  zIndex: 0,
  data: data,
);
