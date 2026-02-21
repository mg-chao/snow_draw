import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_style_state_change.dart';

void main() {
  group('resolveFilterStyleMutation', () {
    test('returns changed ids for filter payload changes', () {
      final previous = _buildStateWithFilter(
        filterData: const FilterData(strength: 0.2),
      );
      final next = _buildStateWithFilter(
        filterData: const FilterData(strength: 0.9),
      );

      final mutation = resolveFilterStyleMutation(
        previous: previous,
        next: next,
      );
      expect(mutation?.changedFilterElementIds, {'filter'});
    });

    test('returns changed ids for filter opacity changes', () {
      final previous = _buildStateWithFilter();
      final next = _buildStateWithFilter(filterOpacity: 0.45);

      final mutation = resolveFilterStyleMutation(
        previous: previous,
        next: next,
      );
      expect(mutation?.changedFilterElementIds, {'filter'});
    });

    test('returns null when a non-filter element changes', () {
      final previous = _buildStateWithFilter();
      final next = _buildStateWithFilter(baseElement: _mutatedBaseElement);

      expect(
        resolveFilterStyleMutation(previous: previous, next: next),
        isNull,
      );
    });

    test('returns null when filter geometry changes', () {
      final previous = _buildStateWithFilter(
        filterData: const FilterData(type: CanvasFilterType.grayscale),
      );
      final next = _buildStateWithFilter(
        filterRect: const DrawRect(minX: 24, minY: 20, maxX: 84, maxY: 80),
        filterData: const FilterData(type: CanvasFilterType.grayscale),
      );

      expect(
        resolveFilterStyleMutation(previous: previous, next: next),
        isNull,
      );
    });

    test('returns null when selection state changes', () {
      final previous = _buildStateWithFilter(
        filterData: const FilterData(strength: 0.2),
      );
      final next = _buildStateWithFilter(
        filterData: const FilterData(strength: 0.6),
        selectedIds: const {},
      );

      expect(
        resolveFilterStyleMutation(previous: previous, next: next),
        isNull,
      );
    });
  });
}

const _baseElement = ElementState(
  id: 'base',
  rect: DrawRect(maxX: 200, maxY: 200),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

const _mutatedBaseElement = ElementState(
  id: 'base',
  rect: DrawRect(maxX: 200, maxY: 200),
  rotation: 0,
  opacity: 0.5,
  zIndex: 0,
  data: RectangleData(),
);

const _filterRect = DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80);

DrawState _buildStateWithFilter({
  ElementState baseElement = _baseElement,
  DrawRect filterRect = _filterRect,
  FilterData filterData = const FilterData(),
  double filterOpacity = 1,
  Set<String> selectedIds = const {'filter'},
}) => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: [
        baseElement,
        ElementState(
          id: 'filter',
          rect: filterRect,
          rotation: 0,
          opacity: filterOpacity,
          zIndex: 1,
          data: filterData,
        ),
      ],
    ),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);
