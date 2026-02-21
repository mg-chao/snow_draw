import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/config_manager.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

void main() {
  group('ConfigManager freeze behavior', () {
    late ConfigManager manager;
    late List<DrawConfig> emitted;
    late StreamSubscription<DrawConfig> subscription;

    setUp(() {
      manager = ConfigManager(DrawConfig());
      emitted = <DrawConfig>[];
      subscription = manager.stream.listen(emitted.add);
    });

    tearDown(() async {
      await subscription.cancel();
      await manager.dispose();
    });

    test('combines partial updates queued during freeze', () async {
      final nextSelection = manager.current.selection.copyWith(padding: 12);
      final nextCanvas = manager.current.canvas.copyWith(
        backgroundColor: const DrawColor(0xFFF5F5F5),
      );

      manager.freeze();
      expect(manager.updateSelection(nextSelection), isFalse);
      expect(manager.updateCanvas(nextCanvas), isFalse);

      expect(manager.current.selection, isNot(nextSelection));
      expect(manager.current.canvas, isNot(nextCanvas));

      manager.unfreeze();
      await _flushAsync();

      expect(manager.current.selection, nextSelection);
      expect(manager.current.canvas, nextCanvas);
      expect(emitted, hasLength(1));
      expect(emitted.single.selection, nextSelection);
      expect(emitted.single.canvas, nextCanvas);
    });

    test('holds pending updates until the outer freeze completes', () async {
      final nextSelection = manager.current.selection.copyWith(padding: 9);

      manager
        ..freeze()
        ..freeze();
      expect(manager.updateSelection(nextSelection), isFalse);

      manager.unfreeze();
      await _flushAsync();
      expect(manager.current.selection, isNot(nextSelection));
      expect(emitted, isEmpty);

      manager.unfreeze();
      await _flushAsync();
      expect(manager.current.selection, nextSelection);
      expect(emitted, hasLength(1));
    });
  });

  group('ConfigManager lifecycle behavior', () {
    late ConfigManager manager;

    setUp(() {
      manager = ConfigManager(DrawConfig());
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('ignores updates after dispose', () async {
      final baseConfig = manager.current;

      await manager.dispose();

      expect(
        manager.update(
          baseConfig.copyWith(
            canvas: baseConfig.canvas.copyWith(
              backgroundColor: const DrawColor(0xFF112233),
            ),
          ),
        ),
        isFalse,
      );
      expect(
        manager.updateSelection(
          baseConfig.selection.copyWith(
            padding: baseConfig.selection.padding + 7,
          ),
        ),
        isFalse,
      );
      expect(
        manager.updateCanvas(
          baseConfig.canvas.copyWith(
            backgroundColor: const DrawColor(0xFF445566),
          ),
        ),
        isFalse,
      );
      expect(manager.current, same(baseConfig));
    });

    test('dispose clears frozen state and drops pending updates', () async {
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
      await _flushAsync();
      expect(emitted, isEmpty);
    });

    test('dispose is idempotent', () async {
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
            color: DrawColor(0xFF334455),
          ),
        );

        final nextElementStyle = config.elementStyle.copyWith(
          color: const DrawColor(0xFF009966),
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
          color: DrawColor(0xFF112233),
          strokeWidth: 3,
        ),
        serialNumberStyle: const ElementStyleConfig(
          serialNumber: 9,
          color: DrawColor(0xFFAA3300),
          fontSize: 24,
        ),
        filterStyle: const ElementStyleConfig(
          color: DrawColor(0xFF334455),
          filterType: CanvasFilterType.gaussianBlur,
          filterStrength: 0.9,
        ),
        highlightStyle: const ElementStyleConfig(
          color: DrawColor(0xFF22AA55),
          textStrokeColor: DrawColor(0xFF101010),
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
