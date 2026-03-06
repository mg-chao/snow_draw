import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../elements/types/connector/connector_points.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/resize_mode.dart';

@immutable
abstract class EditOperationParams {
  const EditOperationParams({this.initialSelectionBounds});

  final DrawRect? initialSelectionBounds;
}

@immutable
final class MoveOperationParams extends EditOperationParams {
  const MoveOperationParams({super.initialSelectionBounds});
}

@immutable
final class ResizeOperationParams extends EditOperationParams {
  const ResizeOperationParams({
    required this.resizeMode,
    this.handleOffset,
    this.selectionPadding = 0,
    super.initialSelectionBounds,
  }) : assert(selectionPadding >= 0, 'selectionPadding must be non-negative');

  final ResizeMode resizeMode;

  final DrawPoint? handleOffset;

  final double selectionPadding;
}

@immutable
final class RotateOperationParams extends EditOperationParams {
  const RotateOperationParams({
    this.startRotationAngle,
    this.rotationSnapAngle = ConfigDefaults.rotationSnapAngle,
    super.initialSelectionBounds,
  }) : assert(rotationSnapAngle >= 0, 'rotationSnapAngle must be non-negative');

  final double? startRotationAngle;

  final double rotationSnapAngle;
}

@immutable
final class ConnectorPointOperationParams extends EditOperationParams {
  const ConnectorPointOperationParams({
    required this.elementId,
    required this.pointKind,
    required this.pointIndex,
    this.isDoubleClick = false,
    super.initialSelectionBounds,
  }) : assert(elementId != '', 'elementId must not be empty'),
       assert(pointIndex >= 0, 'pointIndex must be non-negative');

  final String elementId;
  final ConnectorPointKind pointKind;
  final int pointIndex;
  final bool isDoubleClick;
}
