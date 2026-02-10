import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/config/draw_config.dart';
import '../../draw/elements/types/highlight/highlight_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/services/log/log_service.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';

final ModuleLogger _log = LogService.fallback.render;

/// Maximum highlights the shader can process in a single pass.
///
/// Limited by the uniform array size (9 floats per highlight).
const highlightMaskShaderLimit = 32;

/// Number of uniform floats per highlight.
///
/// Layout: centerX, centerY, halfWidth, halfHeight, cosRot, sinRot,
///         inflateX, inflateY, shape.
const _floatsPerHighlight = 9;

/// Number of header uniforms before the highlight array.
///
/// uResolution (2) + uMaskColor (4) + uHighlightCount (1) + uBounds (4).
const _headerFloats = 11;

/// GPU-accelerated highlight mask rendering.
///
/// Replaces the `saveLayer` + `BlendMode.clear` approach with a single
/// fragment shader draw call, eliminating the offscreen buffer allocation.
class HighlightMaskShaderManager {
  HighlightMaskShaderManager._();

  static final instance = HighlightMaskShaderManager._();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
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
      _program = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/highlight_mask.frag',
      );
      _shader = _program!.fragmentShader();
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
    if (_shader == null) {
      return false;
    }

    final shader = _shader!;
    final effectiveAlpha = (maskConfig.maskColor.a * maskConfig.maskOpacity)
        .clamp(0.0, 1.0);
    if (effectiveAlpha <= 0) {
      return true;
    }

    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;
    final screenWidth = viewportRect.width * scale;
    final screenHeight = viewportRect.height * scale;

    // Cull highlights that are entirely off-screen and collect visible
    // ones.  This avoids sending invisible highlights to the GPU and
    // tightens the combined AABB used for the early-out test.
    final visible = _cullHighlights(
      highlights: highlights,
      viewportRect: viewportRect,
      scale: scale,
      cameraPosition: cameraPosition,
    );

    if (visible.length > highlightMaskShaderLimit) {
      return false;
    }

    var idx = 0;

    // uResolution (vec2)
    shader
      ..setFloat(idx++, screenWidth)
      ..setFloat(idx++, screenHeight);

    // uMaskColor (vec4) — premultiplied alpha, then uHighlightCount.
    final color = maskConfig.maskColor;
    shader
      ..setFloat(idx++, color.r * effectiveAlpha)
      ..setFloat(idx++, color.g * effectiveAlpha)
      ..setFloat(idx++, color.b * effectiveAlpha)
      ..setFloat(idx++, effectiveAlpha)
      ..setFloat(idx++, visible.length.toDouble());

    // uBounds (vec4) — combined screen-space AABB with AA margin.
    // Computed on the Dart side so the shader can early-out for
    // fragments that are clearly outside all highlights.
    if (visible.isEmpty) {
      shader
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0)
        ..setFloat(idx++, 0);
    } else {
      var bMinX = visible.first.screenMinX;
      var bMinY = visible.first.screenMinY;
      var bMaxX = visible.first.screenMaxX;
      var bMaxY = visible.first.screenMaxY;
      for (var i = 1; i < visible.length; i++) {
        final h = visible[i];
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
    }

    // Pack each visible highlight into 9 floats.
    for (final h in visible) {
      shader
        ..setFloat(idx++, h.cx)
        ..setFloat(idx++, h.cy)
        ..setFloat(idx++, h.hw)
        ..setFloat(idx++, h.hh)
        ..setFloat(idx++, h.cosR)
        ..setFloat(idx++, h.sinR)
        ..setFloat(idx++, h.inflateX)
        ..setFloat(idx++, h.inflateY)
        ..setFloat(idx++, h.shape);
    }

    // Zero-fill remaining slots so the shader reads deterministic
    // values (avoids undefined behaviour on some GPU drivers).
    final totalFloats =
        _headerFloats + visible.length * _floatsPerHighlight;
    const maxFloats =
        _headerFloats + highlightMaskShaderLimit * _floatsPerHighlight;
    for (var i = totalFloats; i < maxFloats; i++) {
      shader.setFloat(i, 0);
    }

    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, screenWidth, screenHeight), paint);

    return true;
  }

  /// Disposes of the shader resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _program = null;
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
/// Precomputes cos/sin on the Dart side so the shader avoids
/// per-fragment trigonometry.  Also computes a tight screen-space
/// AABB per highlight for the combined early-out bounds.
List<_VisibleHighlight> _cullHighlights({
  required List<ElementState> highlights,
  required DrawRect viewportRect,
  required double scale,
  required Offset cameraPosition,
}) {
  final screenW = viewportRect.width * scale;
  final screenH = viewportRect.height * scale;
  const aaMargin = 1.0;

  final result = <_VisibleHighlight>[];
  for (final element in highlights) {
    final data = element.data as HighlightData;
    final rect = element.rect;
    final inflate = data.strokeWidth / 2;

    final cx = (rect.centerX + cameraPosition.dx / scale) * scale;
    final cy = (rect.centerY + cameraPosition.dy / scale) * scale;
    final hw = rect.width / 2 * scale;
    final hh = rect.height / 2 * scale;
    final inflateX = inflate * scale;
    final inflateY = inflate * scale;

    // Compute screen-space AABB accounting for rotation.
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

    // Skip highlights entirely outside the screen.
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
