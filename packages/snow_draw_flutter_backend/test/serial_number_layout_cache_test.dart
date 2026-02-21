import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_flutter_backend/services/text/flutter_serial_number_layout.dart';

void main() {
  setUp(() {
    clearSerialNumberTextLayoutCache();
    resetSerialNumberLayoutCacheStats();
  });

  test('reuses text geometry when only text color changes', () {
    const data = SerialNumberData(
      number: 42,
      color: DrawColor(0xFF101010),
      fontSize: 21,
    );

    final firstLayout = layoutSerialNumberText(
      data: data,
      colorOverride: const Color(0xFF101010),
    );
    final afterFirst = debugSerialNumberLayoutCacheStats();
    expect(afterFirst.geometryBuildCount, 1);
    expect(afterFirst.painterBuildCount, 1);

    final secondLayout = layoutSerialNumberText(
      data: data,
      colorOverride: const Color(0x80101010),
    );
    final afterSecond = debugSerialNumberLayoutCacheStats();
    expect(afterSecond.geometryBuildCount, 1);
    expect(afterSecond.painterBuildCount, 2);
    expect(secondLayout.size, firstLayout.size);
    expect(secondLayout.lineHeight, firstLayout.lineHeight);
    expect(secondLayout.visualBounds, firstLayout.visualBounds);

    final repeatedSecondLayout = layoutSerialNumberText(
      data: data,
      colorOverride: const Color(0x80101010),
    );
    final afterRepeated = debugSerialNumberLayoutCacheStats();
    expect(afterRepeated.geometryBuildCount, 1);
    expect(afterRepeated.painterBuildCount, 2);
    expect(
      identical(repeatedSecondLayout.painter, secondLayout.painter),
      isTrue,
    );

    final repeatedFirstLayout = layoutSerialNumberText(
      data: data,
      colorOverride: const Color(0xFF101010),
    );
    final afterAll = debugSerialNumberLayoutCacheStats();
    expect(afterAll.geometryBuildCount, 1);
    expect(afterAll.painterBuildCount, 2);
    expect(identical(repeatedFirstLayout.painter, firstLayout.painter), isTrue);
  });

  test('reuses canonical geometry and painter across font-size changes', () {
    const baseData = SerialNumberData(number: 7, color: DrawColor(0xFF222222));
    const scaledData = SerialNumberData(
      number: 7,
      color: DrawColor(0xFF222222),
      fontSize: 32,
    );
    final expectedScale = scaledData.fontSize / baseData.fontSize;

    final baseLayout = layoutSerialNumberText(data: baseData);
    final statsAfterBase = debugSerialNumberLayoutCacheStats();
    expect(statsAfterBase.geometryBuildCount, 1);
    expect(statsAfterBase.painterBuildCount, 1);

    final scaledLayout = layoutSerialNumberText(data: scaledData);
    final statsAfterScaled = debugSerialNumberLayoutCacheStats();
    expect(statsAfterScaled.geometryBuildCount, 1);
    expect(statsAfterScaled.painterBuildCount, 1);
    expect(identical(scaledLayout.painter, baseLayout.painter), isTrue);
    expect(scaledLayout.paintScale, closeTo(expectedScale, 0.0001));
    expect(
      scaledLayout.size.width,
      closeTo(baseLayout.size.width * expectedScale, 0.0001),
    );
    expect(
      scaledLayout.size.height,
      closeTo(baseLayout.size.height * expectedScale, 0.0001),
    );
    expect(
      scaledLayout.lineHeight,
      closeTo(baseLayout.lineHeight * expectedScale, 0.0001),
    );
  });
}
