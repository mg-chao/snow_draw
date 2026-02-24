import 'package:meta/meta.dart';

import '../../models/draw_state.dart';

/// Interaction state transition result.
@immutable
class InteractionTransition {
  const InteractionTransition({required this.nextState});

  /// State unchanged.
  const InteractionTransition.unchanged(DrawState state)
    : this(nextState: state);

  final DrawState nextState;
}
