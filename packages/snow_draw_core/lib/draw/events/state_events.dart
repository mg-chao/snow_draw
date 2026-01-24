import 'package:meta/meta.dart';

import '../models/camera_state.dart';
import '../models/interaction_state.dart';
import 'event_bus.dart';

@immutable
abstract class StateChangeEvent extends DrawEvent {
  const StateChangeEvent();
}

@immutable
class DocumentChangedEvent extends StateChangeEvent {
  const DocumentChangedEvent({
    required this.elementsVersion,
    required this.elementCount,
  });
  final int elementsVersion;
  final int elementCount;

  @override
  String toString() =>
      'DocumentChangedEvent(version: $elementsVersion, count: $elementCount)';
}

@immutable
class SelectionChangedEvent extends StateChangeEvent {
  const SelectionChangedEvent({
    required this.selectedIds,
    required this.selectionVersion,
  });
  final Set<String> selectedIds;
  final int selectionVersion;

  @override
  String toString() =>
      'SelectionChangedEvent(version: $selectionVersion, '
      'count: ${selectedIds.length})';
}

@immutable
class ViewChangedEvent extends StateChangeEvent {
  const ViewChangedEvent({required this.camera});
  final CameraState camera;

  @override
  String toString() => 'ViewChangedEvent(camera: $camera)';
}

@immutable
class InteractionChangedEvent extends StateChangeEvent {
  const InteractionChangedEvent({required this.interaction});
  final InteractionState interaction;

  @override
  String toString() => 'InteractionChangedEvent(interaction: $interaction)';
}

@immutable
class HistoryAvailabilityChangedEvent extends StateChangeEvent {
  const HistoryAvailabilityChangedEvent({
    required this.canUndo,
    required this.canRedo,
  });
  final bool canUndo;
  final bool canRedo;

  @override
  String toString() =>
      'HistoryAvailabilityChangedEvent(canUndo: $canUndo, canRedo: $canRedo)';
}
