import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart'
    as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bridge.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_bridge relation snapshots', () {
    test(
      'collectCoreBindableRelations includes arrow ids for bound bindables',
      () {
        final target = _rectangleElement(
          id: 'rect-1',
          rect: const DrawRect(maxX: 100, maxY: 100),
          zIndex: 0,
        );
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 20, y: 20),
            DrawPoint(x: 140, y: 20),
          ],
          zIndex: 1,
          startBinding: const ArrowBinding(
            elementId: 'rect-1',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );

        final relations = collectCoreBindableRelations(<ElementState>[
          target,
          arrow,
        ]);

        expect(relations, hasLength(1));
        expect(relations.first.id, 'rect-1');
        expect(relations.first.boundArrowIds, <String>['arrow-1']);
      },
    );

    test('collectCoreBindableRelations includes unbound bindables '
        'with empty arrow lists', () {
      final first = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(maxX: 100, maxY: 100),
        zIndex: 0,
      );
      final second = _rectangleElement(
        id: 'rect-2',
        rect: const DrawRect(minX: 200, maxX: 300, maxY: 100),
        zIndex: 1,
      );
      final arrow = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 140, y: 20),
        ],
        zIndex: 2,
        endBinding: const ArrowBinding(
          elementId: 'rect-1',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
      );

      final relations = collectCoreBindableRelations(<ElementState>[
        first,
        second,
        arrow,
      ]);

      expect(relations, hasLength(2));
      expect(relations[0].id, 'rect-1');
      expect(relations[0].boundArrowIds, <String>['arrow-1']);
      expect(relations[1].id, 'rect-2');
      expect(relations[1].boundArrowIds, isEmpty);
    });

    test('collectCoreBindableRelations preserves arrow order from input', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(maxX: 100, maxY: 100),
        zIndex: 0,
      );
      final arrowB = _arrowElement(
        id: 'arrow-b',
        points: const <DrawPoint>[
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 140, y: 20),
        ],
        zIndex: 2,
        startBinding: const ArrowBinding(
          elementId: 'rect-1',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
      );
      final arrowA = _arrowElement(
        id: 'arrow-a',
        points: const <DrawPoint>[
          DrawPoint(x: 30, y: 30),
          DrawPoint(x: 130, y: 30),
        ],
        zIndex: 1,
        endBinding: const ArrowBinding(
          elementId: 'rect-1',
          anchor: DrawPoint(x: 0, y: 0.5),
        ),
      );

      final relations = collectCoreBindableRelations(<ElementState>[
        target,
        arrowB,
        arrowA,
      ]);

      expect(relations, hasLength(1));
      expect(relations.first.id, 'rect-1');
      expect(relations.first.boundArrowIds, <String>['arrow-b', 'arrow-a']);
    });
  });

  group('arrow_core_bridge document projection', () {
    test('collectCoreBindables preserves input order for z-order', () {
      final top = _rectangleElement(
        id: 'top',
        rect: const DrawRect(minX: 200, minY: 0, maxX: 260, maxY: 60),
        zIndex: 2,
      );
      final bottom = _rectangleElement(
        id: 'bottom',
        rect: const DrawRect(minX: 0, minY: 0, maxX: 60, maxY: 60),
        zIndex: 0,
      );
      final middle = _rectangleElement(
        id: 'middle',
        rect: const DrawRect(minX: 100, minY: 0, maxX: 160, maxY: 60),
        zIndex: 1,
      );

      final bindables = collectCoreBindables(<ElementState>[
        top,
        bottom,
        middle,
      ]);

      expect(bindables.map((bindable) => bindable.id).toList(), <String>[
        'top',
        'bottom',
        'middle',
      ]);
      expect(bindables.map((bindable) => bindable.zIndex).toList(), <double>[
        0,
        1,
        2,
      ]);
    });

    test(
      'collectCoreAnchorElementIdsByBindableId includes serial text anchors',
      () {
        final serial = _serialElement(
          id: 'serial-1',
          textElementId: 'text-1',
          zIndex: 0,
        );
        final text = _textElement(id: 'text-1', zIndex: 1);

        final anchors = collectCoreAnchorElementIdsByBindableId(<ElementState>[
          serial,
          text,
        ]);

        expect(anchors['serial-1'], <String>['serial-1', 'text-1']);
        expect(anchors['text-1'], <String>['text-1']);
      },
    );

    test(
      'projectCoreDocument carries anchor lookup and ordered ids override',
      () {
        final serial = _serialElement(
          id: 'serial-1',
          textElementId: 'text-1',
          zIndex: 0,
        );
        final text = _textElement(id: 'text-1', zIndex: 1);
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 30, y: 30),
            DrawPoint(x: 130, y: 30),
          ],
          zIndex: 2,
          startBinding: const ArrowBinding(
            elementId: 'serial-1',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
        );
        const orderOverride = <String>['serial-1', 'text-1', 'arrow-1'];

        final projection = projectCoreDocument(<ElementState>[
          arrow,
          text,
          serial,
        ], orderedElementIds: orderOverride);

        expect(projection.orderedElementIds, orderOverride);
        expect(
          projection.bindables.map((bindable) => bindable.id).toList(),
          <String>['serial-1', 'text-1'],
        );
        expect(projection.anchorElementIdsByBindableId['serial-1'], <String>[
          'serial-1',
          'text-1',
        ]);
        expect(projection.arrows, hasLength(1));
        expect(projection.arrowSources.keys, contains('arrow-1'));
      },
    );

    test(
      'projectCoreDocument appends missing ids from element snapshot order',
      () {
        final serial = _serialElement(
          id: 'serial-1',
          textElementId: 'text-1',
          zIndex: 0,
        );
        final text = _textElement(id: 'text-1', zIndex: 1);
        final arrow = _arrowElement(
          id: 'arrow-1',
          points: const <DrawPoint>[
            DrawPoint(x: 30, y: 30),
            DrawPoint(x: 130, y: 30),
          ],
          zIndex: 2,
        );

        final projection = projectCoreDocument(
          <ElementState>[arrow, text, serial],
          orderedElementIds: const <String>['serial-1'],
        );

        expect(projection.orderedElementIds, const <String>[
          'serial-1',
          'arrow-1',
          'text-1',
        ]);
      },
    );

    test(
      'toCoreBindableState maps text corner radius to adaptive roundness',
      () {
        const text = ElementState(
          id: 'text-1',
          rect: DrawRect(minX: 100, minY: 60, maxX: 260, maxY: 140),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: TextData(text: 'rounded', cornerRadius: 14, strokeWidth: 3),
        );

        final bindable = toCoreBindableState(text);

        expect(bindable, isNotNull);
        expect(bindable!.shape, 'rectangle');
        expect(bindable.strokeWidth, 3);
        expect(bindable.roundness, isNotNull);
        expect(bindable.roundness!.type, 'adaptive');
        expect(bindable.roundness!.value, 14);
      },
    );

    test('toCoreBindableState maps highlight ellipse as ellipse bindable', () {
      const highlight = ElementState(
        id: 'highlight-1',
        rect: DrawRect(minX: 80, minY: 40, maxX: 200, maxY: 160),
        rotation: 0,
        opacity: 1,
        zIndex: 5,
        data: HighlightData(shape: HighlightShape.ellipse, strokeWidth: 2),
      );

      final bindable = toCoreBindableState(highlight);

      expect(bindable, isNotNull);
      expect(bindable!.shape, 'ellipse');
      expect(bindable.strokeWidth, 2);
      expect(bindable.zIndex, 5);
    });

    test('fromCoreBinding preserves out-of-range fixed-point ratios', () {
      final binding = fromCoreBinding(
        core.FixedPointBinding(
          elementId: 'rect-1',
          fixedPoint: const <double>[-0.2, 1.25],
          mode: core.bindModeOrbit,
        ),
      );

      expect(binding, isNotNull);
      expect(binding!.anchor.x, closeTo(-0.2, 1e-9));
      expect(binding.anchor.y, closeTo(1.25, 1e-9));
    });

    test('fromCoreBinding preserves skip bind mode', () {
      final binding = fromCoreBinding(
        core.FixedPointBinding(
          elementId: 'rect-1',
          fixedPoint: const <double>[0.5, 0.5],
          mode: core.bindModeSkip,
        ),
      );

      expect(binding, isNotNull);
      expect(binding!.mode, ArrowBindingMode.skip);
      final roundTripped = toCoreBinding(binding);
      expect(roundTripped, isNotNull);
      expect(roundTripped!.mode, core.bindModeSkip);
    });

    test(
      'applyCoreArrowPatchToElement applies binding-only patches without geometry drift',
      () {
        final element = _arrowElement(
          id: 'arrow-geometry-stable',
          points: const <DrawPoint>[
            DrawPoint(x: 20, y: 40),
            DrawPoint(x: 120, y: 60),
          ],
          zIndex: 2,
        );
        final data = element.data as ArrowData;

        final patched = applyCoreArrowPatchToElement(
          element: element,
          data: data,
          patch: <String, dynamic>{
            'startBinding': core.FixedPointBinding(
              elementId: 'rect-1',
              fixedPoint: const <double>[0.25, 0.75],
              mode: core.bindModeInside,
            ),
          },
        );
        final patchedData = patched.data as ArrowData;

        expect(patched.rect, element.rect);
        expect(patchedData.points, data.points);
        expect(
          patchedData.startBinding,
          const ArrowBinding(
            elementId: 'rect-1',
            anchor: DrawPoint(x: 0.25, y: 0.75),
            mode: ArrowBindingMode.inside,
          ),
        );
        expect(patchedData.endBinding, isNull);
      },
    );

    test(
      'applyCoreArrowPatchToElement accepts map-shaped binding patch values',
      () {
        final element = _arrowElement(
          id: 'arrow-map-patch',
          points: const <DrawPoint>[
            DrawPoint(x: 0, y: 0),
            DrawPoint(x: 100, y: 0),
          ],
          zIndex: 3,
        );
        final data = element.data as ArrowData;

        final patched = applyCoreArrowPatchToElement(
          element: element,
          data: data,
          patch: <String, dynamic>{
            'endBinding': <String, dynamic>{
              'elementId': 'rect-2',
              'fixedPoint': <double>[1, 0.5],
              'mode': core.bindModeOrbit,
            },
          },
        );
        final patchedData = patched.data as ArrowData;

        expect(
          patchedData.endBinding,
          const ArrowBinding(
            elementId: 'rect-2',
            anchor: DrawPoint(x: 1, y: 0.5),
            mode: ArrowBindingMode.orbit,
          ),
        );
        expect(patchedData.points, data.points);
      },
    );

    test('applyCoreArrowPatchToElement applies fixed-segment-only patches '
        'without geometry drift', () {
      final base = _arrowElement(
        id: 'arrow-fixed-segment-patch',
        points: const <DrawPoint>[
          DrawPoint(x: 40, y: 20),
          DrawPoint(x: 160, y: 80),
        ],
        zIndex: 4,
      );
      final data = (base.data as ArrowData).copyWith(
        arrowType: ArrowType.elbow,
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 1,
            start: DrawPoint(x: 72, y: 20),
            end: DrawPoint(x: 72, y: 80),
          ),
        ],
      );
      final element = base.copyWith(rotation: 0.37, data: data);
      const patch = <String, dynamic>{
        'fixedSegments': <core.FixedSegment>[
          core.FixedSegment(
            index: 1,
            start: <double>[90, 16],
            end: <double>[90, 72],
          ),
        ],
      };
      final expectedArrow = core.applyArrowPatch(
        toCoreArrowState(element: element, data: data),
        patch,
      );
      final expectedFixedSegments = toLocalFixedSegmentsFromCoreArrow(
        expectedArrow,
        element,
      );

      final patched = applyCoreArrowPatchToElement(
        element: element,
        data: data,
        patch: patch,
      );
      final patchedData = patched.data as ArrowData;

      expect(patched.rect, element.rect);
      expect(patchedData.points, data.points);
      expect(patchedData.fixedSegments, expectedFixedSegments);
    });

    test('applyCoreArrowPatchToElement accepts map-shaped fixed-segment '
        'patch values', () {
      final base = _arrowElement(
        id: 'arrow-fixed-segment-map-patch',
        points: const <DrawPoint>[
          DrawPoint(x: 40, y: 20),
          DrawPoint(x: 160, y: 80),
        ],
        zIndex: 5,
      );
      final data = (base.data as ArrowData).copyWith(
        arrowType: ArrowType.elbow,
      );
      final element = base.copyWith(data: data);
      final patch = <String, dynamic>{
        'fixedSegments': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'start': <double>[90, 16],
            'end': <double>[90, 72],
          },
        ],
      };

      final patched = applyCoreArrowPatchToElement(
        element: element,
        data: data,
        patch: patch,
      );
      final patchedData = patched.data as ArrowData;

      expect(patchedData.fixedSegments, isNotNull);
      expect(patchedData.fixedSegments, hasLength(1));
      expect(patchedData.fixedSegments!.first.index, 1);
    });
  });
}

ElementState _rectangleElement({
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

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}

ElementState _serialElement({
  required String id,
  required int zIndex,
  String? textElementId,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: SerialNumberData(textElementId: textElementId),
);

ElementState _textElement({required String id, required int zIndex}) =>
    ElementState(
      id: id,
      rect: const DrawRect(minX: 100, maxX: 200, maxY: 50),
      rotation: 0,
      opacity: 1,
      zIndex: zIndex,
      data: const TextData(text: 'anchor'),
    );
