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
  var _pendingConfigUpdate = Future<void>.value();
  var _isDisposed = false;

  ValueListenable<bool> get enabledListenable => _enabledNotifier;
  ValueListenable<double> get sizeListenable => _sizeNotifier;

  bool get isEnabled => _enabledNotifier.value;
  double get gridSize => _sizeNotifier.value;

  Future<void> toggle() => _enqueueConfigUpdate(
    () => _setEnabledInternal(enabled: !_config.grid.enabled),
  );

  Future<void> setEnabled({required bool enabled}) =>
      _enqueueConfigUpdate(() => _setEnabledInternal(enabled: enabled));

  Future<void> setGridSize(double size) => _enqueueConfigUpdate(() async {
    if (_isDisposed) {
      return;
    }
    final clamped = size < GridConfig.minSize
        ? GridConfig.minSize
        : (size > GridConfig.maxSize ? GridConfig.maxSize : size);
    final nextConfig = _config.copyWith(
      grid: _config.grid.copyWith(size: clamped),
    );
    if (nextConfig == _config) {
      return;
    }
    _config = nextConfig;
    final nextSize = nextConfig.grid.size;
    if (_sizeNotifier.value != nextSize) {
      _sizeNotifier.value = nextSize;
    }
    try {
      await _store.dispatch(UpdateConfig(nextConfig));
    } on Object {
      if (_isDisposed) {
        return;
      }
      _config = _store.config;
      final rollbackEnabled = _config.grid.enabled;
      if (_enabledNotifier.value != rollbackEnabled) {
        _enabledNotifier.value = rollbackEnabled;
      }
      final rollbackSize = _config.grid.size;
      if (_sizeNotifier.value != rollbackSize) {
        _sizeNotifier.value = rollbackSize;
      }
      rethrow;
    }
  });

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _enabledNotifier.dispose();
    _sizeNotifier.dispose();
    unawaited(_configSubscription?.cancel());
  }

  void _handleConfigChange(DrawConfig config) {
    if (_isDisposed || config == _config) {
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

  Future<void> _enqueueConfigUpdate(Future<void> Function() update) =>
      _pendingConfigUpdate = _pendingConfigUpdate
          .catchError((Object _, StackTrace _) {})
          .then((_) => update());

  Future<void> _setEnabledInternal({required bool enabled}) async {
    if (_isDisposed) {
      return;
    }
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
    _config = nextConfig;
    final nextEnabled = nextConfig.grid.enabled;
    if (_enabledNotifier.value != nextEnabled) {
      _enabledNotifier.value = nextEnabled;
    }
    try {
      await _store.dispatch(UpdateConfig(nextConfig));
    } on Object {
      if (_isDisposed) {
        return;
      }
      _config = _store.config;
      final rollbackEnabled = _config.grid.enabled;
      if (_enabledNotifier.value != rollbackEnabled) {
        _enabledNotifier.value = rollbackEnabled;
      }
      final rollbackSize = _config.grid.size;
      if (_sizeNotifier.value != rollbackSize) {
        _sizeNotifier.value = rollbackSize;
      }
      rethrow;
    }
  }
}
