import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';

void main() {
  group('Configuration copyWith no-op behavior', () {
    test('leaf configs return the same instance when unchanged', () {
      const canvas = CanvasConfig();
      expect(canvas.copyWith(), same(canvas));
      expect(
        canvas.copyWith(backgroundColor: canvas.backgroundColor),
        same(canvas),
      );

      const boxSelection = BoxSelectionConfig();
      expect(boxSelection.copyWith(), same(boxSelection));
      expect(
        boxSelection.copyWith(strokeWidth: boxSelection.strokeWidth),
        same(boxSelection),
      );

      const element = ElementConfig();
      expect(element.copyWith(), same(element));
      expect(
        element.copyWith(rotationSnapAngle: element.rotationSnapAngle),
        same(element),
      );

      const grid = GridConfig();
      expect(grid.copyWith(), same(grid));
      expect(grid.copyWith(size: grid.size), same(grid));

      const snap = SnapConfig();
      expect(snap.copyWith(), same(snap));
      expect(snap.copyWith(distance: snap.distance), same(snap));

      const highlight = HighlightMaskConfig();
      expect(highlight.copyWith(), same(highlight));
      expect(
        highlight.copyWith(maskOpacity: highlight.maskOpacity),
        same(highlight),
      );
    });

    test('selection configs return the same instance when unchanged', () {
      const render = SelectionRenderConfig();
      expect(render.copyWith(), same(render));
      expect(
        render.copyWith(controlPointSize: render.controlPointSize),
        same(render),
      );

      const interaction = SelectionInteractionConfig();
      expect(interaction.copyWith(), same(interaction));
      expect(
        interaction.copyWith(handleTolerance: interaction.handleTolerance),
        same(interaction),
      );

      const selection = SelectionConfig();
      expect(selection.copyWith(), same(selection));
      expect(
        selection.copyWith(
          render: selection.render,
          interaction: selection.interaction,
          padding: selection.padding,
          rotateHandleOffset: selection.rotateHandleOffset,
        ),
        same(selection),
      );
    });

    test(
      'element style keeps normalization behavior while avoiding no-op clones',
      () {
        const style = ElementStyleConfig(
          color: Color(0xFF123456),
          fillColor: Color(0xFFFFEE00),
          strokeWidth: 3,
          fontFamily: 'Roboto',
        );

        expect(style.copyWith(), same(style));
        expect(
          style.copyWith(
            color: style.color,
            fillColor: style.fillColor,
            strokeWidth: style.strokeWidth,
            fontFamily: style.fontFamily,
          ),
          same(style),
        );

        final cleared = style.copyWith(fontFamily: '   ');
        expect(cleared, isNot(same(style)));
        expect(cleared.fontFamily, isNull);
      },
    );

    test('draw config remains stable when nested copyWith is a no-op', () {
      final config = DrawConfig();

      final unchangedGrid = config.grid.copyWith(size: config.grid.size);
      final unchangedSnap = config.snap.copyWith(enabled: config.snap.enabled);

      final updated = config.copyWith(grid: unchangedGrid, snap: unchangedSnap);

      expect(updated, same(config));
    });
  });
}
