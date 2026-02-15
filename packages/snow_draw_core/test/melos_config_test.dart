// Tests that verify the melos workspace configuration is consistent.
//
// These are compile-time smoke tests: if the workspace resolution
// breaks, these imports will fail to resolve.
import 'package:flutter_test/flutter_test.dart';

// Cross-package import: the app depends on the core package via path.
// If workspace resolution is broken, this import fails.
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('workspace resolution', () {
    test('core package creates a DrawContext', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(
        elementRegistry: registry,
      );
      expect(context, isNotNull);
    });

    test('core package creates a DefaultDrawStore', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(
        elementRegistry: registry,
      );
      final store = DefaultDrawStore(context: context);
      expect(store, isNotNull);
      store.dispose();
    });
  });
}
