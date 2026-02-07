import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/utils/binding_highlight_style.dart';

void main() {
  test('resolveBindingHighlightStrokeWidth keeps fixed screen width', () {
    expect(resolveBindingHighlightStrokeWidth(1), 6);
    expect(resolveBindingHighlightStrokeWidth(2), 3);
    expect(resolveBindingHighlightStrokeWidth(0), 6);
  });

  test('createBindingHighlightPaint uses fixed alpha', () {
    final paint = createBindingHighlightPaint(
      color: const Color(0xFF000000),
      scale: 1,
    );

    expect(paint.color.alpha, 82);
    expect(paint.strokeWidth, 6);
  });

  test('resolveBindingHighlightOuterRect inflates by half stroke width', () {
    final rect = Rect.fromLTWH(0, 0, 10, 10);

    final outer = resolveBindingHighlightOuterRect(rect, 6);

    expect(outer.left, -3);
    expect(outer.top, -3);
    expect(outer.width, 16);
    expect(outer.height, 16);
  });

  test('resolveBindingHighlightOuterRadius adds half stroke width', () {
    final outer = resolveBindingHighlightOuterRadius(5, 6);

    expect(outer, 8);
  });
}
