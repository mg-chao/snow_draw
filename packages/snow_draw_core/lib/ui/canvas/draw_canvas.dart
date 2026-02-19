import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/elements/core/element_data.dart';
import '../../draw/elements/core/element_type_id.dart';
import '../../draw/store/draw_store_interface.dart';
import 'plugin_draw_canvas.dart';

class DrawCanvas extends StatefulWidget {
  const DrawCanvas({
    required this.size,
    required this.store,
    super.key,
    this.scaleFactor = 1.0,
    this.currentToolTypeId,
    this.isSelectionToolActive = true,
    this.isEraserToolActive = false,
    this.watermarkPreviewListenable,
  });
  final Size size;
  final double scaleFactor;
  final DrawStore store;
  final ElementTypeId<ElementData>? currentToolTypeId;
  final bool isSelectionToolActive;
  final bool isEraserToolActive;
  final ValueListenable<WatermarkConfig?>? watermarkPreviewListenable;

  @override
  State<DrawCanvas> createState() => DrawCanvasState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DoubleProperty('scaleFactor', scaleFactor))
      ..add(DiagnosticsProperty<DrawStore>('store', store))
      ..add(
        DiagnosticsProperty<ElementTypeId<ElementData>?>(
          'currentToolTypeId',
          currentToolTypeId,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'isSelectionToolActive',
          isSelectionToolActive,
        ),
      )
      ..add(DiagnosticsProperty<bool>('isEraserToolActive', isEraserToolActive))
      ..add(
        DiagnosticsProperty<ValueListenable<WatermarkConfig?>?>(
          'watermarkPreviewListenable',
          watermarkPreviewListenable,
        ),
      );
  }
}

class DrawCanvasState extends State<DrawCanvas> {
  @override
  Widget build(BuildContext context) => PluginDrawCanvas(
    size: widget.size,
    store: widget.store,
    scaleFactor: widget.scaleFactor,
    currentToolTypeId: widget.currentToolTypeId,
    isSelectionToolActive: widget.isSelectionToolActive,
    isEraserToolActive: widget.isEraserToolActive,
    watermarkPreviewListenable: widget.watermarkPreviewListenable,
  );
}
