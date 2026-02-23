import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import '../../extensions/draw_color_extensions.dart';

final ModuleLogger _log = LogService.fallback.render;

/// Maximum highlights the shader can process in a single pass.
///
/// Limited by the uniform array size (3 vec4s per highlight).
const highlightMaskShaderLimit = 32;

/// Number of floats per vec4 uniform.
const _vec4Floats = 4;

/// Number of header uniforms before the highlight arrays.
///
/// uResolution (2) + uMaskColor (4) + uHighlightCount (1) + uBounds (4).
const _headerFloats = 11;

/// Offset where uHiA[32] starts (right after the header).
const int _hiAOffset = _headerFloats;

/// Offset where uHiB[32] starts (after uHiA).
const int _hiBOffset = _hiAOffset + highlightMaskShaderLimit * _vec4Floats;

/// Offset where uHiC[32] starts (after uHiB).
const int _hiCOffset = _hiBOffset + highlightMaskShaderLimit * _vec4Floats;

/// GPU-accelerated highlight mask rendering.
///
/// Replaces the `saveLayer` + `BlendMode.clear` approach with shader draws,
/// avoiding CPU path-combine work during high-frequency interactions.
class HighlightMaskShaderManager {
  HighlightMaskShaderManager._();

  static final instance = HighlightMaskShaderManager._();

  ui.FragmentShader? _shader;
  final _paint = Paint();
  var _isLoading = false;
  var _loadFailed = false;

  /// Whether the shader is ready to use.
  bool get isReady => _shader != null;

  /// Whether shader loading failed.
  bool get loadFailed => _loadFailed;

  /// Loads the highlight mask shader asynchronously.
  Future<void> load() async {
    if (_shader != null || _isLoading || _loadFailed) {
      return;
    }

    _isLoading = true;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_flutter_backend/shaders/highlight_mask.frag',
      );
      _shader = program.fragmentShader();
    } on Exception catch (error, stackTrace) {
      _loadFailed = true;
      _log.warning('Failed to load highlight mask shader', {
        'error': error,
        'stackTrace': stackTrace,
      });
    } finally {
      _isLoading = false;
    }
  }

  /// Paints the highlight mask using the fragment shader.
  ///
  /// Returns `true` if the shader was used, `false` if the caller
  /// should fall back to the CPU-based `saveLayer` approach.
  bool paintMask({
    required Canvas canvas,
    required List<ElementState> highlights,
    required DrawRect viewportRect,
    required HighlightMaskConfig maskConfig,
    required double scaleFactor,
    required Offset cameraPosition,
  }) {
    final shader = _shader;
    if (shader == null) {
      return false;
    }

    final effectiveAlpha = (maskConfig.maskColor.a * maskConfig.maskOpacity)
        .clamp(0.0, 1.0);
    if (effectiveAlpha <= 0) {
      return true;
    }

    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;
    final screenWidth = viewportRect.width * scale;
    final screenHeight = viewportRect.height * scale;
    final screenRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);

    final visible = _cullHighlights(
      highlights: highlights,
      viewportRect: viewportRect,
      scale: scale,
      cameraPosition: cameraPosition,
    );

    if (visible.length > highlightMaskShaderLimit) {
      return false;
    }

    _configureShader(
      shader: shader,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      maskColor: maskConfig.maskColor.toFlutterColor(),
      alpha: effectiveAlpha,
      highlights: visible,
    );
    _paint.shader = shader;
    canvas.drawRect(screenRect, _paint);
    return true;
  }

  void _configureShader({
    required ui.FragmentShader shader,
    required double screenWidth,
    required double screenHeight,
    required Color maskColor,
    required double alpha,
    required List<_VisibleHighlight> highlights,
  }) {
    final count = highlights.length;
    var idx = 0;
    shader
      ..setFloat(idx++, screenWidth)
      ..setFloat(idx++, screenHeight)
      ..setFloat(idx++, maskColor.r * alpha)
      ..setFloat(idx++, maskColor.g * alpha)
      ..setFloat(idx++, maskColor.b * alpha)
      ..setFloat(idx++, alpha)
      ..setFloat(idx++, count.toDouble());

    if (highlights.isEmpty) {
      shader
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0);
      return;
    }

    var bMinX = highlights.first.screenMinX;
    var bMinY = highlights.first.screenMinY;
    var bMaxX = highlights.first.screenMaxX;
    var bMaxY = highlights.first.screenMaxY;
    for (var i = 1; i < count; i++) {
      final h = highlights[i];
      if (h.screenMinX < bMinX) {
        bMinX = h.screenMinX;
      }
      if (h.screenMinY < bMinY) {
        bMinY = h.screenMinY;
      }
      if (h.screenMaxX > bMaxX) {
        bMaxX = h.screenMaxX;
      }
      if (h.screenMaxY > bMaxY) {
        bMaxY = h.screenMaxY;
      }
    }
    shader
      ..setFloat(idx++, bMinX)
      ..setFloat(idx++, bMinY)
      ..setFloat(idx++, bMaxX)
      ..setFloat(idx++, bMaxY);

    for (var slot = 0; slot < count; slot++) {
      final h = highlights[slot];
      final aBase = _hiAOffset + slot * _vec4Floats;
      shader
        ..setFloat(aBase, h.cx)
        ..setFloat(aBase + 1, h.cy)
        ..setFloat(aBase + 2, h.hw)
        ..setFloat(aBase + 3, h.hh);

      final bBase = _hiBOffset + slot * _vec4Floats;
      shader
        ..setFloat(bBase, h.cosR)
        ..setFloat(bBase + 1, h.sinR)
        ..setFloat(bBase + 2, h.inflateX)
        ..setFloat(bBase + 3, h.inflateY);

      final cBase = _hiCOffset + slot * _vec4Floats;
      shader
        ..setFloat(cBase, h.shape)
        ..setFloat(cBase + 1, 0)
        ..setFloat(cBase + 2, 0)
        ..setFloat(cBase + 3, 0);
    }
  }

  /// Disposes of the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
  }
}

/// Pre-computed screen-space data for a single highlight.
class _VisibleHighlight {
  const _VisibleHighlight({
    required this.cx,
    required this.cy,
    required this.hw,
    required this.hh,
    required this.cosR,
    required this.sinR,
    required this.inflateX,
    required this.inflateY,
    required this.shape,
    required this.screenMinX,
    required this.screenMinY,
    required this.screenMaxX,
    required this.screenMaxY,
  });

  final double cx;
  final double cy;
  final double hw;
  final double hh;
  final double cosR;
  final double sinR;
  final double inflateX;
  final double inflateY;
  final double shape;

  /// Screen-space AABB (with AA margin) for the combined bounds.
  final double screenMinX;
  final double screenMinY;
  final double screenMaxX;
  final double screenMaxY;
}

/// Culls off-screen highlights and precomputes screen-space data.
///
/// Precomputes cos/sin on the Dart side so the shader avoids per-fragment
/// trigonometry. Also computes a tight screen-space AABB per highlight.
List<_VisibleHighlight> _cullHighlights({
  required List<ElementState> highlights,
  required DrawRect viewportRect,
  required double scale,
  required Offset cameraPosition,
}) {
  final result = <_VisibleHighlight>[];
  final screenW = viewportRect.width * scale;
  final screenH = viewportRect.height * scale;
  const aaMargin = 1.0;
  for (final element in highlights) {
    final data = element.data as HighlightData;
    final rect = element.rect;
    final inflate = data.strokeWidth / 2;

    final cx = (rect.centerX * scale) + cameraPosition.dx;
    final cy = (rect.centerY * scale) + cameraPosition.dy;
    final hw = rect.width * scale / 2;
    final hh = rect.height * scale / 2;
    final inflateX = inflate * scale;
    final inflateY = inflate * scale;

    final rotation = element.rotation;
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);
    final absCos = cosR.abs();
    final absSin = sinR.abs();
    final expandedHW = hw + inflateX;
    final expandedHH = hh + inflateY;
    final rotHW = expandedHW * absCos + expandedHH * absSin;
    final rotHH = expandedHW * absSin + expandedHH * absCos;

    final minX = cx - rotHW - aaMargin;
    final minY = cy - rotHH - aaMargin;
    final maxX = cx + rotHW + aaMargin;
    final maxY = cy + rotHH + aaMargin;

    if (maxX < 0 || minX > screenW || maxY < 0 || minY > screenH) {
      continue;
    }

    result.add(
      _VisibleHighlight(
        cx: cx,
        cy: cy,
        hw: hw,
        hh: hh,
        cosR: cosR,
        sinR: sinR,
        inflateX: inflateX,
        inflateY: inflateY,
        shape: data.shape == HighlightShape.ellipse ? 1.0 : 0.0,
        screenMinX: minX,
        screenMinY: minY,
        screenMaxX: maxX,
        screenMaxY: maxY,
      ),
    );
  }
  return result;
}
