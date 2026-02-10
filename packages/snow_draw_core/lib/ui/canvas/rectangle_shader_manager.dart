import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/types/element_style.dart';

/// Manages the rectangle fragment shader for GPU-accelerated rendering.
///
/// This class handles shader loading and provides a method to paint rectangles
/// using the shader. The shader renders the entire rectangle (fill + stroke
/// with all patterns) in a single GPU draw call.
///
/// A single [ui.FragmentShader] and [Paint] instance are reused across
/// draw calls to avoid per-rectangle allocations. This is safe because
/// `setFloat` overwrites uniforms in place and `Canvas.drawRect` consumes
/// the shader state at call time.
class RectangleShaderManager {
  RectangleShaderManager._();

  static final instance = RectangleShaderManager._();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  var _isLoading = false;
  var _loadFailed = false;

  /// Reusable paint for shader draw calls.
  final _paint = Paint();

  /// Whether the shader is ready to use.
  bool get isReady => _program != null;

  /// Whether shader loading failed.
  bool get loadFailed => _loadFailed;

  /// Loads the rectangle shader asynchronously.
  ///
  /// This should be called early in the app lifecycle. The program will be
  /// cached after the first successful load.
  Future<void> load() async {
    if (_program != null || _isLoading || _loadFailed) {
      return;
    }

    _isLoading = true;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/rectangle.frag',
      );
      _program = program;
      _shader = program.fragmentShader();
    } on Exception catch (e) {
      _loadFailed = true;
      debugPrint('Failed to load rectangle shader: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Paints a rectangle using the fragment shader.
  ///
  /// Returns true if the shader was used, false if fallback rendering
  /// should be used instead.
  bool paintRectangle({
    required Canvas canvas,
    required Offset center,
    required Size size,
    required double rotation,
    required double cornerRadius,
    required FillStyle fillStyle,
    required Color fillColor,
    required double fillLineWidth,
    required double fillLineSpacing,
    required StrokeStyle strokeStyle,
    required Color strokeColor,
    required double strokeWidth,
    required double dashLength,
    required double gapLength,
    required double dotSpacing,
    required double dotRadius,
    required double aaWidth,
  }) {
    final shader = _shader;
    if (shader == null) {
      return false;
    }

    // Reuse the cached shader instance — setFloat overwrites uniforms
    // in place and Canvas.drawRect snapshots the state at call time.
    var idx = 0;

    // uResolution (vec2)
    shader
      ..setFloat(idx++, size.width)
      ..setFloat(idx++, size.height)
      // uCenter (vec2)
      ..setFloat(idx++, center.dx)
      ..setFloat(idx++, center.dy)
      // uRotation (float)
      ..setFloat(idx++, rotation)
      // uCornerRadius (float)
      ..setFloat(idx++, cornerRadius)
      // uFillStyle (float, interpreted as int in shader)
      ..setFloat(idx++, fillStyle.index.toDouble());

    // uFillColor (vec4) — premultiplied alpha
    final fillAlpha = fillColor.a;
    shader
      ..setFloat(idx++, fillColor.r * fillAlpha)
      ..setFloat(idx++, fillColor.g * fillAlpha)
      ..setFloat(idx++, fillColor.b * fillAlpha)
      ..setFloat(idx++, fillAlpha)
      // uFillLineWidth (float)
      ..setFloat(idx++, fillLineWidth)
      // uFillLineSpacing (float)
      ..setFloat(idx++, fillLineSpacing)
      // uStrokeStyle (float, interpreted as int in shader)
      ..setFloat(idx++, strokeStyle.index.toDouble());

    // uStrokeColor (vec4) — premultiplied alpha
    final strokeAlpha = strokeColor.a;
    shader
      ..setFloat(idx++, strokeColor.r * strokeAlpha)
      ..setFloat(idx++, strokeColor.g * strokeAlpha)
      ..setFloat(idx++, strokeColor.b * strokeAlpha)
      ..setFloat(idx++, strokeAlpha)
      // uStrokeWidth (float)
      ..setFloat(idx++, strokeWidth)
      // uDashLength (float)
      ..setFloat(idx++, dashLength)
      // uGapLength (float)
      ..setFloat(idx++, gapLength)
      // uDotSpacing (float)
      ..setFloat(idx++, dotSpacing)
      // uDotRadius (float)
      ..setFloat(idx++, dotRadius)
      // uAAWidth (float)
      ..setFloat(idx++, aaWidth);

    // Reuse paint — just swap the shader reference.
    _paint.shader = shader;

    // Calculate tight bounding box for rotated rectangle.
    // For rotation angle θ, the bounding box dimensions are:
    // width = |w·cos(θ)| + |h·sin(θ)|
    // height = |w·sin(θ)| + |h·cos(θ)|
    final cosR = math.cos(rotation).abs();
    final sinR = math.sin(rotation).abs();
    final rotatedWidth = size.width * cosR + size.height * sinR;
    final rotatedHeight = size.width * sinR + size.height * cosR;
    final padding = strokeWidth + aaWidth * 2;
    final boundingRect = Rect.fromCenter(
      center: center,
      width: rotatedWidth + padding,
      height: rotatedHeight + padding,
    );

    canvas.drawRect(boundingRect, _paint);
    return true;
  }

  /// Disposes of the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _program = null;
  }
}
