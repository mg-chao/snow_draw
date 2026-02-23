import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  test('returns the same config when scale factor is effectively 1', () {
    const config = SelectionConfig();

    final scaled = scaleSelectionConfigForInput(
      selectionConfig: config,
      scaleFactor: 1.0,
    );

    expect(identical(scaled, config), isTrue);
  });

  test('scales render and interaction metrics inversely with zoom', () {
    const config = SelectionConfig(
      render: SelectionRenderConfig(
        strokeWidth: 4,
        cornerRadius: 6,
        controlPointSize: 10,
      ),
      interaction: SelectionInteractionConfig(
        handleTolerance: 8,
        dragThreshold: 2,
      ),
      padding: 12,
      rotateHandleOffset: 18,
    );

    final scaled = scaleSelectionConfigForInput(
      selectionConfig: config,
      scaleFactor: 2.0,
    );

    expect(scaled.render.strokeWidth, 2);
    expect(scaled.render.cornerRadius, 3);
    expect(scaled.render.controlPointSize, 5);
    expect(scaled.interaction.handleTolerance, 4);
    expect(scaled.interaction.dragThreshold, 1);
    expect(scaled.padding, 6);
    expect(scaled.rotateHandleOffset, 9);
  });
}
