import 'package:meta/meta.dart';

import 'application_state.dart';
import 'domain_state.dart';
import 'interaction_state.dart';
import 'selection_overlay_state.dart';
import 'view_state.dart';

/// Aggregate root for draw state.
///
/// Coordinates domain and application state with a unified access interface.
@immutable
class DrawState {
  DrawState({DomainState? domain, ApplicationState? application})
    : domain = domain ?? DomainState.empty(),
      application = application ?? ApplicationState.initial();

  /// Factory constructor: create from layered state.
  factory DrawState.fromLayers({
    required DomainState domain,
    required ApplicationState application,
  }) => DrawState(domain: domain, application: application);

  /// Factory method: create initial state.
  factory DrawState.initial({ViewState? view}) {
    final domainState = DomainState.empty();
    final applicationState = ApplicationState.initial(view: view);
    return DrawState.fromLayers(
      domain: domainState,
      application: applicationState,
    );
  }

  /// Domain state (participates in undo/redo and is persisted).
  final DomainState domain;

  /// Application state (temporary, not part of undo/redo).
  final ApplicationState application;

  DrawState copyWith({DomainState? domain, ApplicationState? application}) =>
      DrawState(
        domain: domain ?? this.domain,
        application: application ?? this.application,
      );

  // ============ History ============

  /// Get the domain snapshot used for history.
  DomainState get domainSnapshot => domain;

  /// Restore domain state from history.
  DrawState restoreFromSnapshot(DomainState snapshot) {
    // Restore domain state while keeping the current application state.
    // Also reset interaction to recompute selection overlays.
    final newApplication = application.copyWith(
      interaction: const IdleState(),
      selectionOverlay: SelectionOverlayState.empty,
    );
    return DrawState(domain: snapshot, application: newApplication);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawState &&
          other.domain == domain &&
          other.application == application;

  @override
  int get hashCode => Object.hash(domain, application);

  @override
  String toString() =>
      'DrawState(elements: ${domain.document.elements.length}, '
      'selection: ${domain.selection.selectedIds}, '
      'interaction: ${application.interaction})';
}
