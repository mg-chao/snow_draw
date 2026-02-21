import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_visibility.dart';

void main() {
  HighlightMaskLayer resolveLayer({
    required bool hasHighlights,
    bool hasDynamicContent = false,
    bool hasDynamicHighlights = false,
    double maskOpacity = 0.5,
  }) {
    return resolveHighlightMaskLayer(
      hasHighlights: hasHighlights,
      hasDynamicContent: hasDynamicContent,
      hasDynamicHighlights: hasDynamicHighlights,
      config: HighlightMaskConfig(maskOpacity: maskOpacity),
    );
  }

  test('mask layer resolves to none when no highlights', () {
    final layer = resolveLayer(hasHighlights: false, maskOpacity: 1);
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to none when opacity is zero', () {
    final layer = resolveLayer(hasHighlights: true, maskOpacity: 0);
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to static when no dynamic highlights', () {
    final layer = resolveLayer(hasHighlights: true);
    expect(layer, HighlightMaskLayer.staticLayer);
  });

  test('mask layer resolves to dynamic when highlights are dynamic', () {
    final layer = resolveLayer(hasHighlights: true, hasDynamicHighlights: true);
    expect(layer, HighlightMaskLayer.dynamicLayer);
  });

  test('mask layer resolves to dynamic when scene content is dynamic', () {
    final layer = resolveLayer(hasHighlights: true, hasDynamicContent: true);
    expect(layer, HighlightMaskLayer.dynamicLayer);
  });
}
