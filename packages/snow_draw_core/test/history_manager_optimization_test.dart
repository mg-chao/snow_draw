import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/history/history_metadata.dart';
import 'package:snow_draw_core/draw/history/recordable.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/store/history_manager.dart';
import 'package:snow_draw_core/draw/store/snapshot.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('History manager optimizations', () {
    test(
      'pruning still enforces bounded undo depth when old branch points exist',
      () {
        final manager = HistoryManager(maxHistoryLength: 3, maxBranchPoints: 2);
        var state = _stateAt(0);

        void recordTo(int step) {
          final next = _stateAt(step);
          expect(
            manager.record(_snapshot(state), _snapshot(next)),
            isTrue,
            reason: 'Recording state transition $step should succeed',
          );
          state = next;
        }

        // Build two branches under root so root becomes a branch point.
        recordTo(1);
        state = manager.undo(state)!;
        recordTo(2);

        // Keep recording on one branch. Pruning must still bound depth.
        for (var step = 3; step <= 12; step++) {
          recordTo(step);
        }

        expect(
          manager.undoLength,
          lessThanOrEqualTo(5),
          reason: 'Undo depth should stay within pruning bounds',
        );
      },
    );

    test('constructor rejects invalid pruning configuration', () {
      expect(() => HistoryManager(maxHistoryLength: 0), throwsArgumentError);
      expect(() => HistoryManager(maxBranchPoints: -1), throwsArgumentError);
    });
  });

  group('History metadata immutability', () {
    test('defensively copies mutable constructor inputs', () {
      final affectedElementIds = <String>{'e1'};
      final extra = <String, dynamic>{'source': 'test'};

      final metadata = HistoryMetadata(
        description: 'Edit 1 element',
        recordType: HistoryRecordType.edit,
        affectedElementIds: affectedElementIds,
        extra: extra,
      );

      affectedElementIds.add('e2');
      extra['source'] = 'mutated';
      extra['newField'] = true;

      expect(metadata.affectedElementIds, equals({'e1'}));
      expect(metadata.extra, equals(<String, dynamic>{'source': 'test'}));
    });

    test('exposes unmodifiable metadata collections', () {
      final metadata = HistoryMetadata(
        description: 'Edit 1 element',
        recordType: HistoryRecordType.edit,
        affectedElementIds: const {'e1'},
        extra: const {'source': 'test'},
      );

      expect(
        () => metadata.affectedElementIds.add('e2'),
        throwsUnsupportedError,
      );
      expect(
        () => metadata.extra!['source'] = 'mutated',
        throwsUnsupportedError,
      );
    });
  });
}

PersistentSnapshot _snapshot(DrawState state) =>
    PersistentSnapshot.fromState(state, includeSelection: false);

DrawState _stateAt(int step) {
  final left = step.toDouble();
  return DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: [
          ElementState(
            id: 'e',
            rect: DrawRect(minX: left, maxX: left + 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: const FilterData(),
          ),
        ],
      ),
    ),
  );
}
