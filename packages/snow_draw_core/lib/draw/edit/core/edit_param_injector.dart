import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../types/draw_rect.dart';
import 'edit_config.dart';
import 'edit_config_provider.dart';
import 'edit_operation_params.dart';

/// Centralized parameter injection for edit operations.
///
/// This keeps "defaulting" logic (selection bounds, config-derived values)
/// out of store/controller code, and makes it easy to unit test.
@immutable
class EditParamInjector {
  const EditParamInjector({
    this.rotateSnapAngle = ConfigDefaults.rotationSnapAngle,
    this.selectionPadding = ConfigDefaults.selectionPadding,
  });

  /// Create from EditConfig.
  factory EditParamInjector.fromConfig(EditConfig config) => EditParamInjector(
    rotateSnapAngle: config.rotationSnapAngle,
    selectionPadding: config.selectionPadding,
  );

  /// Create from EditConfigProvider.
  factory EditParamInjector.fromProvider(EditConfigProvider provider) =>
      EditParamInjector.fromConfig(provider.editConfig);
  final double rotateSnapAngle;
  final double selectionPadding;

  EditOperationParams inject({
    required EditOperationParams params,
    required DrawRect? initialSelectionBounds,
  }) {
    final effectiveInitialBounds =
        params.initialSelectionBounds ?? initialSelectionBounds;

    return switch (params) {
      final MoveOperationParams p => MoveOperationParams(
        initialSelectionBounds:
            p.initialSelectionBounds ?? effectiveInitialBounds,
      ),
      final RotateOperationParams p => RotateOperationParams(
        startRotationAngle: p.startRotationAngle,
        rotationSnapAngle: p.rotationSnapAngle ?? rotateSnapAngle,
        initialSelectionBounds:
            p.initialSelectionBounds ?? effectiveInitialBounds,
      ),
      final ResizeOperationParams p => ResizeOperationParams(
        resizeMode: p.resizeMode,
        handleOffset: p.handleOffset,
        selectionPadding: p.selectionPadding ?? selectionPadding,
        initialSelectionBounds:
            p.initialSelectionBounds ?? effectiveInitialBounds,
      ),
      _ => params,
    };
  }
}
