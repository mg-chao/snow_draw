import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import 'snapshot.dart';

/// Builds snapshots for undo/redo.
@immutable
class SnapshotBuilder {
  const SnapshotBuilder();

  PersistentSnapshot buildSnapshotFromState({
    required DrawState state,
    required bool includeSelection,
  }) => PersistentSnapshot.fromState(state, includeSelection: includeSelection);
}
