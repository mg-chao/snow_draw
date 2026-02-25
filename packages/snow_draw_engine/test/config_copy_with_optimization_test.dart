import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/types/draw_color.dart';
import 'package:test/test.dart';

void expectNoOp<T extends Object>(T config, T Function() copy) {
  expect(copy(), same(config));
}

void main() {
  group('Configuration copyWith no-op behavior', () {
    test('leaf configs return the same instance when unchanged', () {
      const canvas = CanvasConfig();
      expectNoOp(canvas, canvas.copyWith);
      expectNoOp(
        canvas,
        () => canvas.copyWith(backgroundColor: canvas.backgroundColor),
      );

      const boxSelection = BoxSelectionConfig();
      expectNoOp(boxSelection, boxSelection.copyWith);
      expectNoOp(
        boxSelection,
        () => boxSelection.copyWith(strokeWidth: boxSelection.strokeWidth),
      );

      const element = ElementConfig();
      expectNoOp(element, element.copyWith);
      expectNoOp(
        element,
        () => element.copyWith(rotationSnapAngle: element.rotationSnapAngle),
      );

      const grid = GridConfig();
      expectNoOp(grid, grid.copyWith);
      expectNoOp(grid, () => grid.copyWith(size: grid.size));

      const snap = SnapConfig();
      expectNoOp(snap, snap.copyWith);
      expectNoOp(snap, () => snap.copyWith(distance: snap.distance));

      const highlight = HighlightMaskConfig();
      expectNoOp(highlight, highlight.copyWith);
      expectNoOp(
        highlight,
        () => highlight.copyWith(maskOpacity: highlight.maskOpacity),
      );

      const watermark = WatermarkConfig();
      expectNoOp(watermark, watermark.copyWith);
      expectNoOp(watermark, () => watermark.copyWith(text: watermark.text));
    });

    test('selection configs return the same instance when unchanged', () {
      const render = SelectionRenderConfig();
      expectNoOp(render, render.copyWith);
      expectNoOp(
        render,
        () => render.copyWith(controlPointSize: render.controlPointSize),
      );

      const interaction = SelectionInteractionConfig();
      expectNoOp(interaction, interaction.copyWith);
      expectNoOp(
        interaction,
        () =>
            interaction.copyWith(handleTolerance: interaction.handleTolerance),
      );

      const selection = SelectionConfig();
      expectNoOp(selection, selection.copyWith);
      expectNoOp(
        selection,
        () => selection.copyWith(
          render: selection.render,
          interaction: selection.interaction,
          padding: selection.padding,
          rotateHandleOffset: selection.rotateHandleOffset,
        ),
      );
    });

    test(
      'element style keeps normalization behavior while avoiding no-op clones',
      () {
        const style = ElementStyleConfig(
          color: DrawColor(0xFF123456),
          fillColor: DrawColor(0xFFFFEE00),
          strokeWidth: 3,
          fontFamily: 'Roboto',
        );

        expectNoOp(style, style.copyWith);
        expectNoOp(
          style,
          () => style.copyWith(
            color: style.color,
            fillColor: style.fillColor,
            strokeWidth: style.strokeWidth,
            fontFamily: style.fontFamily,
          ),
        );

        final cleared = style.copyWith(fontFamily: '   ');
        expect(cleared, isNot(same(style)));
        expect(cleared.fontFamily, isNull);
      },
    );

    test('element style can explicitly clear font family with null', () {
      const style = ElementStyleConfig(fontFamily: 'Roboto');

      final cleared = style.copyWith(fontFamily: null);

      expect(cleared, isNot(same(style)));
      expect(cleared.fontFamily, isNull);
    });

    test('element style rejects invalid font family copyWith values', () {
      const style = ElementStyleConfig(fontFamily: 'Roboto');

      expect(
        () => style.copyWith(fontFamily: 42),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('draw config copyWith returns an equal snapshot', () {
      final config = DrawConfig();

      final copied = config.copyWith(
        grid: config.grid.copyWith(size: config.grid.size),
        snap: config.snap.copyWith(enabled: config.snap.enabled),
      );

      expect(copied, equals(config));
      expect(copied, isNot(same(config)));
    });
  });
}
