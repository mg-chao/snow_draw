import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';

/// Handles a [DrawAction] and returns the next [DrawState].
///
/// Returning `null` means the action is not handled by this reducer.
typedef SubReducer<D> =
    DrawState? Function(DrawState state, DrawAction action, D deps);

/// Type-safe handler for a specific [DrawAction] subtype.
typedef ActionHandler<A extends DrawAction, D> =
    DrawState? Function(DrawState state, A action, D deps);
