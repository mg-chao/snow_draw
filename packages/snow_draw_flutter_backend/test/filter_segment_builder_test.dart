import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

void main() {
  const builder = FilterSegmentBuilder();
  const rectA = DrawRect(maxX: 10, maxY: 10);
  const rectB = DrawRect(minX: 5, maxX: 15, maxY: 10);
  const rectC = DrawRect(minX: 10, maxX: 20, maxY: 10);

  ElementState rectangle({
    required String id,
    required DrawRect rect,
    required int zIndex,
  }) => ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: const RectangleData(),
  );

  ElementState filter({
    required String id,
    required DrawRect rect,
    required int zIndex,
    FilterData data = const FilterData(),
  }) => ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: data,
  );

  test('build returns one batch for non-filter scene', () {
    final segments = builder.build(
      List.unmodifiable([
        rectangle(id: 'e1', rect: rectA, zIndex: 0),
        rectangle(id: 'e2', rect: rectC, zIndex: 1),
      ]),
    );

    expect(segments.length, 1);
    expect(segments.first, isA<ElementBatchSegment>());
    final batch = segments.first as ElementBatchSegment;
    expect(batch.elements.length, 2);
  });

  test('build alternates batches and filters', () {
    final segments = builder.build(
      List.unmodifiable([
        rectangle(id: 'e1', rect: rectA, zIndex: 0),
        filter(id: 'f1', rect: rectB, zIndex: 1),
        rectangle(id: 'e2', rect: rectC, zIndex: 2),
      ]),
    );

    expect(segments.length, 3);
    expect(segments[0], isA<ElementBatchSegment>());
    expect(segments[1], isA<FilterSegment>());
    expect(segments[2], isA<ElementBatchSegment>());
  });

  test('build handles consecutive filters without empty batches', () {
    final segments = builder.build(
      List.unmodifiable([
        filter(id: 'f1', rect: rectA, zIndex: 0),
        filter(id: 'f2', rect: rectB, zIndex: 1),
        rectangle(id: 'e1', rect: rectC, zIndex: 2),
      ]),
    );

    expect(segments.length, 2);
    expect(segments[0], isA<MergedFilterSegment>());
    final merged = segments[0] as MergedFilterSegment;
    expect(merged.filters.length, 2);
    expect(segments[1], isA<ElementBatchSegment>());
    final batch = segments[1] as ElementBatchSegment;
    expect(batch.elements.length, 1);
  });

  test('build keeps different-type consecutive filters separate', () {
    final segments = builder.build(
      List.unmodifiable([
        filter(id: 'f1', rect: rectA, zIndex: 0),
        filter(
          id: 'f2',
          rect: rectB,
          zIndex: 1,
          data: const FilterData(type: CanvasFilterType.grayscale),
        ),
        rectangle(id: 'e1', rect: rectC, zIndex: 2),
      ]),
    );

    expect(segments.length, 3);
    expect(segments[0], isA<FilterSegment>());
    expect(segments[1], isA<FilterSegment>());
    expect(segments[2], isA<ElementBatchSegment>());
  });
}
