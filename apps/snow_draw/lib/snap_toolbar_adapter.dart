import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';

import 'config_update_queue.dart';

class SnapToolbarAdapter {
  SnapToolbarAdapter({required DrawStore store}) : _store = store {
    _config = _store.config;
    _enabledNotifier = ValueNotifier<bool>(_config.snap.enabled);
    _configSubscription = _store.configStream.listen(_handleConfigChange);
  }

  final DrawStore _store;
  late DrawConfig _config;
  late final ValueNotifier<bool> _enabledNotifier;
  StreamSubscription<DrawConfig>? _configSubscription;
  var _isDisposed = false;

  ValueListenable<bool> get enabledListenable => _enabledNotifier;

  bool get isEnabled => _enabledNotifier.value;

  Future<void> toggle() => _enqueueConfigUpdate(
    () => _setEnabledInternal(enabled: !_store.config.snap.enabled),
  );

  Future<void> setEnabled({required bool enabled}) =>
      _enqueueConfigUpdate(() => _setEnabledInternal(enabled: enabled));

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _enabledNotifier.dispose();
    unawaited(_configSubscription?.cancel());
  }

  void _handleConfigChange(DrawConfig config) {
    if (_isDisposed || config == _config) {
      return;
    }
    _config = config;
    final nextEnabled = config.snap.enabled;
    if (_enabledNotifier.value == nextEnabled) {
      return;
    }
    _enabledNotifier.value = nextEnabled;
  }

  Future<void> _enqueueConfigUpdate(Future<void> Function() update) =>
      ConfigUpdateQueue.enqueue(_store, update);

  Future<void> _setEnabledInternal({required bool enabled}) async {
    if (_isDisposed) {
      return;
    }
    final currentConfig = _store.config;
    _config = currentConfig;
    var nextConfig = currentConfig.copyWith(
      snap: currentConfig.snap.copyWith(enabled: enabled),
    );
    if (enabled && nextConfig.grid.enabled) {
      nextConfig = nextConfig.copyWith(
        grid: nextConfig.grid.copyWith(enabled: false),
      );
    }
    if (nextConfig == currentConfig) {
      return;
    }
    _config = nextConfig;
    final nextEnabled = nextConfig.snap.enabled;
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
      final rollbackEnabled = _config.snap.enabled;
      if (_enabledNotifier.value != rollbackEnabled) {
        _enabledNotifier.value = rollbackEnabled;
      }
      rethrow;
    }
  }
}
