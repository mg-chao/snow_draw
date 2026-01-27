import 'package:meta/meta.dart';

import '../../elements/types/arrow/arrow_points.dart';
import '../../models/edit_enums.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../free_transform/free_transform_context.dart';

@immutable
abstract class EditOperationParams {
  const EditOperationParams({this.initialSelectionBounds});
  final DrawRect? initialSelectionBounds;
}

@immutable
class MoveOperationParams extends EditOperationParams {
  const MoveOperationParams({super.initialSelectionBounds});
}

@immutable
class ResizeOperationParams extends EditOperationParams {
  const ResizeOperationParams({
    required this.resizeMode,
    this.handleOffset,
    this.selectionPadding,
    super.initialSelectionBounds,
  });
  final ResizeMode resizeMode;

  /// Local-space offset between the pointer and the resize handle center.
  ///
  /// When omitted, the operation computes it from [resizeMode] and config.
  final DrawPoint? handleOffset;

  /// Selection padding used for handle placement / bounds calculation.
  ///
  /// When omitted, it should be injected at StartEdit (from
  /// `SelectionConfig.padding`).
  final double? selectionPadding;
}

@immutable
class RotateOperationParams extends EditOperationParams {
  const RotateOperationParams({
    this.startRotationAngle,
    this.rotationSnapAngle,
    super.initialSelectionBounds,
  });

  /// Pointer angle around the rotation center at the start (raw atan2 angle).
  ///
  /// When omitted, the operation computes it from the start pointer position.
  final double? startRotationAngle;

  /// Discrete snap interval for rotation when `discreteAngle` modifier is
  /// used.
  ///
  /// Usually injected from `DrawConfig.element.rotationSnapAngle` at
  /// edit-start.
  final double? rotationSnapAngle;
}

@immutable
class FreeTransformOperationParams extends EditOperationParams {
  const FreeTransformOperationParams({
    super.initialSelectionBounds,
    this.initialMode = FreeTransformMode.move,
  });
  final FreeTransformMode initialMode;
}

@immutable
class ArrowPointOperationParams extends EditOperationParams {
  const ArrowPointOperationParams({
    required this.elementId,
    required this.pointKind,
    required this.pointIndex,
    super.initialSelectionBounds,
  });

  final String elementId;
  final ArrowPointKind pointKind;
  final int pointIndex;
}
