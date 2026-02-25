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

  /// Factory method: create initial state.
  factory DrawState.initial({ViewState? view}) => DrawState(
    domain: DomainState.empty(),
    application: ApplicationState.initial(view: view),
  );

  /// Domain state (participates in undo/redo and is persisted).
  final DomainState domain;

  /// Application state (temporary, not part of undo/redo).
  final ApplicationState application;

  DrawState copyWith({DomainState? domain, ApplicationState? application}) =>
      DrawState(
        domain: domain ?? this.domain,
        application: application ?? this.application,
      );

  /// Get the domain snapshot used for history.
  DomainState get domainSnapshot => domain;

  /// Restore domain state from history.
  DrawState restoreFromSnapshot(DomainState snapshot) => DrawState(
    domain: snapshot,
    application: application.copyWith(
      interaction: const IdleState(),
      selectionOverlay: SelectionOverlayState.empty,
    ),
  );

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
