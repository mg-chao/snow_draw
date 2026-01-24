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

  /// Get the current configuration.
  DrawConfig get current => _config;

  /// Configuration change stream.
  Stream<DrawConfig> get stream => _controller.stream;

  /// Update configuration.
  ///
  /// If the new config matches the current one, do nothing.
  /// Returns true if updated, false if unchanged.
  bool update(DrawConfig newConfig) {
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
      update(_config.copyWith(selection: selection));

  /// Update canvas configuration.
  ///
  /// Convenience method to update only the canvas config.
  /// Returns true if updated, false if unchanged.
  bool updateCanvas(CanvasConfig canvas) =>
      update(_config.copyWith(canvas: canvas));

  /// Release resources.
  Future<void> dispose() => _controller.close();
}
