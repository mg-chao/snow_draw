import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';

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

  Future<void> toggle() => setEnabled(enabled: !isEnabled);

  Future<void> setEnabled({required bool enabled}) async {
    if (_isDisposed) {
      return;
    }
    var nextConfig = _config.copyWith(
      snap: _config.snap.copyWith(enabled: enabled),
    );
    if (enabled && nextConfig.grid.enabled) {
      nextConfig = nextConfig.copyWith(
        grid: nextConfig.grid.copyWith(enabled: false),
      );
    }
    if (nextConfig == _config) {
      return;
    }
    await _store.dispatch(UpdateConfig(nextConfig));
  }

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
}
