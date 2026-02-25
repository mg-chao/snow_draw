import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/services/text/text_metrics_service.dart';
import 'package:test/test.dart';

void main() {
  const service = FallbackTextMetricsService();

  test('measure returns positive metrics for empty text', () {
    final metrics = service.measure(
      const TextLayoutRequest(data: TextData(), maxWidth: 200),
    );

    expect(metrics.width, greaterThan(0));
    expect(metrics.height, greaterThan(0));
    expect(metrics.lineHeight, greaterThan(0));
    expect(metrics.lines, isNotEmpty);
  });

  test('measure wraps long lines when max width is constrained', () {
    final metrics = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'abcdef', fontSize: 10),
        maxWidth: 15,
      ),
    );

    expect(metrics.lines.length, 3);
    expect(metrics.width, 15);
    expect(metrics.height, closeTo(metrics.lineHeight * 3, 0.0001));
  });

  test('measure applies minWidth without exceeding finite maxWidth', () {
    final minApplied = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'a', fontSize: 10),
        maxWidth: 20,
        minWidth: 15,
      ),
    );
    final capped = service.measure(
      const TextLayoutRequest(
        data: TextData(text: 'a', fontSize: 10),
        maxWidth: 20,
        minWidth: 30,
      ),
    );

    expect(minApplied.width, 15);
    expect(capped.width, 20);
  });

  test('clearCaches is a no-op', () {
    service.clearCaches();
  });
}
