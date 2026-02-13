import 'dart:async';

import 'draw_config.dart';

/// Configuration manager.
///
/// Manages DrawConfig updates and change notifications.
/// Provides a configuration stream so listeners can react to changes.
class ConfigManager {
  ConfigManager(DrawConfig initialConfig)
    : _config = initialConfig,
      _controller = StreamController<DrawConfig>.broadcast();
  DrawConfig _config;
  final StreamController<DrawConfig> _controller;
  DrawConfig? _frozenConfig;
  DrawConfig? _pendingConfig;
  var _freezeDepth = 0;

  /// Get the current configuration.
  DrawConfig get current => _frozenConfig ?? _config;

  /// Configuration change stream.
  Stream<DrawConfig> get stream => _controller.stream;

  /// Update configuration.
  ///
  /// If the new config matches the current one, do nothing.
  /// Returns true if updated, false if unchanged.
  bool update(DrawConfig newConfig) {
    if (_freezeDepth > 0) {
      _pendingConfig = newConfig;
      return false;
    }
    return _applyUpdate(newConfig);
  }

  /// Freeze config reads during a dispatch.
  void freeze() {
    _freezeDepth += 1;
    if (_freezeDepth == 1) {
      _frozenConfig = _config;
    }
  }

  /// Unfreeze and apply any pending update.
  void unfreeze() {
    if (_freezeDepth == 0) {
      return;
    }
    _freezeDepth -= 1;
    if (_freezeDepth > 0) {
      return;
    }
    _frozenConfig = null;
    final pending = _pendingConfig;
    if (pending == null) {
      return;
    }
    _pendingConfig = null;
    _applyUpdate(pending);
  }

  bool _applyUpdate(DrawConfig newConfig) {
    if (newConfig == _config) {
      return false;
    }
    _config = newConfig;
    _controller.add(_config);
    return true;
  }

  /// Update selection configuration.
  ///
  /// Convenience method to update only the selection config.
  /// Returns true if updated, false if unchanged.
  bool updateSelection(SelectionConfig selection) =>
      update(_configForWrites.copyWith(selection: selection));

  /// Update canvas configuration.
  ///
  /// Convenience method to update only the canvas config.
  /// Returns true if updated, false if unchanged.
  bool updateCanvas(CanvasConfig canvas) =>
      update(_configForWrites.copyWith(canvas: canvas));

  DrawConfig get _configForWrites => _pendingConfig ?? _config;

  /// Release resources.
  Future<void> dispose() => _controller.close();
}
