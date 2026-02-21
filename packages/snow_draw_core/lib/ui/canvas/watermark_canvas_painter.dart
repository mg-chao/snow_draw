import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import 'watermark_painter.dart';
import 'watermark_visibility.dart';

/// Snapshot consumed by the watermark overlay painter.
@immutable
class WatermarkCanvasLayerState {
  const WatermarkCanvasLayerState({required this.config});

  /// Watermark settings snapshot.
  final WatermarkConfig config;

  /// Whether the watermark produces visible pixels.
  bool get isVisible => isWatermarkVisible(config);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkCanvasLayerState && other.config == config;

  @override
  int get hashCode => config.hashCode;
}

/// Mutable state holder that repaints the watermark layer on demand.
class WatermarkCanvasLayerController
    extends ValueNotifier<WatermarkCanvasLayerState> {
  WatermarkCanvasLayerController({
    required WatermarkCanvasLayerState initialState,
  }) : super(initialState);

  /// Current snapshot used by the painter.
  WatermarkCanvasLayerState get state => value;

  /// Replace the current snapshot and request repaint when it changes.
  void update(WatermarkCanvasLayerState nextState) {
    if (value == nextState) {
      return;
    }
    value = nextState;
  }
}

/// Paints the watermark overlay on a dedicated repaint layer.
///
/// Keeping watermark rendering separate from static/dynamic scene painters
/// lets watermark edits repaint only this overlay instead of re-rendering
/// the full element scene.
@immutable
class WatermarkCanvasPainter extends CustomPainter {
  const WatermarkCanvasPainter({required this.controller})
    : super(repaint: controller);

  /// Layer controller driving repaint updates.
  final WatermarkCanvasLayerController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final config = controller.state.config;
    if (!isWatermarkVisible(config)) {
      return;
    }

    paintWatermark(canvas: canvas, viewportSize: size, config: config);
  }

  @override
  bool shouldRepaint(covariant WatermarkCanvasPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
