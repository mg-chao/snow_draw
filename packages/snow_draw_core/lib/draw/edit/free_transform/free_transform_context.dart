import 'package:meta/meta.dart';

import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';

enum FreeTransformMode { move, resize, rotate }

@immutable
final class FreeTransformEditContext extends EditContext {
  const FreeTransformEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.currentMode,
    required this.elementSnapshots,
    this.handleOffset,
    this.selectionRotation = 0.0,
  });
  final FreeTransformMode currentMode;
  final Map<String, ElementFullSnapshot> elementSnapshots;
  final DrawPoint? handleOffset;
  final double selectionRotation;

  @override
  bool get hasSnapshots => elementSnapshots.isNotEmpty;

  FreeTransformEditContext withMode(FreeTransformMode mode) =>
      FreeTransformEditContext(
        startPosition: startPosition,
        startBounds: startBounds,
        selectedIdsAtStart: selectedIdsAtStart,
        selectionVersion: selectionVersion,
        elementsVersion: elementsVersion,
        currentMode: mode,
        elementSnapshots: elementSnapshots,
        handleOffset: handleOffset,
        selectionRotation: selectionRotation,
      );
}

@immutable
class ElementFullSnapshot {
  const ElementFullSnapshot({
    required this.id,
    required this.center,
    required this.bounds,
    required this.rotation,
  });
  final String id;
  final DrawPoint center;
  final DrawRect bounds;
  final double rotation;
}
