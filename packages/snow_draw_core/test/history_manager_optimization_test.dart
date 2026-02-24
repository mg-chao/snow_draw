import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
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
import 'package:test/test.dart';

void main() {
  group('History manager optimizations', () {
    test('pruning enforces bounded linear undo depth', () {
      final manager = HistoryManager(maxHistoryLength: 3);
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

      for (var step = 1; step <= 12; step++) {
        recordTo(step);
      }

      expect(manager.undoLength, lessThanOrEqualTo(3));
    });

    test('constructor rejects invalid pruning configuration', () {
      expect(() => HistoryManager(maxHistoryLength: 0), throwsArgumentError);
    });

    test('recording after undo discards redo entries', () {
      final manager = HistoryManager(maxHistoryLength: 10);
      var state = _stateAt(0);

      void recordTo(int step) {
        final next = _stateAt(step);
        expect(manager.record(_snapshot(state), _snapshot(next)), isTrue);
        state = next;
      }

      recordTo(1);
      recordTo(2);

      final undone = manager.undo(state);
      expect(undone, isNotNull);
      state = undone!;
      expect(_stateStep(state), equals(1));
      expect(manager.canRedo, isTrue);

      recordTo(3);
      expect(manager.canRedo, isFalse);

      final replayUndo = manager.undo(state);
      expect(replayUndo, isNotNull);
      state = replayUndo!;
      expect(_stateStep(state), equals(1));

      final replayRedo = manager.redo(state);
      expect(replayRedo, isNotNull);
      expect(_stateStep(replayRedo!), equals(3));
    });

    test('restore normalizes stale nextEntryId before recording', () {
      final manager = HistoryManager(maxHistoryLength: 10);
      var state = _stateAt(0);

      void recordTo(int step) {
        final next = _stateAt(step);
        expect(
          manager.record(
            _snapshot(state),
            _snapshot(next),
            metadata: HistoryMetadata(
              description: 'step-$step',
              recordType: HistoryRecordType.edit,
            ),
          ),
          isTrue,
        );
        state = next;
      }

      recordTo(1);

      final snapshotJson = manager.snapshot().toJson()..['nextEntryId'] = 0;
      final restoredSnapshot = HistoryManagerSnapshot.fromJson(
        snapshotJson,
        elementRegistry: _buildRegistry(),
      );

      final restored = HistoryManager(maxHistoryLength: 10)
        ..restore(restoredSnapshot);
      final nextState = _stateAt(2);
      expect(
        restored.record(
          _snapshot(state),
          _snapshot(nextState),
          metadata: HistoryMetadata(
            description: 'step-2',
            recordType: HistoryRecordType.edit,
          ),
        ),
        isTrue,
      );

      final entryIds = _entriesFromSnapshot(
        restored.snapshot().toJson(),
      ).map((entry) => entry['id'] as int).toList();
      expect(entryIds.toSet().length, entryIds.length);
    });
  });

  group('History snapshot codec', () {
    test('round trip preserves undo/redo traversal', () {
      final manager = HistoryManager(maxHistoryLength: 4);
      var state = _stateAt(0);

      void recordTo(int step) {
        final next = _stateAt(step);
        expect(
          manager.record(
            _snapshot(state),
            _snapshot(next),
            metadata: HistoryMetadata(
              description: 'step-$step',
              recordType: HistoryRecordType.edit,
            ),
          ),
          isTrue,
        );
        state = next;
      }

      recordTo(1);
      recordTo(2);

      final restoredSnapshot = HistoryManagerSnapshot.fromJson(
        manager.snapshot().toJson(),
        elementRegistry: _buildRegistry(),
      );

      final restored = HistoryManager(maxHistoryLength: 4)
        ..restore(restoredSnapshot);
      var replay = state;

      replay = restored.undo(replay)!;
      expect(_stateStep(replay), equals(1));

      replay = restored.redo(replay)!;
      expect(_stateStep(replay), equals(2));
    });

    test('decode clamps out-of-range cursor values', () {
      final manager = HistoryManager();
      var state = _stateAt(0);
      for (var step = 1; step <= 2; step++) {
        final next = _stateAt(step);
        expect(manager.record(_snapshot(state), _snapshot(next)), isTrue);
        state = next;
      }

      final snapshotJson = manager.snapshot().toJson()..['cursor'] = 999;
      final restoredSnapshot = HistoryManagerSnapshot.fromJson(
        snapshotJson,
        elementRegistry: _buildRegistry(),
      );
      final restored = HistoryManager()..restore(restoredSnapshot);

      expect(restored.canUndo, isTrue);
      final undone = restored.undo(state);
      expect(undone, isNotNull);
      expect(_stateStep(undone!), equals(1));
    });

    test('decode rejects malformed entries payload', () {
      final snapshotJson = <String, dynamic>{
        'version': 2,
        'cursor': 0,
        'nextEntryId': 1,
        'entries': ['invalid'],
      };

      expect(
        () => HistoryManagerSnapshot.fromJson(
          snapshotJson,
          elementRegistry: _buildRegistry(),
        ),
        throwsStateError,
      );
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

List<Map<String, dynamic>> _entriesFromSnapshot(
  Map<String, dynamic> snapshotJson,
) => (snapshotJson['entries'] as List<dynamic>).cast<Map<String, dynamic>>();

int _stateStep(DrawState state) =>
    state.domain.document.elements.single.rect.minX.round();

DefaultElementRegistry _buildRegistry() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  return registry;
}
