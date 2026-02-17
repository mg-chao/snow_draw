import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/snap_guides.dart';
import 'package:snow_draw_core/ui/canvas/free_draw_creation_state_change.dart';

void main() {
  group('isFreeDrawPreviewMutationOnly', () {
    test('returns true when only free-draw preview payload changes', () {
      final baseState = DrawState();
      final previous = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 8, y: 8)],
          revision: 1,
        ),
        currentRect: const DrawRect(maxX: 8, maxY: 8),
      );
      final next = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 12, y: 12)],
          revision: 2,
        ),
        currentRect: const DrawRect(maxX: 12, maxY: 12),
      );

      expect(
        isFreeDrawPreviewMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false when snap guides change', () {
      final baseState = DrawState();
      final previous = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 8, y: 8)],
          revision: 1,
        ),
        currentRect: const DrawRect(maxX: 8, maxY: 8),
      );
      final next = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 12, y: 12)],
          revision: 2,
        ),
        currentRect: const DrawRect(maxX: 12, maxY: 12),
        snapGuides: const [
          SnapGuide(
            kind: SnapGuideKind.point,
            axis: SnapGuideAxis.horizontal,
            start: DrawPoint(x: 1, y: 1),
            end: DrawPoint(x: 2, y: 1),
          ),
        ],
      );

      expect(
        isFreeDrawPreviewMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when domain changes', () {
      final baseState = DrawState();
      final previous = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 8, y: 8)],
          revision: 1,
        ),
        currentRect: const DrawRect(maxX: 8, maxY: 8),
      );
      final next = _stateWithFreeDrawCreating(
        baseState: baseState,
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 12, y: 12)],
          revision: 2,
        ),
        currentRect: const DrawRect(maxX: 12, maxY: 12),
      ).copyWith(domain: previous.domain.withSelected('other-element'));

      expect(
        isFreeDrawPreviewMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when creation session changes', () {
      final baseState = DrawState();
      final previous = _stateWithFreeDrawCreating(
        baseState: baseState,
        elementId: 'free-draw-1',
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 8, y: 8)],
          revision: 1,
        ),
        currentRect: const DrawRect(maxX: 8, maxY: 8),
      );
      final next = _stateWithFreeDrawCreating(
        baseState: baseState,
        elementId: 'free-draw-2',
        mode: const FreeDrawCreationMode(
          worldPoints: <DrawPoint>[DrawPoint.zero, DrawPoint(x: 12, y: 12)],
          revision: 2,
        ),
        currentRect: const DrawRect(maxX: 12, maxY: 12),
      );

      expect(
        isFreeDrawPreviewMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });
}

DrawState _stateWithFreeDrawCreating({
  required FreeDrawCreationMode mode,
  required DrawRect currentRect,
  DrawState? baseState,
  String elementId = 'free-draw',
  List<SnapGuide> snapGuides = const <SnapGuide>[],
}) {
  const data = FreeDrawData();
  final element = ElementState(
    id: elementId,
    rect: const DrawRect(maxX: 1, maxY: 1),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: data,
  );
  final interaction = CreatingState(
    element: element,
    startPosition: DrawPoint.zero,
    currentRect: currentRect,
    snapGuides: snapGuides,
    creationMode: mode,
  );
  final state = baseState ?? DrawState();
  return state.copyWith(
    application: state.application.copyWith(interaction: interaction),
  );
}
