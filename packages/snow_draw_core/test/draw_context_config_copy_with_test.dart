import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';

void main() {
  group('DrawContext copyWith configuration behavior', () {
    test('applies config when config and configManager are both provided', () {
      final base = DrawContext.withDefaults();
      final manager = ConfigManager(DrawConfig());
      final nextConfig = DrawConfig(
        canvas: const CanvasConfig(backgroundColor: Color(0xFF112233)),
      );

      final copied = base.copyWith(configManager: manager, config: nextConfig);

      expect(copied.configManager, same(manager));
      expect(copied.config, nextConfig);
      expect(manager.current, nextConfig);
    });

    test(
      'reuses existing configManager when provided config is value-equal',
      () {
        final base = DrawContext.withDefaults(config: DrawConfig());

        final copied = base.copyWith(config: DrawConfig());

        expect(copied.configManager, same(base.configManager));
        expect(copied.config, base.config);
      },
    );

    test('creates a new configManager when provided config is different', () {
      final base = DrawContext.withDefaults(config: DrawConfig());
      final nextConfig = base.config.copyWith(
        canvas: const CanvasConfig(backgroundColor: Color(0xFFABCDEF)),
      );

      final copied = base.copyWith(config: nextConfig);

      expect(copied.configManager, isNot(same(base.configManager)));
      expect(copied.config, nextConfig);
      expect(base.config, isNot(nextConfig));
    });
  });
}
