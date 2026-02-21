import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';

void main() {
  test('channels and normalized channels are derived from argb32', () {
    const color = DrawColor(0x80402010);

    expect(color.alpha, 0x80);
    expect(color.red, 0x40);
    expect(color.green, 0x20);
    expect(color.blue, 0x10);
    expect(color.a, closeTo(0x80 / 255, 0.000001));
    expect(color.r, closeTo(0x40 / 255, 0.000001));
    expect(color.g, closeTo(0x20 / 255, 0.000001));
    expect(color.b, closeTo(0x10 / 255, 0.000001));
    expect(color.toARGB32(), 0x80402010);
  });

  test('withAlpha updates only alpha channel', () {
    const color = DrawColor(0x80402010);
    final updated = color.withAlpha(0x12);

    expect(updated.toARGB32(), 0x12402010);
  });

  test('withValues updates normalized channels', () {
    const color = DrawColor(0x80402010);
    final updated = color.withValues(alpha: 1, red: 0, green: 0.5, blue: 1);

    expect(updated.toARGB32(), 0xFF0080FF);
  });
}
