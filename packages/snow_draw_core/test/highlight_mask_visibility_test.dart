import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_visibility.dart';

void main() {
  test('mask layer resolves to none when no highlights', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: false,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(maskOpacity: 1),
    );
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to none when opacity is zero', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(),
    );
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to static when no dynamic content', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(maskOpacity: 0.5),
    );
    expect(layer, HighlightMaskLayer.staticLayer);
  });

  test('mask layer resolves to dynamic when dynamic content exists', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: true,
      config: const HighlightMaskConfig(maskOpacity: 0.5),
    );
    expect(layer, HighlightMaskLayer.dynamicLayer);
  });
}
