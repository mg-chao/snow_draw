import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/services/log/log_service.dart';

final ModuleLogger _gridShaderLog = LogService.fallback.render;

/// Manages the grid fragment shader for GPU-accelerated grid rendering.
///
/// This class handles shader loading, caching, and provides a method to
/// paint the grid using the shader. The shader renders the entire grid
/// in a single GPU draw call, providing maximum performance.
class GridShaderManager {
  GridShaderManager._();

  static final instance = GridShaderManager._();

  ui.FragmentShader? _shader;
  final _paint = Paint();
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
      _shader = (await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/grid.frag',
      )).fragmentShader();
    } on Exception catch (error, stackTrace) {
      _loadFailed = true;
      _gridShaderLog.warning('Failed to load grid shader', {
        'error': error,
        'stackTrace': stackTrace,
      });
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
    final shader = _shader;
    if (shader == null) {
      return false;
    }

    final minorColor = config.lineColor.withValues(
      alpha: config.lineOpacity * minorOpacityRatio * 0.5,
    );
    final majorColor = config.lineColor.withValues(
      alpha: config.majorLineOpacity,
    );

    var idx = 0;
    shader
      ..setFloat(idx++, size.width)
      ..setFloat(idx++, size.height)
      ..setFloat(idx++, cameraPosition.dx)
      ..setFloat(idx++, cameraPosition.dy)
      ..setFloat(idx++, scale)
      ..setFloat(idx++, config.size)
      ..setFloat(idx++, majorEveryFactor.toDouble())
      ..setFloat(idx++, config.lineWidth)
      ..setFloat(idx++, config.lineWidth * 1.5);

    idx = _setPremultipliedColor(shader, idx, minorColor);
    _setPremultipliedColor(shader, idx, majorColor);

    _paint.shader = shader;
    canvas.drawRect(Offset.zero & size, _paint);

    return true;
  }

  int _setPremultipliedColor(ui.FragmentShader shader, int start, Color color) {
    final alpha = color.a;
    shader
      ..setFloat(start++, color.r * alpha)
      ..setFloat(start++, color.g * alpha)
      ..setFloat(start++, color.b * alpha)
      ..setFloat(start++, alpha);
    return start;
  }

  /// Disposes of the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
  }
}
