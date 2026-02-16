import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/models/camera_state.dart';
import 'watermark_painter.dart';
import 'watermark_visibility.dart';

/// Snapshot consumed by the watermark overlay painter.
@immutable
class WatermarkCanvasLayerState {
  const WatermarkCanvasLayerState({
    required this.camera,
    required this.scaleFactor,
    required this.config,
  });

  /// Current camera transform used by the canvas.
  final CameraState camera;

  /// Effective canvas scale factor.
  final double scaleFactor;

  /// Watermark settings snapshot.
  final WatermarkConfig config;

  /// Whether the watermark produces visible pixels.
  bool get isVisible => isWatermarkVisible(config);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkCanvasLayerState &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor &&
          other.config == config;

  @override
  int get hashCode => Object.hash(camera, scaleFactor, config);
}

/// Mutable state holder that repaints the watermark layer on demand.
class WatermarkCanvasLayerController extends ChangeNotifier {
  WatermarkCanvasLayerController({
    required WatermarkCanvasLayerState initialState,
  }) : _state = initialState;

  WatermarkCanvasLayerState _state;

  /// Current snapshot used by the painter.
  WatermarkCanvasLayerState get state => _state;

  /// Replace the current snapshot and request repaint when it changes.
  void update(WatermarkCanvasLayerState nextState) {
    if (_state == nextState) {
      return;
    }
    _state = nextState;
    notifyListeners();
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
    final state = controller.state;
    if (!state.isVisible) {
      return;
    }

    paintWatermark(
      canvas: canvas,
      viewportSize: size,
      config: state.config,
      scaleFactor: state.scaleFactor,
      cameraPosition: Offset(state.camera.position.x, state.camera.position.y),
    );
  }

  @override
  bool shouldRepaint(covariant WatermarkCanvasPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
