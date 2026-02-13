import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';

void main() {
  group('ConfigManager freeze behavior', () {
    test('combines partial updates queued during freeze', () async {
      final manager = ConfigManager(DrawConfig());
      final emitted = <DrawConfig>[];
      final subscription = manager.stream.listen(emitted.add);
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
      });

      final nextSelection = manager.current.selection.copyWith(padding: 12);
      final nextCanvas = manager.current.canvas.copyWith(
        backgroundColor: const Color(0xFFF5F5F5),
      );

      manager.freeze();
      expect(manager.updateSelection(nextSelection), isFalse);
      expect(manager.updateCanvas(nextCanvas), isFalse);

      // Reads stay frozen until unfreeze.
      expect(manager.current.selection, isNot(nextSelection));
      expect(manager.current.canvas, isNot(nextCanvas));

      manager.unfreeze();
      await Future<void>.delayed(Duration.zero);

      expect(manager.current.selection, nextSelection);
      expect(manager.current.canvas, nextCanvas);
      expect(emitted, hasLength(1));
      expect(emitted.single.selection, nextSelection);
      expect(emitted.single.canvas, nextCanvas);
    });

    test('holds pending updates until the outer freeze completes', () async {
      final manager = ConfigManager(DrawConfig());
      final emitted = <DrawConfig>[];
      final subscription = manager.stream.listen(emitted.add);
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
      });

      final nextSelection = manager.current.selection.copyWith(padding: 9);

      manager
        ..freeze()
        ..freeze();
      expect(manager.updateSelection(nextSelection), isFalse);

      manager.unfreeze();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current.selection, isNot(nextSelection));
      expect(emitted, isEmpty);

      manager.unfreeze();
      await Future<void>.delayed(Duration.zero);
      expect(manager.current.selection, nextSelection);
      expect(emitted, hasLength(1));
    });
  });

  group('DrawConfig copyWith behavior', () {
    test(
      'keeps serial number defaults specialized when element style changes',
      () {
        final config = DrawConfig(
          serialNumberStyle: const ElementStyleConfig(
            serialNumber: 41,
            fontSize: 19,
            color: Color(0xFF334455),
          ),
        );

        final nextElementStyle = config.elementStyle.copyWith(
          color: const Color(0xFF009966),
          fontSize: 34,
        );

        final updated = config.copyWith(elementStyle: nextElementStyle);

        expect(updated.serialNumberStyle.color, nextElementStyle.color);
        expect(
          updated.serialNumberStyle.fontSize,
          ConfigDefaults.defaultSerialNumberFontSize,
        );
        expect(updated.serialNumberStyle.serialNumber, 41);
      },
    );
  });
}
