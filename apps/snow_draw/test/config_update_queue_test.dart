import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/config_update_queue.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/services/log/log_service.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigUpdateQueue', () {
    test(
      'serializes updates so each update reads the latest committed config',
      () async {
        final registry = DefaultElementRegistry();
        registerBuiltInElements(registry);
        final context = DrawContext.withDefaults(
          elementRegistry: registry,
          logService: NoOpLogService(),
        );
        final store = DefaultDrawStore(context: context);
        addTearDown(store.dispose);

        final first = ConfigUpdateQueue.enqueue(store, () async {
          final currentConfig = store.config;
          final nextConfig = currentConfig.copyWith(
            grid: currentConfig.grid.copyWith(size: 44),
          );
          await store.dispatch(UpdateConfig(nextConfig));
        });

        final second = ConfigUpdateQueue.enqueue(store, () async {
          final currentConfig = store.config;
          final nextConfig = currentConfig.copyWith(
            snap: currentConfig.snap.copyWith(enabled: true),
          );
          await store.dispatch(UpdateConfig(nextConfig));
        });

        await Future.wait([first, second]);

        expect(store.config.grid.size, 44);
        expect(store.config.snap.enabled, isTrue);
      },
    );

    test('continues processing later updates after a failure', () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(
        elementRegistry: registry,
        logService: NoOpLogService(),
      );
      final store = DefaultDrawStore(context: context);
      addTearDown(store.dispose);

      var secondRan = false;

      final first = ConfigUpdateQueue.enqueue(
        store,
        () async => throw StateError('boom'),
      );
      final second = ConfigUpdateQueue.enqueue(store, () async {
        secondRan = true;
      });

      await expectLater(first, throwsA(isA<StateError>()));
      await second;
      expect(secondRan, isTrue);
    });
  });
}
