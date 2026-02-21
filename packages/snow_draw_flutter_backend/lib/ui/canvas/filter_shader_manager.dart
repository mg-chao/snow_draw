import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:snow_draw_core/draw/services/log/log_service.dart';

final ModuleLogger _filterShaderLog = LogService.fallback.render;
const _mosaicShaderAssetPath =
    'packages/snow_draw_core/shaders/filter_mosaic.frag';

/// Manages shader-backed image filters used by canvas filter elements.
class FilterShaderManager {
  FilterShaderManager._();

  static final instance = FilterShaderManager._();

  ui.FragmentProgram? _mosaicProgram;
  Future<void>? _mosaicLoadTask;

  /// Whether shader-backed image filters are supported on this backend.
  bool get isShaderFilterSupported => ui.ImageFilter.isShaderFilterSupported;

  /// Whether the mosaic shader program is ready.
  bool get isMosaicReady => _mosaicProgram != null;

  /// Whether the backend can render mosaic using a fragment shader.
  bool get canUseShaderBackedMosaic => isShaderFilterSupported && isMosaicReady;

  /// Preloads shader programs used for filter rendering.
  Future<void> load() => _mosaicLoadTask ??= _loadMosaicProgram();

  Future<void> _loadMosaicProgram() async {
    if (_mosaicProgram != null) {
      return;
    }

    try {
      _mosaicProgram = await ui.FragmentProgram.fromAsset(
        _mosaicShaderAssetPath,
      );
    } on Exception catch (error, stackTrace) {
      _filterShaderLog.warning('Failed to load mosaic filter shader', {
        'error': error,
        'stackTrace': stackTrace,
      });
    }
  }

  /// Resolves the mosaic block size in logical pixels for a region.
  ///
  /// Larger strength values produce larger pixel blocks.
  double resolveMosaicBlockSize({
    required double strength,
    required Size regionSize,
  }) {
    final width = regionSize.width;
    final height = regionSize.height;
    if (width <= 0 || height <= 0) {
      return 1;
    }

    final normalizedStrength = (strength / 3).clamp(0.0, 1.0);
    final shortestSide = width < height ? width : height;
    const minBlockSize = 2.0;
    final maxBlockSize = (shortestSide / 8).clamp(4.0, 64.0);
    return minBlockSize + ((maxBlockSize - minBlockSize) * normalizedStrength);
  }

  /// Creates an `ImageFilter.shader` for mosaic if shader filtering is
  /// available.
  ///
  /// Falls back to a matrix-based pixelation filter on backends that do not
  /// support shader filters.
  ui.ImageFilter? createMosaicFilter({
    required double strength,
    required Size regionSize,
    required Offset regionOffset,
    double? blockSize,
  }) {
    final width = regionSize.width;
    final height = regionSize.height;
    if (width <= 0 || height <= 0) {
      return null;
    }

    final resolvedBlockSize = _resolveValidBlockSize(
      blockSize ??
          resolveMosaicBlockSize(strength: strength, regionSize: regionSize),
    );

    if (canUseShaderBackedMosaic) {
      final shader = _mosaicProgram!.fragmentShader();
      var index = 0;
      shader
        ..setFloat(index++, width)
        ..setFloat(index++, height)
        ..setFloat(index++, resolvedBlockSize)
        ..setFloat(index++, regionOffset.dx)
        ..setFloat(index++, regionOffset.dy);

      try {
        return ui.ImageFilter.shader(shader);
      } on Exception catch (error, stackTrace) {
        _filterShaderLog.warning('Failed to create mosaic shader filter', {
          'error': error,
          'stackTrace': stackTrace,
        });
      }
    }

    return _createMatrixMosaicFilter(
      blockSize: resolvedBlockSize,
      regionOffset: regionOffset,
    );
  }

  double _resolveValidBlockSize(double value) {
    if (value.isFinite && value > 0) {
      return value;
    }
    return 1;
  }

  ui.ImageFilter _createMatrixMosaicFilter({
    required double blockSize,
    required Offset regionOffset,
  }) => ui.ImageFilter.compose(
    outer: ui.ImageFilter.matrix(
      _buildScaleMatrix(
        scaleX: blockSize,
        scaleY: blockSize,
        pivotX: regionOffset.dx,
        pivotY: regionOffset.dy,
      ),
      filterQuality: FilterQuality.none,
    ),
    inner: ui.ImageFilter.matrix(
      _buildScaleMatrix(
        scaleX: 1 / blockSize,
        scaleY: 1 / blockSize,
        pivotX: regionOffset.dx,
        pivotY: regionOffset.dy,
      ),
      filterQuality: FilterQuality.none,
    ),
  );

  Float64List _buildScaleMatrix({
    required double scaleX,
    required double scaleY,
    required double pivotX,
    required double pivotY,
  }) => Float64List.fromList(<double>[
    scaleX,
    0,
    0,
    0,
    0,
    scaleY,
    0,
    0,
    0,
    0,
    1,
    0,
    pivotX * (1 - scaleX),
    pivotY * (1 - scaleY),
    0,
    1,
  ]);
}
