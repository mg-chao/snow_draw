import '../../actions/draw_actions.dart';
import '../../config/draw_config.dart';
import '../../types/draw_point.dart';
import '../../types/edit_operation_id.dart';
import '../../utils/edit_intent_detector.dart';
import 'edit_operation_params.dart';

typedef EditIntentResolver =
    EditIntentResolution? Function(EditIntent intent, DrawConfig config);

typedef EditIntentResolution = ({
  EditOperationId operationId,
  EditOperationParams params,
});

/// Maps input-layer [EditIntent] to a domain-layer [StartEdit] action.
///
/// Default mapping is implemented with a direct type switch, avoiding runtime
/// predicates and downcasts from the previous mapping-list approach.
class EditIntentToOperationMapper {
  const EditIntentToOperationMapper._(this._resolver);

  factory EditIntentToOperationMapper.withDefaults() =>
      const EditIntentToOperationMapper._(_resolveDefaultIntent);

  /// Creates a mapper from a custom [resolver].
  factory EditIntentToOperationMapper.custom(EditIntentResolver resolver) =>
      EditIntentToOperationMapper._(resolver);

  final EditIntentResolver _resolver;

  /// Returns a [StartEdit] action, or `null` if the intent is not mapped.
  StartEdit? mapToStartEdit({
    required EditIntent intent,
    required DrawPoint position,
    required DrawConfig config,
  }) {
    final resolved = _resolver(intent, config);
    if (resolved == null) {
      return null;
    }
    return StartEdit(
      operationId: resolved.operationId,
      position: position,
      params: resolved.params,
    );
  }
}

EditIntentResolution? _resolveDefaultIntent(
  EditIntent intent,
  DrawConfig config,
) => switch (intent) {
  StartArrowPointIntent(
    :final elementId,
    :final pointKind,
    :final pointIndex,
    :final isDoubleClick,
  ) =>
    (
      operationId: EditOperationIds.arrowPoint,
      params: ArrowPointOperationParams(
        elementId: elementId,
        pointKind: pointKind,
        pointIndex: pointIndex,
        isDoubleClick: isDoubleClick,
      ),
    ),
  StartRotateIntent() => (
    operationId: EditOperationIds.rotate,
    params: RotateOperationParams(
      rotationSnapAngle: config.element.rotationSnapAngle,
    ),
  ),
  StartResizeIntent(:final mode, :final selectionPadding) => (
    operationId: EditOperationIds.resize,
    params: ResizeOperationParams(
      resizeMode: mode,
      selectionPadding: selectionPadding,
    ),
  ),
  StartMoveIntent() => (
    operationId: EditOperationIds.move,
    params: const MoveOperationParams(),
  ),
  _ => null,
};
