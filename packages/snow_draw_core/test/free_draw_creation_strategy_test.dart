import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/snapping_mode.dart';

void main() {
  group('FreeDrawCreationStrategy', () {
    test(
      'update keeps element data identity and advances preview revision',
      () {
        const strategy = FreeDrawCreationStrategy();
        const data = FreeDrawData();
        const start = DrawPoint(x: 40, y: 50);

        final startResult = strategy.start(data: data, startPosition: start);
        final creatingState = _toCreatingState(
          result: startResult,
          startPosition: start,
        );

        final update = strategy.update(
          state: DrawState(),
          config: DrawConfig(),
          creatingState: creatingState,
          currentPosition: const DrawPoint(x: 70, y: 90),
          maintainAspectRatio: false,
          createFromCenter: false,
          snappingMode: SnappingMode.none,
        );

        expect(identical(update.data, creatingState.elementData), isTrue);
        final mode = update.creationMode as FreeDrawCreationMode;
        expect(mode.revision, 1);
        expect(mode.worldPoints, isNotNull);
        expect(mode.previewPath, isNull);
        expect(update.rect.maxX, greaterThan(creatingState.currentRect.maxX));
        expect(update.rect.maxY, greaterThan(creatingState.currentRect.maxY));
      },
    );

    test('non-solid strokes keep incremental preview path', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData(strokeStyle: StrokeStyle.dashed);
      const start = DrawPoint(x: 10, y: 10);

      final startResult = strategy.start(data: data, startPosition: start);
      final creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      final update = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 40, y: 25),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.previewPath, isNotNull);
      expect(mode.revision, 1);
    });

    test('solid updates advance revision even when bounds stay unchanged', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData();
      const start = DrawPoint.zero;

      final startResult = strategy.start(data: data, startPosition: start);
      var creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      final firstUpdate = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 100, y: 100),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );
      final firstMode = firstUpdate.creationMode as FreeDrawCreationMode;

      creatingState = creatingState.copyWith(
        element: creatingState.element.copyWith(data: firstUpdate.data),
        currentRect: firstUpdate.rect,
        creationMode: firstUpdate.creationMode,
      );

      final secondUpdate = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 20, y: 20),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final secondMode = secondUpdate.creationMode as FreeDrawCreationMode;
      expect(secondUpdate.rect, firstUpdate.rect);
      expect(secondMode.revision, firstMode.revision + 1);
    });

    test('sub-threshold updates keep creation mode stable', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData();
      const start = DrawPoint(x: 10, y: 10);

      final startResult = strategy.start(data: data, startPosition: start);
      final creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      final update = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 10.5, y: 10.5),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      expect(identical(update.creationMode, startResult.creationMode), isTrue);
      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.revision, 0);
      expect(update.rect, creatingState.currentRect);
    });

    test(
      'long straight strokes reuse tail point instead of growing forever',
      () {
        const strategy = FreeDrawCreationStrategy();
        const data = FreeDrawData();
        const start = DrawPoint.zero;

        final startResult = strategy.start(data: data, startPosition: start);
        var creatingState = _toCreatingState(
          result: startResult,
          startPosition: start,
        );

        for (final point in const [
          DrawPoint(x: 12, y: 0),
          DrawPoint(x: 24, y: 0),
          DrawPoint(x: 36, y: 0),
          DrawPoint(x: 48, y: 0),
          DrawPoint(x: 60, y: 0),
          DrawPoint(x: 72, y: 0),
        ]) {
          final update = strategy.update(
            state: DrawState(),
            config: DrawConfig(),
            creatingState: creatingState,
            currentPosition: point,
            maintainAspectRatio: false,
            createFromCenter: false,
            snappingMode: SnappingMode.none,
          );

          creatingState = creatingState.copyWith(
            element: creatingState.element.copyWith(data: update.data),
            currentRect: update.rect,
            creationMode: update.creationMode,
          );
        }

        final mode = creatingState.creationMode as FreeDrawCreationMode;
        final points = mode.worldPoints!;
        expect(points.length, lessThanOrEqualTo(4));
        expect(points.last.x, greaterThan(60));
      },
    );

    test('releasing line mode clears transient line segment state', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData();
      const start = DrawPoint(x: 20, y: 20);

      final startResult = strategy.start(data: data, startPosition: start);
      var creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      final withLine = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 45, y: 35),
        maintainAspectRatio: true,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final lineMode = withLine.creationMode as FreeDrawCreationMode;
      expect(lineMode.isLineActive, isTrue);
      expect(lineMode.lineAnchor, isNotNull);
      expect(lineMode.lineCurrent, isNotNull);

      creatingState = creatingState.copyWith(
        element: creatingState.element.copyWith(data: withLine.data),
        currentRect: withLine.rect,
        creationMode: withLine.creationMode,
      );

      final withoutLine = strategy.update(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 50, y: 40),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final freeMode = withoutLine.creationMode as FreeDrawCreationMode;
      expect(freeMode.isLineActive, isFalse);
      expect(freeMode.lineAnchor, isNull);
      expect(freeMode.lineCurrent, isNull);
      expect(freeMode.revision, greaterThan(lineMode.revision));
    });

    test('finish normalizes once and returns commit-ready data', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData();
      const start = DrawPoint(x: 100, y: 100);

      final startResult = strategy.start(data: data, startPosition: start);
      var creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      for (final point in const [
        DrawPoint(x: 130, y: 130),
        DrawPoint(x: 160, y: 120),
        DrawPoint(x: 190, y: 150),
      ]) {
        final update = strategy.update(
          state: DrawState(),
          config: DrawConfig(),
          creatingState: creatingState,
          currentPosition: point,
          maintainAspectRatio: false,
          createFromCenter: false,
          snappingMode: SnappingMode.none,
        );

        creatingState = creatingState.copyWith(
          element: creatingState.element.copyWith(data: update.data),
          currentRect: update.rect,
          creationMode: update.creationMode,
        );
      }

      final finish = strategy.finish(
        config: DrawConfig(),
        creatingState: creatingState,
      );

      expect(finish.shouldCommit, isTrue);
      final finishedData = finish.data as FreeDrawData;
      expect(finishedData.points.length, greaterThan(2));
      for (final point in finishedData.points) {
        expect(point.x, inInclusiveRange(0.0, 1.0));
        expect(point.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('updateBatch processes sampled points with one revision bump', () {
      const strategy = FreeDrawCreationStrategy();
      const data = FreeDrawData();
      const start = DrawPoint(x: 12, y: 18);

      final startResult = strategy.start(data: data, startPosition: start);
      final creatingState = _toCreatingState(
        result: startResult,
        startPosition: start,
      );

      final update = strategy.updateBatch(
        state: DrawState(),
        config: DrawConfig(),
        creatingState: creatingState,
        positions: const [
          DrawPoint(x: 18, y: 22),
          DrawPoint(x: 30, y: 36),
          DrawPoint(x: 48, y: 52),
        ],
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.revision, 1);
      expect(mode.worldPoints, isNotNull);
      expect(mode.worldPoints!.length, greaterThan(2));
      expect(update.rect.maxX, greaterThan(creatingState.currentRect.maxX));
      expect(update.rect.maxY, greaterThan(creatingState.currentRect.maxY));
    });
  });
}

CreatingState _toCreatingState({
  required CreationUpdateResult result,
  required DrawPoint startPosition,
}) {
  final element = ElementState(
    id: 'free-draw-test',
    rect: result.rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: result.data,
  );

  return CreatingState(
    element: element,
    startPosition: startPosition,
    currentRect: result.rect,
    creationMode: result.creationMode,
  );
}
