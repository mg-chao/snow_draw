import 'package:meta/meta.dart';

import '../models/draw_state.dart';
import 'history_metadata.dart';

/// History service interface for undo/redo.
abstract interface class HistoryService {
  void record({
    required DrawState previousState,
    required DrawState newState,
    required HistoryMetadata metadata,
  });

  DrawState? undo();
  DrawState? redo();

  bool get canUndo;
  bool get canRedo;

  List<String> get undoDescriptions;
  List<String> get redoDescriptions;

  void clear();
}

@immutable
class HistoryEntry {
  HistoryEntry({
    required this.state,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final DrawState state;
  final HistoryMetadata metadata;
  final DateTime timestamp;
}
