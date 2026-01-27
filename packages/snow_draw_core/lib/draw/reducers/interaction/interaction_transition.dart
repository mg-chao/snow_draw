import 'package:meta/meta.dart';

import '../../edit/core/edit_event_factory.dart';
import '../../models/draw_state.dart';

/// Interaction state transition result.
///
/// Carries the next state plus any explicit edit session events to emit.
@immutable
class InteractionTransition {
  const InteractionTransition({
    required this.nextState,
    this.events = const [],
  });

  /// State unchanged.
  factory InteractionTransition.unchanged(
    DrawState state, {
    List<EditSessionEvent> events = const [],
  }) => InteractionTransition(nextState: state, events: events);
  final DrawState nextState;
  final List<EditSessionEvent> events;
}
