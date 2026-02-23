import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('text layout constants', () {
    test('caret constants stay stable', () {
      expect(textCursorWidth, 1.2);
      expect(textCaretGap, 1.0);
      expect(textCaretMargin, textCursorWidth + textCaretGap);
    });

    test('padding helpers sanitize invalid inputs', () {
      expect(resolveTextLayoutHorizontalPadding(10), 0.1);
      expect(resolveTextBackgroundHorizontalPadding(10), 3.2);
      expect(resolveTextBackgroundVerticalPadding(10), 1.0);

      expect(resolveTextLayoutHorizontalPadding(double.nan), 0);
      expect(resolveTextBackgroundHorizontalPadding(double.infinity), 0);
      expect(resolveTextBackgroundVerticalPadding(double.negativeInfinity), 0);
    });
  });
}
