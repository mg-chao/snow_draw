import '../../actions/draw_actions.dart';
import '../../models/draw_state.dart';

/// Sub-reducer function signature.
///
/// Returns a [DrawState] to indicate the action was handled (even if it's a
/// no-op), or `null` to indicate "not handled" so the next reducer can try.
typedef SubReducer<D> =
    DrawState? Function(DrawState state, DrawAction action, D deps);

/// Handler signature for a specific [DrawAction] type.
typedef ActionHandler<A extends DrawAction, D> =
    DrawState? Function(DrawState state, A action, D deps);

/// Handler signature for actions that don't carry extra payload.
typedef SimpleHandler<D> = DrawState? Function(DrawState state, D deps);
