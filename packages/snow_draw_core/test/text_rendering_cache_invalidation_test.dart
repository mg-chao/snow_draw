import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';

void main() {
  setUp(resetSceneTextMetricsService);
  tearDown(resetSceneTextMetricsService);

  test('invalidateTextRenderingCaches notifies listeners and callbacks', () {
    final previousRevision = textRenderingCacheRevisionListenable.value;
    var listenerCalls = 0;
    var invalidatorCalls = 0;
    void onRevision() {
      listenerCalls += 1;
    }

    void invalidator() {
      invalidatorCalls += 1;
    }

    textRenderingCacheRevisionListenable.addListener(onRevision);
    registerTextRenderingCacheInvalidator(invalidator);
    addTearDown(
      () => textRenderingCacheRevisionListenable.removeListener(onRevision),
    );
    addTearDown(() => unregisterTextRenderingCacheInvalidator(invalidator));

    invalidateTextRenderingCaches();

    expect(textRenderingCacheRevisionListenable.value, previousRevision + 1);
    expect(listenerCalls, 1);
    expect(invalidatorCalls, 1);
  });

  test(
    'invalidateTextRenderingCaches clears overridden scene metrics service',
    () {
      final metricsService = _CountingMetricsService();
      configureSceneTextMetricsService(metricsService);

      invalidateTextRenderingCaches();

      expect(metricsService.clearCalls, 1);
    },
  );
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
