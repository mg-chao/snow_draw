import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/plugins/select_plugin.dart';
import 'package:snow_draw_core/draw/input/plugins/text_tool_plugin.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  const event = PointerDownInputEvent(
    position: DrawPoint(x: 20, y: 20),
    modifiers: KeyModifiers.none,
  );

  group('SelectPlugin tool mode routing', () {
    test('disables selection handling when selection mode is inactive', () {
      final plugin = SelectPlugin(isSelectionToolActive: false);

      expect(plugin.canHandle(event, DrawState()), isFalse);
    });

    test('keeps routing enabled when a drawing tool is active', () {
      final plugin = SelectPlugin(
        currentToolTypeId: RectangleData.typeIdToken,
        isSelectionToolActive: false,
      );

      expect(plugin.canHandle(event, DrawState()), isTrue);
    });
  });

  group('TextToolPlugin tool mode routing', () {
    test('does not handle selection-like interactions for watermark mode', () {
      final plugin = TextToolPlugin(
        currentToolTypeId: null,
        isSelectionToolActive: false,
      );

      expect(plugin.canHandle(event, DrawState()), isFalse);
    });

    test('handles selection-like interactions for selection mode', () {
      final plugin = TextToolPlugin(currentToolTypeId: null);

      expect(plugin.canHandle(event, DrawState()), isTrue);
    });

    test('serial number mode remains selection-like', () {
      final plugin = TextToolPlugin(
        currentToolTypeId: SerialNumberData.typeIdToken,
      );

      expect(plugin.canHandle(event, DrawState()), isTrue);
    });
  });
}
