import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_pipeline/filter_segment.dart';
import 'package:snow_draw_core/ui/canvas/filter_pipeline/filter_segment_builder.dart';

void main() {
  const builder = FilterSegmentBuilder();

  test('build returns one batch for non-filter scene', () {
    final segments = builder.build(const [
      ElementState(
        id: 'e1',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      ),
      ElementState(
        id: 'e2',
        rect: DrawRect(minX: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: RectangleData(),
      ),
    ]);

    expect(segments.length, 1);
    expect(segments.first, isA<ElementBatchSegment>());
    final batch = segments.first as ElementBatchSegment;
    expect(batch.elements.length, 2);
  });

  test('build alternates batches and filters', () {
    final segments = builder.build(const [
      ElementState(
        id: 'e1',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      ),
      ElementState(
        id: 'f1',
        rect: DrawRect(minX: 5, maxX: 15, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(),
      ),
      ElementState(
        id: 'e2',
        rect: DrawRect(minX: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: RectangleData(),
      ),
    ]);

    expect(segments.length, 3);
    expect(segments[0], isA<ElementBatchSegment>());
    expect(segments[1], isA<FilterSegment>());
    expect(segments[2], isA<ElementBatchSegment>());
  });

  test('build handles consecutive filters without empty batches', () {
    final segments = builder.build(const [
      ElementState(
        id: 'f1',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      ),
      ElementState(
        id: 'f2',
        rect: DrawRect(minX: 5, maxX: 15, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(),
      ),
      ElementState(
        id: 'e1',
        rect: DrawRect(minX: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: RectangleData(),
      ),
    ]);

    expect(segments.length, 2);
    expect(segments[0], isA<MergedFilterSegment>());
    final merged = segments[0] as MergedFilterSegment;
    expect(merged.filters.length, 2);
    expect(segments[1], isA<ElementBatchSegment>());
    final batch = segments[1] as ElementBatchSegment;
    expect(batch.elements.length, 1);
  });

  test('build keeps different-type consecutive filters separate', () {
    final segments = builder.build(const [
      ElementState(
        id: 'f1',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(type: CanvasFilterType.mosaic),
      ),
      ElementState(
        id: 'f2',
        rect: DrawRect(minX: 5, maxX: 15, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(type: CanvasFilterType.grayscale),
      ),
      ElementState(
        id: 'e1',
        rect: DrawRect(minX: 10, maxX: 20, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: RectangleData(),
      ),
    ]);

    expect(segments.length, 3);
    expect(segments[0], isA<FilterSegment>());
    expect(segments[1], isA<FilterSegment>());
    expect(segments[2], isA<ElementBatchSegment>());
  });
}
