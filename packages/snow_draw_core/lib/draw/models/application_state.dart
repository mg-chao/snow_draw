import 'package:meta/meta.dart';

import 'interaction_state.dart';
import 'selection_overlay_state.dart';
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
    this.selectionOverlay = SelectionOverlayState.empty,
  });

  /// Factory method: create the initial application state.
  factory ApplicationState.initial({ViewState? view}) =>
      ApplicationState(view: view ?? const ViewState());

  /// View state (camera position, zoom, and so on).
  final ViewState view;

  /// Interaction state (editing, creating, box selection, and so on).
  final InteractionState interaction;

  /// Selection overlay state (multi-select bounds/rotation).
  final SelectionOverlayState selectionOverlay;

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

  /// Whether it is pending (select or move).
  bool get isPending => interaction is DragPendingState;

  ApplicationState copyWith({
    ViewState? view,
    InteractionState? interaction,
    SelectionOverlayState? selectionOverlay,
  }) => ApplicationState(
    view: view ?? this.view,
    interaction: interaction ?? this.interaction,
    selectionOverlay: selectionOverlay ?? this.selectionOverlay,
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
          other.interaction == interaction &&
          other.selectionOverlay == selectionOverlay;

  @override
  int get hashCode => Object.hash(view, interaction, selectionOverlay);

  @override
  String toString() =>
      'ApplicationState(view: $view, '
      'interaction: $interaction, '
      'selectionOverlay: $selectionOverlay)';
}
