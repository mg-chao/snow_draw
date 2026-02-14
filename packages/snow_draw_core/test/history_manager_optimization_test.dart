import 'package:flutter_test/flutter_test.dart';
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

    test('restore normalizes stale nextNodeId before recording', () {
      final manager = HistoryManager(maxHistoryLength: 10, maxBranchPoints: 2);
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

      final snapshotJson = manager.snapshot().toJson()..['nextNodeId'] = 1;
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final restoredSnapshot = HistoryManagerSnapshot.fromJson(
        snapshotJson,
        elementRegistry: registry,
      );

      final restored = HistoryManager(maxHistoryLength: 10, maxBranchPoints: 2)
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

      final nodeIds = _nodesFromSnapshot(
        restored.snapshot().toJson(),
      ).map((node) => node['id'] as int).toList();
      expect(
        nodeIds.toSet().length,
        nodeIds.length,
        reason: 'History node ids should stay unique after restore+record',
      );
    });
  });

  group('History root normalization', () {
    test('pruned root omits unreachable payload in exported snapshots', () {
      final manager = HistoryManager(maxHistoryLength: 1, maxBranchPoints: 0);
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

      final snapshotJson = manager.snapshot().toJson();
      final rootNode = _nodeById(snapshotJson, snapshotJson['rootId'] as int);
      expect(rootNode.containsKey('delta'), isFalse);
      expect(rootNode.containsKey('metadata'), isFalse);

      final undone = manager.undo(state);
      expect(undone, isNotNull);
      state = undone!;
      expect(_stateStep(state), equals(1));

      final redone = manager.redo(state);
      expect(redone, isNotNull);
      state = redone!;
      expect(_stateStep(state), equals(2));
    });

    test('restore strips legacy root payload without changing traversal', () {
      final manager = HistoryManager(maxHistoryLength: 4, maxBranchPoints: 0);
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

      final snapshotJson = manager.snapshot().toJson();
      final rootId = snapshotJson['rootId'] as int;
      final nodes = (snapshotJson['nodes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final rootNode = nodes.singleWhere((node) => node['id'] == rootId);
      final nodeWithPayload = nodes.firstWhere(
        (node) => node['id'] != rootId && node.containsKey('delta'),
      );

      rootNode['delta'] = Map<String, dynamic>.from(
        nodeWithPayload['delta'] as Map<String, dynamic>,
      );
      rootNode['metadata'] = Map<String, dynamic>.from(
        nodeWithPayload['metadata'] as Map<String, dynamic>,
      );

      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final restoredSnapshot = HistoryManagerSnapshot.fromJson(
        snapshotJson,
        elementRegistry: registry,
      );

      final restored = HistoryManager(maxHistoryLength: 4, maxBranchPoints: 0)
        ..restore(restoredSnapshot);

      final normalizedJson = restored.snapshot().toJson();
      final normalizedRoot = _nodeById(
        normalizedJson,
        normalizedJson['rootId'] as int,
      );
      expect(normalizedRoot.containsKey('delta'), isFalse);
      expect(normalizedRoot.containsKey('metadata'), isFalse);

      var replay = state;
      replay = restored.undo(replay)!;
      expect(_stateStep(replay), equals(1));

      replay = restored.redo(replay)!;
      expect(_stateStep(replay), equals(2));
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

Map<String, dynamic> _nodeById(Map<String, dynamic> snapshotJson, int nodeId) {
  final nodes = (snapshotJson['nodes'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  return nodes.singleWhere((node) => node['id'] == nodeId);
}

List<Map<String, dynamic>> _nodesFromSnapshot(
  Map<String, dynamic> snapshotJson,
) => (snapshotJson['nodes'] as List<dynamic>).cast<Map<String, dynamic>>();

int _stateStep(DrawState state) =>
    state.domain.document.elements.single.rect.minX.round();
