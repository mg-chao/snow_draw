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
  DrawConfig? _pendingConfig;
  var _freezeDepth = 0;
  var _isDisposed = false;

  /// Get the current configuration.
  DrawConfig get current => _config;

  /// Configuration change stream.
  Stream<DrawConfig> get stream => _controller.stream;

  /// Update configuration.
  ///
  /// If the new config matches the current one, do nothing.
  /// Returns true if updated, false if unchanged.
  bool update(DrawConfig newConfig) {
    if (_isDisposed) {
      return false;
    }

    if (_freezeDepth == 0) {
      return _commit(newConfig);
    }

    final writableConfig = _pendingConfig ?? _config;
    if (newConfig != writableConfig) {
      _pendingConfig = newConfig;
    }
    return false;
  }

  /// Freeze config reads during a dispatch.
  void freeze() {
    if (_isDisposed) {
      return;
    }
    _freezeDepth += 1;
  }

  /// Unfreeze and apply any pending update.
  void unfreeze() {
    if (_isDisposed || _freezeDepth == 0) {
      return;
    }

    _freezeDepth -= 1;
    if (_freezeDepth != 0) {
      return;
    }

    final pending = _pendingConfig;
    _pendingConfig = null;
    if (pending != null) {
      _commit(pending);
    }
  }

  bool _commit(DrawConfig newConfig) {
    if (newConfig == _config) {
      return false;
    }

    _config = newConfig;
    _controller.add(newConfig);
    return true;
  }

  /// Update selection configuration.
  ///
  /// Convenience method to update only the selection config.
  /// Returns true if updated, false if unchanged.
  bool updateSelection(SelectionConfig selection) {
    final writableConfig = _pendingConfig ?? _config;
    return update(writableConfig.copyWith(selection: selection));
  }

  /// Update canvas configuration.
  ///
  /// Convenience method to update only the canvas config.
  /// Returns true if updated, false if unchanged.
  bool updateCanvas(CanvasConfig canvas) {
    final writableConfig = _pendingConfig ?? _config;
    return update(writableConfig.copyWith(canvas: canvas));
  }

  /// Release resources.
  Future<void> dispose() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    _isDisposed = true;
    _freezeDepth = 0;
    _pendingConfig = null;
    return _controller.close();
  }
}
