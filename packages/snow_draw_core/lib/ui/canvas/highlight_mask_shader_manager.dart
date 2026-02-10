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
/// Limited by the uniform array size (8 floats per highlight).
const int highlightMaskShaderLimit = 32;

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
    if (highlights.length > highlightMaskShaderLimit) {
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

    var idx = 0;

    // uResolution (vec2)
    shader
      ..setFloat(idx++, screenWidth)
      ..setFloat(idx++, screenHeight);

    // uMaskColor (vec4) — premultiplied alpha
    final color = maskConfig.maskColor;
    shader
      ..setFloat(idx++, color.r * effectiveAlpha)
      ..setFloat(idx++, color.g * effectiveAlpha)
      ..setFloat(idx++, color.b * effectiveAlpha)
      ..setFloat(idx++, effectiveAlpha);

    // uHighlightCount
    shader.setFloat(idx++, highlights.length.toDouble());

    // Pack each highlight into 8 floats.
    for (final element in highlights) {
      final data = element.data as HighlightData;
      final rect = element.rect;
      final inflate = data.strokeWidth / 2;

      // Convert world coordinates to screen coordinates.
      final cx = (rect.centerX + cameraPosition.dx / scale) * scale;
      final cy = (rect.centerY + cameraPosition.dy / scale) * scale;
      final hw = rect.width / 2 * scale;
      final hh = rect.height / 2 * scale;
      final inflateX = inflate * scale;
      final inflateY = inflate * scale;
      final shape = data.shape == HighlightShape.ellipse ? 1.0 : 0.0;

      shader
        ..setFloat(idx++, cx)
        ..setFloat(idx++, cy)
        ..setFloat(idx++, hw)
        ..setFloat(idx++, hh)
        ..setFloat(idx++, element.rotation)
        ..setFloat(idx++, inflateX)
        ..setFloat(idx++, inflateY)
        ..setFloat(idx++, shape);
    }

    // Zero-fill remaining slots so the shader reads deterministic
    // values (avoids undefined behaviour on some GPU drivers).
    final totalFloats = 7 + highlights.length * 8; // 7 header + 8 per highlight
    final maxFloats = 7 + highlightMaskShaderLimit * 8;
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
