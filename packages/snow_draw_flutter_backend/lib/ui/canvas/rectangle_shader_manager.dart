import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

/// Manages the rectangle fragment shader for GPU-accelerated rendering.
///
/// This class handles shader loading and provides a method to paint rectangles
/// using the shader. The shader renders the entire rectangle (fill + stroke
/// with all patterns) in a single GPU draw call.
///
/// On web backends, sharing a single mutable [ui.FragmentShader] across
/// multiple rectangle draw calls in one frame can cause uniform values from
/// later calls to overwrite earlier draws. To keep rendering deterministic,
/// web uses a bounded per-element shader cache.
class RectangleShaderManager {
  RectangleShaderManager._();

  static final instance = RectangleShaderManager._();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _sharedShader;
  var _isLoading = false;
  var _loadFailed = false;

  /// Reusable paint for non-web shader draw calls.
  final _sharedPaint = Paint();

  /// Bounded web shader cache keyed by element id.
  static const _webShaderCacheEntries = 512;
  final _webShaderCache = LruCache<String, ui.FragmentShader>(
    maxEntries: _webShaderCacheEntries,
    onEvict: (shader) => shader.dispose(),
  );

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
      _program = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/rectangle.frag',
      );
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
    required String elementId,
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
    final program = _program;
    if (program == null) {
      return false;
    }

    final shader = _resolveShader(program, elementId);
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

    // uFillColor (vec4), premultiplied alpha.
    idx = _setPremultipliedColor(shader, idx, fillColor);
    shader
      // uFillLineWidth (float)
      ..setFloat(idx++, fillLineWidth)
      // uFillLineSpacing (float)
      ..setFloat(idx++, fillLineSpacing)
      // uStrokeStyle (float, interpreted as int in shader)
      ..setFloat(idx++, strokeStyle.index.toDouble());

    // uStrokeColor (vec4), premultiplied alpha.
    idx = _setPremultipliedColor(shader, idx, strokeColor);
    shader
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

    final paint = _resolvePaint(shader);

    // Calculate tight bounding box for rotated rectangle.
    // For rotation angle r, the bounding box dimensions are:
    // width = |w * cos(r)| + |h * sin(r)|
    // height = |w * sin(r)| + |h * cos(r)|
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

    canvas.drawRect(boundingRect, paint);
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

  ui.FragmentShader _resolveShader(
    ui.FragmentProgram program,
    String elementId,
  ) {
    if (kIsWeb) {
      return _webShaderCache.getOrCreate(elementId, program.fragmentShader);
    }
    return _sharedShader ??= program.fragmentShader();
  }

  Paint _resolvePaint(ui.FragmentShader shader) =>
      (kIsWeb
            // Keep paint instances isolated on web to avoid mutable-state
            // carry-over when multiple draw commands are queued in one frame.
            ? Paint()
            : _sharedPaint)
        ..shader = shader;

  /// Disposes of the shader resources.
  void dispose() {
    _sharedShader?.dispose();
    _sharedShader = null;
    _webShaderCache.clear();
    _program = null;
  }
}
