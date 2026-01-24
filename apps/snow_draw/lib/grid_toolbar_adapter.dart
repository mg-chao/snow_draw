import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';

class GridToolbarAdapter {
  GridToolbarAdapter({required DrawStore store}) : _store = store {
    _config = _store.config;
    _enabledNotifier = ValueNotifier<bool>(_config.grid.enabled);
    _sizeNotifier = ValueNotifier<double>(_config.grid.size);
    _configSubscription = _store.configStream.listen(_handleConfigChange);
  }

  final DrawStore _store;
  late DrawConfig _config;
  late final ValueNotifier<bool> _enabledNotifier;
  late final ValueNotifier<double> _sizeNotifier;
  StreamSubscription<DrawConfig>? _configSubscription;

  ValueListenable<bool> get enabledListenable => _enabledNotifier;
  ValueListenable<double> get sizeListenable => _sizeNotifier;

  bool get isEnabled => _enabledNotifier.value;
  double get gridSize => _sizeNotifier.value;

  Future<void> toggle() => setEnabled(enabled: !isEnabled);

  Future<void> setEnabled({required bool enabled}) async {
    var nextConfig = _config.copyWith(
      grid: _config.grid.copyWith(enabled: enabled),
    );
    if (enabled && nextConfig.snap.enabled) {
      nextConfig = nextConfig.copyWith(
        snap: nextConfig.snap.copyWith(enabled: false),
      );
    }
    if (nextConfig == _config) {
      return;
    }
    await _store.dispatch(UpdateConfig(nextConfig));
  }

  Future<void> setGridSize(double size) async {
    final clamped = size < GridConfig.minSize
        ? GridConfig.minSize
        : (size > GridConfig.maxSize ? GridConfig.maxSize : size);
    final nextConfig = _config.copyWith(
      grid: _config.grid.copyWith(size: clamped),
    );
    if (nextConfig == _config) {
      return;
    }
    await _store.dispatch(UpdateConfig(nextConfig));
  }

  void dispose() {
    _enabledNotifier.dispose();
    _sizeNotifier.dispose();
    unawaited(_configSubscription?.cancel());
  }

  void _handleConfigChange(DrawConfig config) {
    if (config == _config) {
      return;
    }
    _config = config;
    final nextEnabled = config.grid.enabled;
    if (_enabledNotifier.value != nextEnabled) {
      _enabledNotifier.value = nextEnabled;
    }
    final nextSize = config.grid.size;
    if (_sizeNotifier.value != nextSize) {
      _sizeNotifier.value = nextSize;
    }
  }
}
