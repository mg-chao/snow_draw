import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:test/test.dart';

void main() {
  group('DrawContext.copyWith config handling', () {
    test('copyWith keeps the same config manager by default', () {
      final base = DrawContext.withDefaults();

      final copied = base.copyWith();

      expect(copied.configManager, same(base.configManager));
      expect(copied.config, same(base.config));
    });

    test('copyWith can replace the config manager', () {
      final base = DrawContext.withDefaults();
      final replacement = ConfigManager(
        DrawConfig(
          canvas: const CanvasConfig(backgroundColor: DrawColor(0xFF112233)),
        ),
      );

      final copied = base.copyWith(configManager: replacement);

      expect(copied.configManager, same(replacement));
      expect(copied.config, equals(replacement.current));
    });

    test('withDefaults uses the provided config manager as-is', () {
      final manager = ConfigManager(
        DrawConfig(
          canvas: const CanvasConfig(backgroundColor: DrawColor(0xFFABCDEF)),
        ),
      );

      final context = DrawContext.withDefaults(configManager: manager);

      expect(context.configManager, same(manager));
      expect(context.config, equals(manager.current));
    });
  });
}
