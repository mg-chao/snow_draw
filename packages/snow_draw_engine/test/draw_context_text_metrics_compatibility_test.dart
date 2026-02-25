import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/services/text/text_metrics_service.dart';
import 'package:test/test.dart';

void main() {
  group('DrawContext text metrics compatibility', () {
    test('withDefaults uses shared default text metrics service', () {
      final context = DrawContext.withDefaults();

      expect(context.textMetricsService, same(defaultTextMetricsService));
    });

    test('withDefaults honors injected text metrics service', () {
      final service = _FakeTextMetricsService();
      final context = DrawContext.withDefaults(textMetricsService: service);

      expect(context.textMetricsService, same(service));
    });

    test('copyWith preserves existing text metrics service by default', () {
      final service = _FakeTextMetricsService();
      final context = DrawContext.withDefaults(textMetricsService: service);

      final copied = context.copyWith();

      expect(copied.textMetricsService, same(service));
    });

    test('copyWith can replace text metrics service', () {
      final original = _FakeTextMetricsService();
      final replacement = _FakeTextMetricsService();
      final context = DrawContext.withDefaults(textMetricsService: original);

      final copied = context.copyWith(textMetricsService: replacement);

      expect(copied.textMetricsService, same(replacement));
      expect(copied.textMetricsService, isNot(same(original)));
    });
  });
}

final class _FakeTextMetricsService implements TextMetricsService {
  @override
  TextMetrics measure(TextLayoutRequest request) => const TextMetrics(
    width: 1,
    height: 1,
    lineHeight: 1,
    lines: <TextLineMetrics>[],
  );

  @override
  void clearCaches() {}
}
