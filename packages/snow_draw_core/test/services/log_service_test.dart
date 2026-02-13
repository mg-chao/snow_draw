import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:snow_draw_core/draw/services/log/log_config.dart';
import 'package:snow_draw_core/draw/services/log/log_output.dart';
import 'package:snow_draw_core/draw/services/log/log_service.dart';

void main() {
  group('LogService', () {
    test('module loggers are cached', () {
      final service = LogService(config: LogConfig.test);
      final a = service.module(LogModule.store);
      final b = service.module(LogModule.store);

      expect(identical(a, b), isTrue);
    });

    test('shortcut accessors return correct modules', () {
      final service = LogService(config: LogConfig.test);

      expect(service.store.module, LogModule.store);
      expect(service.pipeline.module, LogModule.pipeline);
      expect(service.edit.module, LogModule.edit);
      expect(service.element.module, LogModule.element);
      expect(service.input.module, LogModule.input);
      expect(service.history.module, LogModule.history);
      expect(service.render.module, LogModule.render);
      expect(service.service.module, LogModule.service);
      expect(service.configLog.module, LogModule.config);
      expect(service.general.module, LogModule.general);
    });

    test('updateConfig clears module logger cache', () {
      final service = LogService(config: LogConfig.test);
      final before = service.store;
      service.updateConfig(LogConfig.development);
      final after = service.store;

      // After config update, cache is cleared so a new instance is created.
      expect(identical(before, after), isFalse);
    });

    test('log respects config shouldLog', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: const LogConfig(
          minLevel: Level.warning,
          enabled: true,
        ),
        outputs: [collector],
      );

      service.log(Level.debug, LogModule.store, 'debug msg');
      service.log(Level.warning, LogModule.store, 'warning msg');

      expect(collector.records.length, 1);
      expect(collector.records.first.message, 'warning msg');
    });

    test('log suppressed when config disabled', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: const LogConfig(enabled: false),
        outputs: [collector],
      );

      service.log(Level.error, LogModule.store, 'should not appear');

      expect(collector.records, isEmpty);
    });

    test('log suppressed for disabled modules', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: const LogConfig(
          disabledModules: {LogModule.store},
        ),
        outputs: [collector],
      );

      service.log(Level.error, LogModule.store, 'suppressed');
      service.log(Level.error, LogModule.edit, 'visible');

      expect(collector.records.length, 1);
      expect(collector.records.first.message, 'visible');
    });

    test('addOutput and removeOutput work', () {
      final service = LogService(
        config: const LogConfig(enabled: true),
      );
      final collector = MemoryLogCollector();

      service.addOutput(collector);
      service.log(Level.info, LogModule.general, 'after add');
      expect(collector.records.length, 1);

      service.removeOutput(collector);
      service.log(Level.info, LogModule.general, 'after remove');
      expect(collector.records.length, 1);
    });

    test('dispose closes output handlers and clears cache', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: LogConfig.test,
        outputs: [collector],
      );
      service.module(LogModule.store); // populate cache

      service.dispose();

      // After dispose, outputs list is cleared.
      // Logging should not crash but also should not reach collector.
      service.log(Level.error, LogModule.store, 'after dispose');
      expect(collector.records, isEmpty);
    });
  });

  group('ModuleLogger', () {
    test('isEnabled reflects config', () {
      final service = LogService(
        config: const LogConfig(
          enabled: true,
          minLevel: Level.trace,
        ),
      );
      final logger = service.store;

      expect(logger.isEnabled, isTrue);
    });

    test('isLevelEnabled checks specific level', () {
      final service = LogService(
        config: const LogConfig(
          enabled: true,
          minLevel: Level.warning,
        ),
      );
      final logger = service.store;

      expect(logger.isLevelEnabled(Level.debug), isFalse);
      expect(logger.isLevelEnabled(Level.warning), isTrue);
      expect(logger.isLevelEnabled(Level.error), isTrue);
    });

    test('timedSync measures and logs duration', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: const LogConfig(enabled: true),
        outputs: [collector],
      );
      final logger = service.store;

      final result = logger.timedSync('test op', () => 42);

      expect(result, 42);
      expect(collector.records.length, 1);
      expect(collector.records.first.message, contains('test op'));
    });

    test('timedSync logs error on failure', () {
      final collector = MemoryLogCollector();
      final service = LogService(
        config: const LogConfig(enabled: true),
        outputs: [collector],
      );
      final logger = service.store;

      expect(
        () => logger.timedSync<int>('failing op', () => throw StateError('x')),
        throwsStateError,
      );
      expect(collector.records.length, 1);
      expect(collector.records.first.level, Level.error);
    });
  });

  group('NoOpLogService', () {
    test('does not output anything', () {
      final collector = MemoryLogCollector();
      final service = NoOpLogService();
      service.addOutput(collector);

      service.log(Level.error, LogModule.store, 'should be silent');

      expect(collector.records, isEmpty);
    });
  });

  group('LogModule.config shortcut', () {
    test('LogModule.config exists in enum', () {
      expect(LogModule.config, isNotNull);
      expect(LogModule.config.displayName, 'Config');
    });
  });
}
