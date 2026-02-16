import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/models/camera_state.dart';
import 'watermark_painter.dart';

/// Paints the watermark overlay on a dedicated repaint layer.
///
/// Keeping watermark rendering separate from static/dynamic scene painters
/// lets watermark edits repaint only this overlay instead of re-rendering
/// the full element scene.
@immutable
class WatermarkCanvasPainter extends CustomPainter {
  const WatermarkCanvasPainter({
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

  @override
  void paint(Canvas canvas, Size size) {
    paintWatermark(
      canvas: canvas,
      viewportSize: size,
      config: config,
      scaleFactor: scaleFactor,
      cameraPosition: Offset(camera.position.x, camera.position.y),
    );
  }

  @override
  bool shouldRepaint(covariant WatermarkCanvasPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.scaleFactor != scaleFactor ||
      oldDelegate.config != config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkCanvasPainter &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor &&
          other.config == config;

  @override
  int get hashCode => Object.hash(camera, scaleFactor, config);
}
