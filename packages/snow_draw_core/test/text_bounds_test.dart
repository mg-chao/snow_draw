import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_bounds.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test(
    'fitTextFontSizeToHeight scales up for tall targets with low iterations',
    () {
      const data = TextData(text: 'N', fontSize: 36);

      final fittedFontSize = fitTextFontSizeToHeight(
        data: data,
        targetHeight: 860,
        maxWidth: 420,
        maxIterations: 2,
      );
      final fittedHeight = resolveTextLayoutHeight(
        layoutText(
          data: data.copyWith(fontSize: fittedFontSize),
          maxWidth: 420,
        ),
      );

      expect(fittedFontSize, greaterThan(200));
      expect(fittedHeight, greaterThan(200));
    },
  );

  test('fitTextFontSizeToHeight sanitizes non-finite source font sizes', () {
    const infData = TextData(text: 'A', fontSize: double.infinity);
    const nanData = TextData(text: 'A', fontSize: double.nan);

    final fittedFromInf = fitTextFontSizeToHeight(
      data: infData,
      targetHeight: 80,
      maxWidth: 200,
    );
    final fittedFromNan = fitTextFontSizeToHeight(
      data: nanData,
      targetHeight: 80,
      maxWidth: 200,
    );

    expect(fittedFromInf.isFinite, isTrue);
    expect(fittedFromInf, greaterThan(0));
    expect(fittedFromNan.isFinite, isTrue);
    expect(fittedFromNan, greaterThan(0));
  });

  test(
    'clampTextRectToLayout keeps left edge fixed for left-anchored clamps',
    () {
      const data = TextData(text: 'Long text for minimum width');
      const rect = DrawRect(minX: 10, minY: 20, maxX: 11, maxY: 28);
      const startRect = DrawRect(minX: 10, minY: 20, maxX: 11, maxY: 28);
      const anchor = DrawPoint(x: 5, y: 0);

      final clamped = clampTextRectToLayout(
        rect: rect,
        startRect: startRect,
        anchor: anchor,
        data: data,
      );

      expect(clamped.minX, rect.minX);
      expect(clamped.width, greaterThan(rect.width));
      expect(clamped.minY, rect.minY);
    },
  );
}
