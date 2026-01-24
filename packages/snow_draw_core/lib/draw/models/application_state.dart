import 'package:meta/meta.dart';

import 'interaction_state.dart';
import 'view_state.dart';

/// Application-layer state.
///
/// Contains all temporary UI and interaction state.
/// These states do not participate in undo/redo and are not persisted.
@immutable
class ApplicationState {
  const ApplicationState({
    required this.view,
    this.interaction = const IdleState(),
  });

  /// Factory method: create the initial application state.
  factory ApplicationState.initial({ViewState? view}) =>
      ApplicationState(view: view ?? const ViewState());

  /// View state (camera position, zoom, and so on).
  final ViewState view;

  /// Interaction state (editing, creating, box selection, and so on).
  final InteractionState interaction;

  /// Whether editing is in progress.
  bool get isEditing => interaction is EditingState;

  /// Whether creation is in progress.
  bool get isCreating => interaction is CreatingState;

  /// Whether box selection is in progress.
  bool get isBoxSelecting => interaction is BoxSelectingState;

  /// Whether text editing is in progress.
  bool get isTextEditing => interaction is TextEditingState;

  /// Whether the state is idle.
  bool get isIdle => interaction is IdleState;

  /// Whether it is pending select.
  bool get isPendingSelect => interaction is PendingSelectState;

  /// Whether it is pending move.
  bool get isPendingMove => interaction is PendingMoveState;

  ApplicationState copyWith({ViewState? view, InteractionState? interaction}) =>
      ApplicationState(
        view: view ?? this.view,
        interaction: interaction ?? this.interaction,
      );

  /// Reset to the idle state.
  ApplicationState toIdle() {
    if (interaction is IdleState) {
      return this;
    }
    return copyWith(interaction: const IdleState());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicationState &&
          other.view == view &&
          other.interaction == interaction;

  @override
  int get hashCode => Object.hash(view, interaction);

  @override
  String toString() =>
      'ApplicationState(view: $view, interaction: $interaction)';
}
