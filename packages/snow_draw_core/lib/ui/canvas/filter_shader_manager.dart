import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../draw/services/log/log_service.dart';

final ModuleLogger _filterShaderLog = LogService.fallback.render;

/// Manages shader-backed image filters used by canvas filter elements.
class FilterShaderManager {
  FilterShaderManager._();

  static final instance = FilterShaderManager._();

  ui.FragmentProgram? _mosaicProgram;
  var _isLoadingMosaic = false;
  var _mosaicLoadFailed = false;

  /// Whether shader-backed image filters are supported on this backend.
  bool get isShaderFilterSupported => ui.ImageFilter.isShaderFilterSupported;

  /// Whether the mosaic shader program is ready.
  bool get isMosaicReady => _mosaicProgram != null;

  /// Preloads shader programs used for filter rendering.
  Future<void> load() async {
    await _loadMosaicProgram();
  }

  Future<void> _loadMosaicProgram() async {
    if (_mosaicProgram != null || _isLoadingMosaic || _mosaicLoadFailed) {
      return;
    }
    _isLoadingMosaic = true;
    try {
      _mosaicProgram = await ui.FragmentProgram.fromAsset(
        'packages/snow_draw_core/shaders/filter_mosaic.frag',
      );
    } on Exception catch (error, stackTrace) {
      _mosaicLoadFailed = true;
      _filterShaderLog.warning('Failed to load mosaic filter shader', {
        'error': error,
        'stackTrace': stackTrace,
      });
    } finally {
      _isLoadingMosaic = false;
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
  }) {
    final width = regionSize.width;
    final height = regionSize.height;
    if (width <= 0 || height <= 0) {
      return null;
    }

    final blockSize = resolveMosaicBlockSize(
      strength: strength,
      regionSize: regionSize,
    );

    final shaderFilter = _createShaderBackedMosaicFilter(
      regionWidth: width,
      regionHeight: height,
      regionOffset: regionOffset,
      blockSize: blockSize,
    );
    if (shaderFilter != null) {
      return shaderFilter;
    }

    return _createMatrixMosaicFilter(
      blockSize: blockSize,
      regionOffset: regionOffset,
    );
  }

  ui.ImageFilter? _createShaderBackedMosaicFilter({
    required double regionWidth,
    required double regionHeight,
    required Offset regionOffset,
    required double blockSize,
  }) {
    if (!isShaderFilterSupported || _mosaicProgram == null) {
      return null;
    }

    final shader = _mosaicProgram!.fragmentShader();
    var index = 0;
    shader
      ..setFloat(index++, regionWidth)
      ..setFloat(index++, regionHeight)
      ..setFloat(index++, blockSize)
      ..setFloat(index++, regionOffset.dx)
      ..setFloat(index++, regionOffset.dy);

    try {
      return ui.ImageFilter.shader(shader);
    } on Exception {
      return null;
    }
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
