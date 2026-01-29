import '../../actions/draw_actions.dart';
import '../../types/draw_point.dart';
import '../../types/edit_operation_id.dart';
import '../../utils/edit_intent_detector.dart';
import '../edit_operation_registry_interface.dart';
import 'edit_modifiers.dart';
import 'edit_operation_params.dart';

typedef EditIntentToOperationPredicate =
    bool Function(EditIntent intent, EditIntentToOperationContext context);

typedef EditIntentToParamsBuilder =
    EditOperationParams Function(
      EditIntent intent,
      EditIntentToOperationContext context,
    );

class EditIntentToOperationContext {
  const EditIntentToOperationContext({
    required this.position,
    required this.modifiers,
    required this.editOperations,
  });
  final DrawPoint position;
  final EditModifiers modifiers;
  final EditOperationRegistry editOperations;

  bool get maintainAspectRatio => modifiers.maintainAspectRatio;
  bool get fromCenter => modifiers.fromCenter;
  bool get discreteAngle => modifiers.discreteAngle;
}

/// Maps input-layer [EditIntent] to a domain-layer [StartEdit] action.
///
/// This is an extension point: new operations can be wired up by registering
/// new mappings, without modifying controller flow.
class EditIntentToOperationMapper {
  const EditIntentToOperationMapper._(this._mappings);

  factory EditIntentToOperationMapper.withDefaults() =>
      EditIntentToOperationMapper._([
        _IntentMapping(
          operationId: EditOperationIds.arrowPoint,
          predicate: (intent, _) => intent is StartArrowPointIntent,
          paramsBuilder: (intent, _) {
            final arrowIntent = intent as StartArrowPointIntent;
            return ArrowPointOperationParams(
              elementId: arrowIntent.elementId,
              pointKind: arrowIntent.pointKind,
              pointIndex: arrowIntent.pointIndex,
              isDoubleClick: arrowIntent.isDoubleClick,
            );
          },
        ),
        _IntentMapping(
          operationId: EditOperationIds.rotate,
          predicate: (intent, _) => intent is StartRotateIntent,
          paramsBuilder: (intent, context) => const RotateOperationParams(),
        ),
        _IntentMapping(
          operationId: EditOperationIds.resize,
          predicate: (intent, _) => intent is StartResizeIntent,
          paramsBuilder: (intent, _) {
            final resizeIntent = intent as StartResizeIntent;
            return ResizeOperationParams(
              resizeMode: resizeIntent.mode,
              selectionPadding: resizeIntent.selectionPadding,
            );
          },
        ),
        _IntentMapping(
          operationId: EditOperationIds.move,
          predicate: (intent, _) => intent is StartMoveIntent,
          paramsBuilder: (intent, context) => const MoveOperationParams(),
        ),
      ]);

  /// Creates a mapper from a mapping list (higher priority first).
  factory EditIntentToOperationMapper.custom(
    List<EditIntentToOperationMapping> mappings,
  ) => EditIntentToOperationMapper._([
    for (final m in mappings)
      _IntentMapping(
        operationId: m.operationId,
        predicate: m.predicate,
        paramsBuilder: m.paramsBuilder,
      ),
  ]);
  final List<_IntentMapping> _mappings;

  /// Returns a [StartEdit] action, or `null` if the intent is not mapped.
  ///
  /// This returns `null` when the mapped operation id is not registered in
  /// [editOperations] to avoid starting unknown operations.
  StartEdit? mapToStartEdit({
    required EditIntent intent,
    required DrawPoint position,
    required EditModifiers modifiers,
    required EditOperationRegistry editOperations,
  }) {
    final context = EditIntentToOperationContext(
      position: position,
      modifiers: modifiers,
      editOperations: editOperations,
    );

    for (final mapping in _mappings) {
      if (!mapping.predicate(intent, context)) {
        continue;
      }
      if (editOperations.getOperation(mapping.operationId) == null) {
        return null;
      }
      return StartEdit(
        operationId: mapping.operationId,
        position: position,
        params: mapping.paramsBuilder(intent, context),
      );
    }

    return null;
  }
}

/// Public mapping entry for configuring [EditIntentToOperationMapper].
class EditIntentToOperationMapping {
  const EditIntentToOperationMapping({
    required this.operationId,
    required this.predicate,
    required this.paramsBuilder,
  });
  final EditOperationId operationId;
  final EditIntentToOperationPredicate predicate;
  final EditIntentToParamsBuilder paramsBuilder;
}

class _IntentMapping {
  const _IntentMapping({
    required this.operationId,
    required this.predicate,
    required this.paramsBuilder,
  });
  final EditOperationId operationId;
  final EditIntentToOperationPredicate predicate;
  final EditIntentToParamsBuilder paramsBuilder;
}
