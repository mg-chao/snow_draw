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
        final harness = _FreeDrawTestHarness.start(
          start: const DrawPoint(x: 40, y: 50),
        );
        final update = harness.update(const DrawPoint(x: 70, y: 90));

        expect(
          identical(update.data, harness.creatingState.elementData),
          isTrue,
        );
        final mode = update.creationMode as FreeDrawCreationMode;
        expect(mode.revision, 1);
        expect(mode.worldPoints, isNotNull);
        expect(mode.previewPath, isNull);
        expect(
          update.rect.maxX,
          greaterThan(harness.creatingState.currentRect.maxX),
        );
        expect(
          update.rect.maxY,
          greaterThan(harness.creatingState.currentRect.maxY),
        );
      },
    );

    test('non-solid strokes keep incremental preview path', () {
      final harness = _FreeDrawTestHarness.start(
        data: const FreeDrawData(strokeStyle: StrokeStyle.dashed),
        start: const DrawPoint(x: 10, y: 10),
      );
      final update = harness.update(const DrawPoint(x: 40, y: 25));

      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.previewPath, isNotNull);
      expect(mode.revision, 1);
    });

    test('solid updates advance revision even when bounds stay unchanged', () {
      final harness = _FreeDrawTestHarness.start();
      final firstUpdate = harness.step(const DrawPoint(x: 100, y: 100));
      final firstMode = firstUpdate.creationMode as FreeDrawCreationMode;

      final secondUpdate = harness.update(const DrawPoint(x: 20, y: 20));

      final secondMode = secondUpdate.creationMode as FreeDrawCreationMode;
      expect(secondUpdate.rect, firstUpdate.rect);
      expect(secondMode.revision, firstMode.revision + 1);
    });

    test('sub-threshold updates keep creation mode stable', () {
      final harness = _FreeDrawTestHarness.start(
        start: const DrawPoint(x: 10, y: 10),
      );
      final update = harness.update(const DrawPoint(x: 10.5, y: 10.5));

      expect(
        identical(update.creationMode, harness.creatingState.creationMode),
        isTrue,
      );
      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.revision, 0);
      expect(update.rect, harness.creatingState.currentRect);
    });

    test(
      'long straight strokes reuse tail point instead of growing forever',
      () {
        final harness = _FreeDrawTestHarness.start();
        harness.draw(const [
          DrawPoint(x: 12, y: 0),
          DrawPoint(x: 24, y: 0),
          DrawPoint(x: 36, y: 0),
          DrawPoint(x: 48, y: 0),
          DrawPoint(x: 60, y: 0),
          DrawPoint(x: 72, y: 0),
        ]);

        final mode = harness.creatingState.creationMode as FreeDrawCreationMode;
        final points = mode.worldPoints!;
        expect(points.length, lessThanOrEqualTo(4));
        expect(points.last.x, greaterThan(60));
      },
    );

    test('releasing line mode clears transient line segment state', () {
      final harness = _FreeDrawTestHarness.start(
        start: const DrawPoint(x: 20, y: 20),
      );
      final withLine = harness.step(
        const DrawPoint(x: 45, y: 35),
        maintainAspectRatio: true,
      );

      final lineMode = withLine.creationMode as FreeDrawCreationMode;
      expect(lineMode.isLineActive, isTrue);
      expect(lineMode.lineAnchor, isNotNull);
      expect(lineMode.lineCurrent, isNotNull);

      final withoutLine = harness.update(const DrawPoint(x: 50, y: 40));

      final freeMode = withoutLine.creationMode as FreeDrawCreationMode;
      expect(freeMode.isLineActive, isFalse);
      expect(freeMode.lineAnchor, isNull);
      expect(freeMode.lineCurrent, isNull);
      expect(freeMode.revision, greaterThan(lineMode.revision));
    });

    test('finish normalizes once and returns commit-ready data', () {
      final harness = _FreeDrawTestHarness.start(
        start: const DrawPoint(x: 100, y: 100),
      );
      harness.draw(const [
        DrawPoint(x: 130, y: 130),
        DrawPoint(x: 160, y: 120),
        DrawPoint(x: 190, y: 150),
      ]);
      final finish = harness.finish();

      expect(finish.shouldCommit, isTrue);
      final finishedData = finish.data as FreeDrawData;
      expect(finishedData.points.length, greaterThan(2));
      for (final point in finishedData.points) {
        expect(point.x, inInclusiveRange(0.0, 1.0));
        expect(point.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('updateBatch processes sampled points with one revision bump', () {
      final harness = _FreeDrawTestHarness.start(
        start: const DrawPoint(x: 12, y: 18),
      );
      final update = harness.updateBatch(const [
        DrawPoint(x: 18, y: 22),
        DrawPoint(x: 30, y: 36),
        DrawPoint(x: 48, y: 52),
      ]);

      final mode = update.creationMode as FreeDrawCreationMode;
      expect(mode.revision, 1);
      expect(mode.worldPoints, isNotNull);
      expect(mode.worldPoints!.length, greaterThan(2));
      expect(
        update.rect.maxX,
        greaterThan(harness.creatingState.currentRect.maxX),
      );
      expect(
        update.rect.maxY,
        greaterThan(harness.creatingState.currentRect.maxY),
      );
    });
  });
}

class _FreeDrawTestHarness {
  _FreeDrawTestHarness._({required this.strategy, required this.creatingState});

  final FreeDrawCreationStrategy strategy;
  CreatingState creatingState;

  static _FreeDrawTestHarness start({
    FreeDrawData data = const FreeDrawData(),
    DrawPoint start = DrawPoint.zero,
  }) {
    const strategy = FreeDrawCreationStrategy();
    final result = strategy.start(data: data, startPosition: start);
    return _FreeDrawTestHarness._(
      strategy: strategy,
      creatingState: _toCreatingState(result: result, startPosition: start),
    );
  }

  CreationUpdateResult update(
    DrawPoint currentPosition, {
    bool maintainAspectRatio = false,
  }) {
    return strategy.update(
      state: DrawState(),
      config: DrawConfig(),
      creatingState: creatingState,
      currentPosition: currentPosition,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: false,
      snappingMode: SnappingMode.none,
    );
  }

  CreationUpdateResult updateBatch(
    List<DrawPoint> positions, {
    bool maintainAspectRatio = false,
  }) {
    return strategy.updateBatch(
      state: DrawState(),
      config: DrawConfig(),
      creatingState: creatingState,
      positions: positions,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: false,
      snappingMode: SnappingMode.none,
    );
  }

  CreationUpdateResult step(
    DrawPoint currentPosition, {
    bool maintainAspectRatio = false,
  }) {
    final update = this.update(
      currentPosition,
      maintainAspectRatio: maintainAspectRatio,
    );
    apply(update);
    return update;
  }

  void draw(List<DrawPoint> points) {
    for (final point in points) {
      step(point);
    }
  }

  void apply(CreationUpdateResult update) {
    creatingState = creatingState.copyWith(
      element: creatingState.element.copyWith(data: update.data),
      currentRect: update.rect,
      creationMode: update.creationMode,
    );
  }

  CreationFinishResult finish() {
    return strategy.finish(config: DrawConfig(), creatingState: creatingState);
  }
}

CreatingState _toCreatingState({
  required CreationUpdateResult result,
  required DrawPoint startPosition,
}) {
  return CreatingState(
    element: ElementState(
      id: 'free-draw-test',
      rect: result.rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: result.data,
    ),
    startPosition: startPosition,
    currentRect: result.rect,
    creationMode: result.creationMode,
  );
}
