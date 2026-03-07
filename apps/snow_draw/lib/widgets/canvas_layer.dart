import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

import '../render_backend.dart';
import '../tool_controller.dart';

class CanvasLayer extends StatelessWidget {
  const CanvasLayer({
    required this.size,
    required this.store,
    required this.toolController,
    this.watermarkPreviewListenable,
    super.key,
  });

  final Size size;
  final DefaultDrawStore store;
  final ToolController toolController;
  final ValueListenable<WatermarkConfig?>? watermarkPreviewListenable;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DiagnosticsProperty<DefaultDrawStore>('store', store))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      )
      ..add(
        DiagnosticsProperty<ValueListenable<WatermarkConfig?>?>(
          'watermarkPreviewListenable',
          watermarkPreviewListenable,
        ),
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
      isSelectionToolActive: tool == ToolType.selection,
      isEraserToolActive: tool == ToolType.eraser,
      watermarkPreviewListenable: watermarkPreviewListenable,
    ),
  );
}
