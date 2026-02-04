import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/ui/canvas/draw_canvas.dart';

import '../tool_controller.dart';

class CanvasLayer extends StatefulWidget {
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
  State<CanvasLayer> createState() => _CanvasLayerState();

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
}

class _CanvasLayerState extends State<CanvasLayer> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ToolType>(
    // Canvas owns store subscriptions; this layer only reacts to tool changes.
    valueListenable: widget.toolController,
    builder: (context, tool, _) => DrawCanvas(
      size: widget.size,
      store: widget.store,
      currentToolTypeId: tool == ToolType.rectangle
          ? RectangleData.typeIdToken
          : tool == ToolType.arrow
          ? ArrowData.typeIdToken
          : tool == ToolType.line
          ? LineData.typeIdToken
          : tool == ToolType.freeDraw
          ? FreeDrawData.typeIdToken
          : tool == ToolType.text
          ? TextData.typeIdToken
          : null,
    ),
  );
}
