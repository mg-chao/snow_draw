import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/reducers/core/arrow_binding_sync.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_binding_sync duplication parity', () {
    test('mixed snapshots only remap duplicated arrows', () {
      final originals = _buildBaseElements();
      const idMap = <String, String>{
        'r1': 'dup-r1',
        'r2': 'dup-r2',
        'a1': 'dup-a1',
      };
      final duplicates = _duplicateElements(
        elements: originals,
        idMap: idMap,
        offsetX: 24,
        offsetY: 16,
        startZIndex: originals.length,
      );
      final combined = <ElementState>[...originals, ...duplicates];

      final synced = syncArrowBindingsAfterDuplication(
        elements: combined,
        idMap: idMap,
      );

      final sourceArrow = _arrowDataById(synced, 'a1');
      final duplicateArrow = _arrowDataById(synced, 'dup-a1');

      expect(sourceArrow.startBinding?.elementId, 'r1');
      expect(sourceArrow.endBinding?.elementId, 'r2');
      expect(duplicateArrow.startBinding?.elementId, 'dup-r1');
      expect(duplicateArrow.endBinding?.elementId, 'dup-r2');
      expect(
        synced.map((element) => element.id).toList(growable: false),
        combined.map((element) => element.id).toList(growable: false),
      );
    });

    test('duplicate-only snapshots still remap duplicated arrows', () {
      final originals = _buildBaseElements();
      const idMap = <String, String>{
        'r1': 'dup-r1',
        'r2': 'dup-r2',
        'a1': 'dup-a1',
      };
      final duplicates = _duplicateElements(
        elements: originals,
        idMap: idMap,
        offsetX: 24,
        offsetY: 16,
        startZIndex: 0,
      );

      final synced = syncArrowBindingsAfterDuplication(
        elements: duplicates,
        idMap: idMap,
      );

      final duplicateArrow = _arrowDataById(synced, 'dup-a1');
      expect(duplicateArrow.startBinding?.elementId, 'dup-r1');
      expect(duplicateArrow.endBinding?.elementId, 'dup-r2');
    });
  });

  group('arrow_binding_sync deletion parity', () {
    test('repairs bindings when only deleted ids are provided', () {
      const retainedBindable = ElementState(
        id: 'r2',
        rect: DrawRect(minX: 300, maxX: 400, maxY: 100),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final retainedArrow = _buildArrow(
        id: 'a1',
        startTargetId: 'deleted-r1',
        endTargetId: 'r2',
        offsetX: 0,
        offsetY: 0,
        zIndex: 1,
      );

      final synced = syncArrowBindingsAfterDeletion(
        elements: <ElementState>[retainedBindable, retainedArrow],
        deletedIds: const <String>{'deleted-r1'},
        deletedElementsById: const <String, ElementState>{},
      );
      final syncedArrow = _arrowDataById(synced, 'a1');

      expect(syncedArrow.startBinding, isNull);
      expect(syncedArrow.endBinding?.elementId, 'r2');
    });
  });
}

List<ElementState> _buildBaseElements() {
  const rect1 = ElementState(
    id: 'r1',
    rect: DrawRect(maxX: 100, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  const rect2 = ElementState(
    id: 'r2',
    rect: DrawRect(minX: 300, maxX: 400, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  );
  final arrow = _buildArrow(
    id: 'a1',
    startTargetId: 'r1',
    endTargetId: 'r2',
    offsetX: 0,
    offsetY: 0,
    zIndex: 2,
  );
  return <ElementState>[rect1, rect2, arrow];
}

List<ElementState> _duplicateElements({
  required List<ElementState> elements,
  required Map<String, String> idMap,
  required double offsetX,
  required double offsetY,
  required int startZIndex,
}) {
  final duplicated = <ElementState>[];
  var nextZIndex = startZIndex;
  for (final element in elements) {
    final nextId = idMap[element.id]!;
    if (element.data is ArrowData) {
      duplicated.add(
        _buildArrow(
          id: nextId,
          // Keep original target ids before lifecycle sync, mirroring
          // duplication flow in reducers.
          startTargetId: 'r1',
          endTargetId: 'r2',
          offsetX: offsetX,
          offsetY: offsetY,
          zIndex: nextZIndex,
        ),
      );
    } else {
      duplicated.add(
        element.copyWith(
          id: nextId,
          rect: element.rect.translate(DrawPoint(x: offsetX, y: offsetY)),
          zIndex: nextZIndex,
        ),
      );
    }
    nextZIndex += 1;
  }
  return duplicated;
}

ElementState _buildArrow({
  required String id,
  required String startTargetId,
  required String endTargetId,
  required double offsetX,
  required double offsetY,
  required int zIndex,
}) {
  final worldPoints = <DrawPoint>[
    DrawPoint(x: 100 + offsetX, y: 50 + offsetY),
    DrawPoint(x: 300 + offsetX, y: 50 + offsetY),
  ];
  final rect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: worldPoints,
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
      arrowType: ArrowType.straight,
      startBinding: ArrowBinding(
        elementId: startTargetId,
        anchor: const DrawPoint(x: 1, y: 0.5),
      ),
      endBinding: ArrowBinding(
        elementId: endTargetId,
        anchor: const DrawPoint(x: 0, y: 0.5),
      ),
    ),
  );
}

ArrowData _arrowDataById(List<ElementState> elements, String id) =>
    elements.firstWhere((element) => element.id == id).data as ArrowData;
