import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

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

  group('ConfigManager lifecycle behavior', () {
    test('ignores updates after dispose', () async {
      final manager = ConfigManager(DrawConfig());
      final baseConfig = manager.current;

      await manager.dispose();

      final nextConfig = baseConfig.copyWith(
        canvas: baseConfig.canvas.copyWith(
          backgroundColor: const Color(0xFF112233),
        ),
      );
      final nextSelection = baseConfig.selection.copyWith(
        padding: baseConfig.selection.padding + 7,
      );
      final nextCanvas = baseConfig.canvas.copyWith(
        backgroundColor: const Color(0xFF445566),
      );

      expect(manager.update(nextConfig), isFalse);
      expect(manager.updateSelection(nextSelection), isFalse);
      expect(manager.updateCanvas(nextCanvas), isFalse);
      expect(manager.current, same(baseConfig));
    });

    test('dispose clears frozen state and drops pending updates', () async {
      final manager = ConfigManager(DrawConfig());
      final emitted = <DrawConfig>[];
      final subscription = manager.stream.listen(emitted.add);
      addTearDown(() async {
        await subscription.cancel();
      });

      final baseSelection = manager.current.selection;
      final nextSelection = baseSelection.copyWith(
        padding: baseSelection.padding + 10,
      );

      manager.freeze();
      expect(manager.updateSelection(nextSelection), isFalse);

      await manager.dispose();
      expect(manager.unfreeze, returnsNormally);
      expect(manager.current.selection, baseSelection);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);
    });

    test('dispose is idempotent', () async {
      final manager = ConfigManager(DrawConfig());

      await manager.dispose();
      await manager.dispose();
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

    test('does not reset specialized styles on value-equal element style', () {
      final config = DrawConfig(
        elementStyle: const ElementStyleConfig(
          color: Color(0xFF112233),
          strokeWidth: 3,
        ),
        serialNumberStyle: const ElementStyleConfig(
          serialNumber: 9,
          color: Color(0xFFAA3300),
          fontSize: 24,
        ),
        filterStyle: const ElementStyleConfig(
          color: Color(0xFF334455),
          filterType: CanvasFilterType.gaussianBlur,
          filterStrength: 0.9,
        ),
        highlightStyle: const ElementStyleConfig(
          color: Color(0xFF22AA55),
          textStrokeColor: Color(0xFF101010),
          textStrokeWidth: 1.5,
          highlightShape: HighlightShape.ellipse,
        ),
      );

      final updated = config.copyWith(
        elementStyle: config.elementStyle.copyWith(),
      );

      expect(updated.serialNumberStyle, config.serialNumberStyle);
      expect(updated.filterStyle, config.filterStyle);
      expect(updated.highlightStyle, config.highlightStyle);
    });

    test(
      'returns the same instance when copyWith has no effective changes',
      () {
        final config = DrawConfig();

        expect(config.copyWith(), same(config));
        expect(config.copyWith(selection: config.selection), same(config));
        expect(config.copyWith(canvas: config.canvas), same(config));
      },
    );
  });
}
