import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/ui/canvas/draw_canvas.dart';

import '../tool_controller.dart';

class CanvasLayer extends StatelessWidget {
  const CanvasLayer({
    required this.size,
    required this.store,
    required this.toolController,
    super.key,
  });

  final Size size;
  final DefaultDrawStore store;
  final ToolController toolController;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DiagnosticsProperty<DefaultDrawStore>('store', store))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      );
  }

  static const Map<ToolType, ElementTypeId<ElementData>> _toolTypeIds = {
    ToolType.rectangle: RectangleData.typeIdToken,
    ToolType.highlight: HighlightData.typeIdToken,
    ToolType.filter: FilterData.typeIdToken,
    ToolType.arrow: ArrowData.typeIdToken,
    ToolType.line: LineData.typeIdToken,
    ToolType.freeDraw: FreeDrawData.typeIdToken,
    ToolType.text: TextData.typeIdToken,
    ToolType.serialNumber: SerialNumberData.typeIdToken,
  };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ToolType>(
    // Canvas owns store subscriptions; this layer only reacts to tool changes.
    valueListenable: toolController,
    builder: (context, tool, _) => DrawCanvas(
      size: size,
      store: store,
      currentToolTypeId: _toolTypeIds[tool],
    ),
  );
}
