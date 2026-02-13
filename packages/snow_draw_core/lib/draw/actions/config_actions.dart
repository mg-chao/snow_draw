import '../config/draw_config.dart';
import '../store/draw_store_interface.dart' show DrawStore;
import 'draw_actions.dart';

/// Updates the full [DrawConfig] for a [DrawStore].
class UpdateConfig extends DrawAction {
  const UpdateConfig(this.config);
  final DrawConfig config;

  @override
  String toString() => 'UpdateConfig(config: $config)';
}

/// Convenience action for partially updating selection config.
class UpdateSelectionConfig extends DrawAction {
  const UpdateSelectionConfig(this.selection);
  final SelectionConfig selection;

  @override
  String toString() => 'UpdateSelectionConfig(selection: $selection)';
}

/// Convenience action for partially updating canvas config.
class UpdateCanvasConfig extends DrawAction {
  const UpdateCanvasConfig(this.canvas);
  final CanvasConfig canvas;

  @override
  String toString() => 'UpdateCanvasConfig(canvas: $canvas)';
}
