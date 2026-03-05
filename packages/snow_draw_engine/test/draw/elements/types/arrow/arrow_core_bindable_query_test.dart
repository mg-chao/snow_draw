import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core_bindable_query.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_core_bindable_query', () {
    test('orders resolved candidates by document z-order', () {
      final first = _rectangleElement(
        id: 'first',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
      );
      final second = _rectangleElement(
        id: 'second',
        rect: const DrawRect(minX: 140, minY: 20, maxX: 240, maxY: 120),
      );
      final third = _rectangleElement(
        id: 'third',
        rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
      );
      final document = DocumentState(
        elements: <ElementState>[first, second, third],
      );

      final resolved = resolveCoreBindableCandidates(
        document: document,
        worldPoint: const DrawPoint(x: 160, y: 70),
        distance: 320,
        preferredBinding: const ArrowBinding(
          elementId: 'third',
          anchor: DrawPoint(x: 0.5, y: 0.5),
        ),
      );

      expect(resolved.elements.map((element) => element.id).toList(), <String>[
        'first',
        'second',
        'third',
      ]);
    });

    test('reuses document-cached arrow-core bindables by identity', () {
      final first = _rectangleElement(
        id: 'first',
        rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
      );
      final second = _rectangleElement(
        id: 'second',
        rect: const DrawRect(minX: 140, minY: 20, maxX: 240, maxY: 120),
      );
      final third = _rectangleElement(
        id: 'third',
        rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
      );
      final document = DocumentState(
        elements: <ElementState>[first, second, third],
      );
      final cachedById = {
        for (final bindable in document.arrowCoreBindables)
          bindable.id: bindable,
      };

      final resolved = resolveCoreBindableCandidates(
        document: document,
        worldPoint: const DrawPoint(x: 160, y: 70),
        distance: 320,
      );

      expect(resolved.bindables, hasLength(3));
      for (final bindable in resolved.bindables) {
        expect(identical(bindable, cachedById[bindable.id]), isTrue);
      }
    });

    test(
      'includeNearby=false keeps preferred/opposite bindings in z-order',
      () {
        final first = _rectangleElement(
          id: 'first',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
        );
        final second = _rectangleElement(
          id: 'second',
          rect: const DrawRect(minX: 140, minY: 20, maxX: 240, maxY: 120),
        );
        final third = _rectangleElement(
          id: 'third',
          rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
        );
        final document = DocumentState(
          elements: <ElementState>[first, second, third],
        );

        final resolved = resolveCoreBindableCandidates(
          document: document,
          worldPoint: const DrawPoint(x: -9999, y: -9999),
          distance: 0,
          includeNearby: false,
          preferredBinding: const ArrowBinding(
            elementId: 'third',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
          oppositeBinding: const ArrowBinding(
            elementId: 'first',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
        );

        expect(
          resolved.elements.map((element) => element.id).toList(),
          <String>['first', 'third'],
        );
      },
    );

    test(
      'endpoint strategy candidates include all bindables when new binding is allowed',
      () {
        final first = _rectangleElement(
          id: 'first',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
        );
        final second = _rectangleElement(
          id: 'second',
          rect: const DrawRect(minX: 140, minY: 20, maxX: 240, maxY: 120),
        );
        final third = _rectangleElement(
          id: 'third',
          rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
        );
        final document = DocumentState(
          elements: <ElementState>[first, second, third],
        );

        final resolved = resolveCoreBindableCandidatesForEndpointStrategy(
          document: document,
          allowNewBinding: true,
        );

        expect(
          resolved.elements.map((element) => element.id).toList(),
          <String>['first', 'second', 'third'],
        );
      },
    );

    test(
      'endpoint strategy candidates keep only bound targets when new binding is disabled',
      () {
        final first = _rectangleElement(
          id: 'first',
          rect: const DrawRect(minX: 20, minY: 20, maxX: 120, maxY: 120),
        );
        final second = _rectangleElement(
          id: 'second',
          rect: const DrawRect(minX: 140, minY: 20, maxX: 240, maxY: 120),
        );
        final third = _rectangleElement(
          id: 'third',
          rect: const DrawRect(minX: 260, minY: 20, maxX: 360, maxY: 120),
        );
        final document = DocumentState(
          elements: <ElementState>[first, second, third],
        );

        final resolved = resolveCoreBindableCandidatesForEndpointStrategy(
          document: document,
          activeBinding: const ArrowBinding(
            elementId: 'third',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
          oppositeBinding: const ArrowBinding(
            elementId: 'first',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
          allowNewBinding: false,
        );

        expect(
          resolved.elements.map((element) => element.id).toList(),
          <String>['first', 'third'],
        );
      },
    );
  });
}

ElementState _rectangleElement({required String id, required DrawRect rect}) =>
    ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );
