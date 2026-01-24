import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../models/draw_state.dart';

/// Sub-reducer function signature.
///
/// Returns a [DrawState] to indicate the action was handled (even if it's a
/// no-op), or `null` to indicate "not handled" so the next reducer can try.
typedef SubReducer =
    DrawState? Function(
      DrawState state,
      DrawAction action,
      DrawContext context,
    );

/// Handler signature for a specific [DrawAction] type.
typedef ActionHandler<A extends DrawAction> =
    DrawState? Function(DrawState state, A action, DrawContext context);

/// Handler signature for actions that don't carry extra payload.
typedef SimpleHandler =
    DrawState? Function(DrawState state, DrawContext context);
