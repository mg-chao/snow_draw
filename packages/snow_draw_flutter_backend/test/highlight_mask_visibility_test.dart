import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';

void main() {
  bool resolveVisibility({
    required bool hasHighlights,
    double maskOpacity = 0.5,
  }) => isHighlightMaskVisible(
    hasHighlights: hasHighlights,
    config: HighlightMaskConfig(maskOpacity: maskOpacity),
  );

  test('mask visibility is false when no highlights', () {
    final visible = resolveVisibility(hasHighlights: false, maskOpacity: 1);
    expect(visible, isFalse);
  });

  test('mask visibility is false when opacity is zero', () {
    final visible = resolveVisibility(hasHighlights: true, maskOpacity: 0);
    expect(visible, isFalse);
  });

  test('mask visibility is true when highlights are visible', () {
    final visible = resolveVisibility(hasHighlights: true);
    expect(visible, isTrue);
  });
}
