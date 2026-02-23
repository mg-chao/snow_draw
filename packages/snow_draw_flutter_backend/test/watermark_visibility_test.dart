import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/watermark_visibility.dart';

void main() {
  test('isWatermarkVisible returns false for whitespace-only text', () {
    expect(isWatermarkVisible(const WatermarkConfig(text: '   ')), isFalse);
  });

  test('isWatermarkVisible returns false for imperceptible alpha', () {
    expect(
      isWatermarkVisible(
        const WatermarkConfig(text: 'CONFIDENTIAL', opacity: 0.001),
      ),
      isFalse,
    );
  });

  test('isWatermarkVisible returns true for visible watermark config', () {
    expect(
      isWatermarkVisible(const WatermarkConfig(text: 'CONFIDENTIAL')),
      isTrue,
    );
  });
}
