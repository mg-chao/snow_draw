import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';
import 'package:test/test.dart';

void main() {
  const service = FallbackTextMetricsService();

  test('default text metrics service remains fallback implementation', () {
    expect(defaultTextMetricsService, isA<FallbackTextMetricsService>());
  });

  test('scene text metrics service supports override and reset', () {
    final override = _TestMetricsService();
    addTearDown(resetSceneTextMetricsService);

    configureSceneTextMetricsService(override);
    expect(sceneTextMetricsService, same(override));

    resetSceneTextMetricsService();
    expect(sceneTextMetricsService, same(defaultTextMetricsService));
  });

  test(
    'clearTextLayoutCaches clears overridden scene text metrics service',
    () {
      final override = _CountingMetricsService();
      addTearDown(resetSceneTextMetricsService);
      configureSceneTextMetricsService(override);

      clearTextLayoutCaches();

      expect(override.clearCalls, 1);
    },
  );

  test('fallback service sanitizes non-positive max width requests', () {
    final zeroWidth = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'a', fontSize: 10),
        maxWidth: 0,
      ),
    );
    final negativeWidth = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'a', fontSize: 10),
        maxWidth: -10,
      ),
    );

    expect(zeroWidth.width, 1);
    expect(negativeWidth.width, 1);
    expect(zeroWidth.lines, isNotEmpty);
    expect(negativeWidth.lines, isNotEmpty);
  });

  test('fallback service keeps line metrics immutable', () {
    final metrics = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'immutable', fontSize: 16),
        maxWidth: 200,
      ),
    );

    expect(
      () => metrics.lines.add(const TextLineMetrics(width: 1, height: 1)),
      throwsUnsupportedError,
    );
  });

  test(
    'fallback service layout is deterministic across locale and resize flags',
    () {
      final baseline = service.measure(
        const TextLayoutRequest(
          data: TextData(text: 'deterministic', fontSize: 12),
          maxWidth: 120,
          localeTag: 'en-US',
          isResizing: false,
        ),
      );
      final variant = service.measure(
        const TextLayoutRequest(
          data: TextData(text: 'deterministic', fontSize: 12),
          maxWidth: 120,
          localeTag: 'zh-CN',
          isResizing: true,
        ),
      );

      expect(variant.width, baseline.width);
      expect(variant.height, baseline.height);
      expect(variant.lineHeight, baseline.lineHeight);
      expect(variant.lines.length, baseline.lines.length);
      for (var i = 0; i < baseline.lines.length; i++) {
        expect(variant.lines[i].width, baseline.lines[i].width);
        expect(variant.lines[i].height, baseline.lines[i].height);
      }
    },
  );
}

final class _TestMetricsService implements TextMetricsService {
  @override
  TextMetrics measure(TextLayoutRequest request) => const TextMetrics(
    width: 1,
    height: 1,
    lineHeight: 1,
    lines: <TextLineMetrics>[TextLineMetrics(width: 1, height: 1)],
  );

  @override
  void clearCaches() {}
}

final class _CountingMetricsService implements TextMetricsService {
  int clearCalls = 0;

  @override
  TextMetrics measure(TextLayoutRequest request) => const TextMetrics(
    width: 1,
    height: 1,
    lineHeight: 1,
    lines: <TextLineMetrics>[TextLineMetrics(width: 1, height: 1)],
  );

  @override
  void clearCaches() {
    clearCalls += 1;
  }
}
