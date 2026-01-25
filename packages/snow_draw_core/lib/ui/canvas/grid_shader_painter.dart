import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';

/// Manages the grid fragment shader for GPU-accelerated grid rendering.
///
/// This class handles shader loading, caching, and provides a method to
/// paint the grid using the shader. The shader renders the entire grid
/// in a single GPU draw call, providing maximum performance.
class GridShaderManager {
  GridShaderManager._();

  static final instance = GridShaderManager._();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  var _isLoading = false;
  var _loadFailed = false;

  /// Whether the shader is ready to use.
  bool get isReady => _shader != null;

  /// Whether shader loading failed.
  bool get loadFailed => _loadFailed;

  /// Loads the grid shader asynchronously.
  ///
  /// This should be called early in the app lifecycle. The shader will be
  /// cached after the first successful load.
  Future<void> load() async {
    if (_shader != null || _isLoading || _loadFailed) {
      return;
    }

    _isLoading = true;
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/grid.frag',
      );
      _shader = _program!.fragmentShader();
    } on Exception catch (e) {
      _loadFailed = true;
      debugPrint('Failed to load grid shader: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Paints the grid using the fragment shader.
  ///
  /// Returns true if the shader was used, false if fallback rendering
  /// should be used instead.
  bool paintGrid({
    required Canvas canvas,
    required Size size,
    required Offset cameraPosition,
    required double scale,
    required GridConfig config,
    required double minorOpacityRatio,
    required int majorEveryFactor,
  }) {
    if (_shader == null) {
      return false;
    }

    final shader = _shader!;
    final effectiveScale = scale == 0 ? 1.0 : scale;

    // Calculate colors with opacity
    final minorColor = config.lineColor.withValues(
      alpha: config.lineOpacity * minorOpacityRatio * 0.5,
    );
    final majorColor = config.lineColor.withValues(
      alpha: config.majorLineOpacity,
    );

    // Set uniforms (order must match shader declaration)
    var idx = 0;

    // uResolution (vec2)
    shader
      ..setFloat(idx++, size.width)
      ..setFloat(idx++, size.height)
      // uCameraPosition (vec2)
      ..setFloat(idx++, cameraPosition.dx)
      ..setFloat(idx++, cameraPosition.dy)
      // uScale (float)
      ..setFloat(idx++, effectiveScale)
      // uGridSize (float)
      ..setFloat(idx++, config.size)
      // uMajorEvery (float)
      ..setFloat(idx++, majorEveryFactor.toDouble())
      // uLineWidth (float) - minor line width in screen pixels
      ..setFloat(idx++, config.lineWidth)
      // uMajorLineWidth (float) - major line width (1.5x thicker)
      ..setFloat(idx++, config.lineWidth * 1.5);

    // uMinorColor (vec4) - premultiplied alpha
    final minorAlpha = minorColor.a;
    shader
      ..setFloat(idx++, minorColor.r * minorAlpha)
      ..setFloat(idx++, minorColor.g * minorAlpha)
      ..setFloat(idx++, minorColor.b * minorAlpha)
      ..setFloat(idx++, minorAlpha);

    // uMajorColor (vec4) - premultiplied alpha
    final majorAlpha = majorColor.a;
    shader
      ..setFloat(idx++, majorColor.r * majorAlpha)
      ..setFloat(idx++, majorColor.g * majorAlpha)
      ..setFloat(idx++, majorColor.b * majorAlpha)
      ..setFloat(idx++, majorAlpha);

    // Draw the shader as a full-screen rect
    final paint = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );

    return true;
  }

  /// Disposes of the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _program = null;
  }
}
