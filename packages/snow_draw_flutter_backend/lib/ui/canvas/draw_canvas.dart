import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'plugin_draw_canvas.dart';

class DrawCanvas extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) => PluginDrawCanvas(
    size: size,
    store: store,
    scaleFactor: scaleFactor,
    currentToolTypeId: currentToolTypeId,
    isSelectionToolActive: isSelectionToolActive,
    isEraserToolActive: isEraserToolActive,
    watermarkPreviewListenable: watermarkPreviewListenable,
  );
}
