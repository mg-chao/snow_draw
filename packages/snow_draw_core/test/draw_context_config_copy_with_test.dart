import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';

void main() {
  DrawContext withDefaultConfig() {
    return DrawContext.withDefaults(config: DrawConfig());
  }

  group('DrawContext.copyWith config handling', () {
    test('applies config when config and configManager are both provided', () {
      final base = DrawContext.withDefaults();
      final manager = ConfigManager(DrawConfig());
      final nextConfig = DrawConfig(
        canvas: const CanvasConfig(backgroundColor: DrawColor(0xFF112233)),
      );

      final copied = base.copyWith(configManager: manager, config: nextConfig);

      expect(copied.configManager, same(manager));
      expect(copied.config, nextConfig);
      expect(manager.current, nextConfig);
    });

    test('reuses existing configManager for a value-equal config', () {
      final base = withDefaultConfig();
      final copied = base.copyWith(config: DrawConfig());

      expect(copied.configManager, same(base.configManager));
      expect(copied.config, base.config);
    });

    test('creates a new configManager when provided config is different', () {
      final base = withDefaultConfig();
      final nextConfig = base.config.copyWith(
        canvas: const CanvasConfig(backgroundColor: DrawColor(0xFFABCDEF)),
      );

      final copied = base.copyWith(config: nextConfig);

      expect(copied.configManager, isNot(same(base.configManager)));
      expect(copied.config, nextConfig);
      expect(base.config, isNot(nextConfig));
    });
  });
}
