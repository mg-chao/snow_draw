import 'package:meta/meta.dart';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../edit/core/edit_modifiers.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../models/draw_state.dart';
import '../camera/camera_reducer.dart';
import '../element/element_reducer.dart';
import '../selection/selection_reducer.dart';
import 'create/create_element_reducer.dart';
import 'edit/edit_state_reducer.dart';
import 'interaction_transition.dart';
import 'selection/box_select_reducer.dart';
import 'selection/pending_state_reducer.dart';
import 'text/text_edit_reducer.dart';

/// Interaction state machine - coordinates sub-reducers.
///
/// Responsibilities:
/// 1. Dispatch actions to sub-reducers by priority
/// 2. Coordinate state transitions across subsystems
///
/// Returns explicit transition events from reducers.
@immutable
class InteractionStateMachine {
  const InteractionStateMachine();

  /// Single entry point for all interaction actions.
  InteractionTransition reduce({
    required DrawState state,
    required DrawAction action,
    required InteractionReducerDeps context,
    required EditSessionService editSessionService,
    required EditSessionIdGenerator sessionIdGenerator,
    EditUpdateFailurePolicy updateFailurePolicy =
        EditUpdateFailurePolicy.toIdle,
  }) {
    final resolvedAction = _resolveEditIntentAction(action, context);
    if (resolvedAction == null) {
      return InteractionTransition.unchanged(state);
    }

    // 1) Edit operations.
    final editReducer = EditStateReducer(
      editSessionService: editSessionService,
      sessionIdGenerator: sessionIdGenerator,
      updateFailurePolicy: updateFailurePolicy,
    );

    final editResult = editReducer.reduce(
      state: state,
      action: resolvedAction,
      context: context,
    );
    if (editResult != null) {
      return editResult;
    }

    // 2) Other interaction and domain reducers.
    final reduced = reduceState(state, resolvedAction, context);
    if (reduced != null) {
      return InteractionTransition(nextState: reduced);
    }

    return InteractionTransition.unchanged(state);
  }

  /// Handle non-edit actions (state only).
  ///
  /// Reducers are called in a specific priority order. The first reducer that
  /// handles an action (returns non-null) wins, and subsequent reducers are
  /// skipped.
  DrawState? reduceState(
    DrawState state,
    DrawAction action,
    InteractionReducerDeps context,
  ) {
    for (final entry in _interactionReducers) {
      final nextState = entry.reduce(state, action, context);
      if (nextState != null) {
        return nextState;
      }
    }
    return null;
  }

  /// Pre-reducer stabilization (no-op).
  DrawState stabilize(
    DrawState state,
    DrawAction action,
    InteractionReducerDeps _,
  ) {
    if (action is CancelEdit) {
      return state;
    }
    return state;
  }
}

enum InteractionReducerPriority {
  pending(0),
  boxSelect(1),
  creation(2),
  textEdit(3),
  selection(4),
  element(5),
  camera(6);

  const InteractionReducerPriority(this.order);
  final int order;
}

@immutable
class _ReducerEntry {
  const _ReducerEntry({required this.priority, required this.reduce});
  final InteractionReducerPriority priority;
  final DrawState? Function(
    DrawState state,
    DrawAction action,
    InteractionReducerDeps context,
  )
  reduce;
}

const _pendingReducer = PendingStateReducer();
const _boxSelectReducer = BoxSelectReducer();
const _createReducer = CreateElementReducer();
const _textEditReducer = TextEditReducer();

final _interactionReducers = <_ReducerEntry>[
  _ReducerEntry(
    priority: InteractionReducerPriority.pending,
    reduce: (state, action, _) => _pendingReducer.reduce(state, action),
  ),
  _ReducerEntry(
    priority: InteractionReducerPriority.boxSelect,
    reduce: (state, action, _) => _boxSelectReducer.reduce(state, action),
  ),
  _ReducerEntry(
    priority: InteractionReducerPriority.creation,
    reduce: (state, action, context) =>
        _createReducer.reduce(state, action, context),
  ),
  _ReducerEntry(
    priority: InteractionReducerPriority.textEdit,
    reduce: (state, action, context) =>
        _textEditReducer.reduce(state, action, context),
  ),
  const _ReducerEntry(
    priority: InteractionReducerPriority.selection,
    reduce: selectionReducer,
  ),
  const _ReducerEntry(
    priority: InteractionReducerPriority.element,
    reduce: elementReducer,
  ),
  const _ReducerEntry(
    priority: InteractionReducerPriority.camera,
    reduce: cameraReducer,
  ),
]..sort((a, b) => a.priority.order.compareTo(b.priority.order));

const interactionStateMachine = InteractionStateMachine();

@immutable
class HistoryAvailability {
  const HistoryAvailability({this.canUndo = true, this.canRedo = true});
  final bool canUndo;
  final bool canRedo;

  bool shouldCancelFor(DrawAction action) {
    if (action is Undo) {
      return canUndo;
    }
    if (action is Redo) {
      return canRedo;
    }
    return false;
  }
}

DrawAction? _resolveEditIntentAction(
  DrawAction action,
  EditIntentResolverDeps context,
) {
  if (action is! EditIntentAction) {
    return action;
  }
  return context.editIntentMapper.mapToStartEdit(
    intent: action.intent,
    position: action.position,
    modifiers: action.modifiers,
    editOperations: context.editOperations,
  );
}
