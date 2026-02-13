import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:snow_draw_core/draw/services/log/log_output.dart';

void main() {
  group('MemoryLogCollector', () {
    DefaultLogRecord _record(String message) => DefaultLogRecord(
      timestamp: DateTime(2025),
      level: Level.info,
      module: 'Test',
      message: message,
    );

    test('stores records up to maxRecords', () {
      final collector = MemoryLogCollector(maxRecords: 3);
      collector.output(_record('a'));
      collector.output(_record('b'));
      collector.output(_record('c'));

      expect(collector.records.length, 3);
      expect(collector.records.map((r) => r.message), ['a', 'b', 'c']);
    });

    test('evicts oldest records when exceeding capacity', () {
      final collector = MemoryLogCollector(maxRecords: 3);
      collector.output(_record('a'));
      collector.output(_record('b'));
      collector.output(_record('c'));
      collector.output(_record('d'));

      expect(collector.records.length, 3);
      expect(collector.records.map((r) => r.message), ['b', 'c', 'd']);
    });

    test('evicts multiple oldest when burst exceeds capacity', () {
      final collector = MemoryLogCollector(maxRecords: 2);
      for (var i = 0; i < 5; i++) {
        collector.output(_record('msg$i'));
      }

      expect(collector.records.length, 2);
      expect(collector.records.map((r) => r.message), ['msg3', 'msg4']);
    });

    test('getRecent returns last n records', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      for (var i = 0; i < 5; i++) {
        collector.output(_record('msg$i'));
      }

      final recent = collector.getRecent(2);
      expect(recent.map((r) => r.message), ['msg3', 'msg4']);
    });

    test('getRecent returns all when count exceeds size', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      collector.output(_record('a'));
      collector.output(_record('b'));

      final recent = collector.getRecent(100);
      expect(recent.length, 2);
    });

    test('filterByLevel filters correctly', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      collector.output(
        DefaultLogRecord(
          timestamp: DateTime(2025),
          level: Level.debug,
          module: 'Test',
          message: 'debug',
        ),
      );
      collector.output(
        DefaultLogRecord(
          timestamp: DateTime(2025),
          level: Level.error,
          module: 'Test',
          message: 'error',
        ),
      );
      collector.output(
        DefaultLogRecord(
          timestamp: DateTime(2025),
          level: Level.info,
          module: 'Test',
          message: 'info',
        ),
      );

      final errors = collector.filterByLevel(Level.error);
      expect(errors.length, 1);
      expect(errors.first.message, 'error');
    });

    test('filterByModule filters correctly', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      collector.output(
        DefaultLogRecord(
          timestamp: DateTime(2025),
          level: Level.info,
          module: 'Store',
          message: 'store msg',
        ),
      );
      collector.output(
        DefaultLogRecord(
          timestamp: DateTime(2025),
          level: Level.info,
          module: 'Edit',
          message: 'edit msg',
        ),
      );

      final storeRecords = collector.filterByModule('Store');
      expect(storeRecords.length, 1);
      expect(storeRecords.first.message, 'store msg');
    });

    test('clear removes all records', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      collector.output(_record('a'));
      collector.output(_record('b'));
      collector.clear();

      expect(collector.records, isEmpty);
    });

    test('outputBatch adds all records', () {
      final collector = MemoryLogCollector(maxRecords: 10);
      collector.outputBatch([_record('a'), _record('b'), _record('c')]);

      expect(collector.records.length, 3);
    });
  });
}
