import 'package:test/test.dart';
import 'package:snow_draw_core/draw/edit/core/edit_compute_pipeline.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  setUp(ArrowBindingResolver.instance.invalidate);

  DrawState stateWith(List<ElementState> elements) => DrawState(
    domain: DomainState(document: DocumentState(elements: elements)),
  );

  ElementState rect0({
    required String id,
    DrawRect rect = const DrawRect(maxX: 100, maxY: 100),
  }) => ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: const RectangleData(),
  );

  ElementState arrow0({
    required String id,
    required List<DrawPoint> points,
    ArrowBinding? startBinding,
    ArrowBinding? endBinding,
  }) {
    final rect = _rectForPoints(points);
    return ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: ArrowData(
        points: ArrowGeometry.normalizePoints(worldPoints: points, rect: rect),
        startBinding: startBinding,
        endBinding: endBinding,
      ),
    );
  }

  ({ElementState target, ElementState arrow, DrawState state})
  boundArrowFixture({String arrowId = 'boundArrow'}) {
    final target = rect0(
      id: 'target',
      rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
    );
    final arrow = arrow0(
      id: arrowId,
      points: const [DrawPoint(x: 10, y: 80), DrawPoint(x: 200, y: 80)],
      startBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
    );
    return (target: target, arrow: arrow, state: stateWith([target, arrow]));
  }

  group('EditComputePipeline.finalize', () {
    test('returns null for empty updatedById', () {
      final state = stateWith([rect0(id: 'r1')]);
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {},
      );
      expect(result, isNull);
    });

    test('returns result with updated elements for non-empty map', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
      );
      expect(result, isNotNull);
      expect(result!.updatedElements['r1']!.rect.minX, 10);
    });

    test(
      'keeps caller map untouched when no post-processing updates are needed',
      () {
        final r1 = rect0(id: 'r1');
        final state = stateWith([r1]);
        final moved = r1.copyWith(
          rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
        );
        final callerMap = <String, ElementState>{'r1': moved};

        final result = EditComputePipeline.finalize(
          state: state,
          updatedById: callerMap,
        );

        expect(result, isNotNull);
        expect(identical(callerMap['r1'], moved), isTrue);
        expect(identical(result!.updatedElements['r1'], moved), isTrue);
      },
    );

    test('does not mutate the caller map keys', () {
      final fixture = boundArrowFixture();
      final movedTarget = fixture.target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final callerMap = <String, ElementState>{'target': movedTarget};
      final keysBefore = callerMap.keys.toSet();

      EditComputePipeline.finalize(
        state: fixture.state,
        updatedById: callerMap,
      );

      expect(callerMap.keys.toSet(), equals(keysBefore));
    });

    test('does not mutate the caller map values', () {
      final fixture = boundArrowFixture(arrowId: 'arrow');
      final movedArrow = fixture.arrow.copyWith(
        rect: const DrawRect(minX: 60, minY: 79, maxX: 250, maxY: 81),
      );
      final callerMap = <String, ElementState>{'arrow': movedArrow};

      EditComputePipeline.finalize(
        state: fixture.state,
        updatedById: callerMap,
      );

      expect(identical(callerMap['arrow'], movedArrow), isTrue);
    });

    test('unbinds arrow-like elements in the result', () {
      final fixture = boundArrowFixture(arrowId: 'arrow');
      final movedArrow = fixture.arrow.copyWith(
        rect: const DrawRect(minX: 60, minY: 79, maxX: 250, maxY: 81),
      );
      final result = EditComputePipeline.finalize(
        state: fixture.state,
        updatedById: {'arrow': movedArrow},
      );

      expect(result, isNotNull);
      final resultArrow = result!.updatedElements['arrow']!;
      final data = resultArrow.data as ArrowData;
      expect(data.startBinding, isNull);
    });

    test('passes through multiSelectBounds and multiSelectRotation', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      const bounds = DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110);
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
        multiSelectBounds: bounds,
        multiSelectRotation: 1.5,
      );
      expect(result!.multiSelectBounds, equals(bounds));
      expect(result.multiSelectRotation, 1.5);
    });

    test('skipBindingUpdate predicate excludes elements', () {
      final fixture = boundArrowFixture();
      final movedTarget = fixture.target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final result = EditComputePipeline.finalize(
        state: fixture.state,
        updatedById: {'target': movedTarget},
        skipBindingUpdate: (id, _) => id == fixture.arrow.id,
      );

      expect(result, isNotNull);
      expect(result!.updatedElements.containsKey(fixture.arrow.id), isFalse);
    });

    test('resolves bindings when bound target moves', () {
      final fixture = boundArrowFixture();
      final movedTarget = fixture.target.copyWith(
        rect: const DrawRect(minX: 300, minY: 40, maxX: 380, maxY: 120),
      );
      final result = EditComputePipeline.finalize(
        state: fixture.state,
        updatedById: {'target': movedTarget},
      );

      expect(result, isNotNull);
      expect(result!.updatedElements.containsKey(fixture.arrow.id), isTrue);
    });

    test('skips unrelated arrow binding updates for non-bindable elements', () {
      final fixture = boundArrowFixture();
      const freeDraw = ElementState(
        id: 'free',
        rect: DrawRect(minX: 20, minY: 20, maxX: 60, maxY: 60),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: FreeDrawData(),
      );
      final state = stateWith([fixture.target, fixture.arrow, freeDraw]);

      final movedFreeDraw = freeDraw.copyWith(
        rect: const DrawRect(minX: 40, minY: 24, maxX: 80, maxY: 64),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'free': movedFreeDraw},
      );

      expect(result, isNotNull);
      expect(result!.updatedElements.keys.toSet(), equals(const {'free'}));
    });

    test('result updatedElements is unmodifiable', () {
      final r1 = rect0(id: 'r1');
      final state = stateWith([r1]);
      final moved = r1.copyWith(
        rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
      );
      final result = EditComputePipeline.finalize(
        state: state,
        updatedById: {'r1': moved},
      );
      expect(result, isNotNull);
      expect(
        () => result!.updatedElements['new'] = moved,
        throwsUnsupportedError,
      );
    });
  });
}

DrawRect _rectForPoints(List<DrawPoint> points) {
  assert(points.isNotEmpty);

  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    minX = point.x < minX ? point.x : minX;
    maxX = point.x > maxX ? point.x : maxX;
    minY = point.y < minY ? point.y : minY;
    maxY = point.y > maxY ? point.y : maxY;
  }

  return DrawRect(
    minX: minX,
    minY: minY,
    maxX: maxX == minX ? minX + 1 : maxX,
    maxY: maxY == minY ? minY + 1 : maxY,
  );
}
