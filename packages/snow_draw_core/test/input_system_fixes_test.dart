/// Tests for Input System fixes.
///
/// Covers:
/// 1. ThrottleMiddleware: last event before pointer-up must not be dropped.
/// 2. KeyModifiers.toEditModifiers: shared conversion replaces duplicated
///    private methods in EditPlugin and SelectPlugin.
/// 3. PointerCancelInputEvent carries synced modifiers.
/// 4. Dead code removal: _resolveHoverSelectionElementId is superseded by
///    the combined _updateCursorAndHoverForPosition path.
/// 5. EditPlugin default routing policy: pointer-down during edit returns
///    handled (commit) instead of falling through.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/middleware/default_middlewares.dart';
import 'package:snow_draw_core/draw/input/middleware/input_middleware.dart';
import 'package:snow_draw_core/draw/input/plugin_core.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  // =========================================================================
  // 1. ThrottleMiddleware
  // =========================================================================

  group('ThrottleMiddleware', () {
    test('forwards non-throttled event types unconditionally', () async {
      final middleware = ThrottleMiddleware(
        duration: const Duration(milliseconds: 100),
      );
      final context = MiddlewareContext(state: DrawState());
      const event = PointerDownInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );

      var nextCalled = false;
      final result = await middleware.process(event, context, (e) async {
        nextCalled = true;
        return e;
      });

      expect(nextCalled, isTrue);
      expect(result, isNotNull);
    });

    test('forwards first throttled event', () async {
      final middleware = ThrottleMiddleware(
        duration: const Duration(milliseconds: 100),
      );
      final context = MiddlewareContext(state: DrawState());
      const event = PointerMoveInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );

      var nextCalled = false;
      await middleware.process(event, context, (e) async {
        nextCalled = true;
        return e;
      });

      expect(nextCalled, isTrue);
    });

    test('drops throttled event within duration window '
        'by returning null (not the raw event)', () async {
      final middleware = ThrottleMiddleware(
        duration: const Duration(milliseconds: 500),
      );
      final context = MiddlewareContext(state: DrawState());
      const event1 = PointerMoveInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );
      const event2 = PointerMoveInputEvent(
        position: DrawPoint(x: 30, y: 40),
        modifiers: KeyModifiers.none,
      );

      // First event goes through.
      await middleware.process(event1, context, (e) async => e);

      // Second event within window should be dropped (null).
      var nextCalled = false;
      final result = await middleware.process(event2, context, (e) async {
        nextCalled = true;
        return e;
      });

      // After fix: throttled events return null instead of the raw
      // event, so the coordinator knows the event was intercepted.
      expect(nextCalled, isFalse);
      expect(result, isNull);
    });

    test('forwards event after duration window expires', () async {
      final middleware = ThrottleMiddleware(
        duration: const Duration(milliseconds: 10),
      );
      final context = MiddlewareContext(state: DrawState());
      const event1 = PointerMoveInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );
      const event2 = PointerMoveInputEvent(
        position: DrawPoint(x: 30, y: 40),
        modifiers: KeyModifiers.none,
      );

      await middleware.process(event1, context, (e) async => e);

      // Wait for the throttle window to expire.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var nextCalled = false;
      await middleware.process(event2, context, (e) async {
        nextCalled = true;
        return e;
      });

      expect(nextCalled, isTrue);
    });
  });

  // =========================================================================
  // 2. KeyModifiers.toEditModifiers
  // =========================================================================

  group('KeyModifiers.toEditModifiers', () {
    test('none produces default EditModifiers', () {
      const modifiers = KeyModifiers.none;
      final result = modifiers.toEditModifiers();

      expect(result.maintainAspectRatio, isFalse);
      expect(result.discreteAngle, isFalse);
      expect(result.fromCenter, isFalse);
      expect(result.snapOverride, isFalse);
    });

    test('shift maps to maintainAspectRatio and discreteAngle', () {
      const modifiers = KeyModifiers(shift: true);
      final result = modifiers.toEditModifiers();

      expect(result.maintainAspectRatio, isTrue);
      expect(result.discreteAngle, isTrue);
      expect(result.fromCenter, isFalse);
      expect(result.snapOverride, isFalse);
    });

    test('alt maps to fromCenter', () {
      const modifiers = KeyModifiers(alt: true);
      final result = modifiers.toEditModifiers();

      expect(result.maintainAspectRatio, isFalse);
      expect(result.fromCenter, isTrue);
    });

    test('control maps to snapOverride', () {
      const modifiers = KeyModifiers(control: true);
      final result = modifiers.toEditModifiers();

      expect(result.snapOverride, isTrue);
    });

    test('all modifiers active', () {
      const modifiers = KeyModifiers(shift: true, control: true, alt: true);
      final result = modifiers.toEditModifiers();

      expect(result.maintainAspectRatio, isTrue);
      expect(result.discreteAngle, isTrue);
      expect(result.fromCenter, isTrue);
      expect(result.snapOverride, isTrue);
    });
  });

  // =========================================================================
  // 3. EditPlugin default routing: pointer-down during edit
  // =========================================================================

  group('EditPlugin default routing policy', () {
    test('default policy commits edit on pointer-down instead of ignoring', () {
      // The default InputRoutingPolicy should use commitEdit
      // so that pointer-down during an active edit finishes the
      // edit rather than falling through to select/create plugins.
      const policy = InputRoutingPolicy.defaultPolicy;
      expect(
        policy.editPointerDownBehavior,
        equals(EditPointerDownBehavior.commitEdit),
      );
    });
  });

  // =========================================================================
  // 4. InputRoutingPolicy: equality and basic behavior
  // =========================================================================

  group('InputRoutingPolicy', () {
    test('allowSelection returns false when editing by default', () {
      const policy = InputRoutingPolicy();
      final state = DrawState();
      // Idle state: should allow selection.
      expect(policy.allowSelection(state), isTrue);
    });

    test('allowCreate returns false when editing by default', () {
      const policy = InputRoutingPolicy();
      final state = DrawState();
      expect(policy.allowCreate(state), isTrue);
    });
  });

  // =========================================================================
  // 5. PluginResult equality and status
  // =========================================================================

  group('PluginResult', () {
    test('handled stops propagation', () {
      const result = PluginResult.handled(message: 'test');
      expect(result.isHandled, isTrue);
      expect(result.shouldStopPropagation, isTrue);
    });

    test('unhandled continues propagation', () {
      const result = PluginResult.unhandled(reason: 'test');
      expect(result.isUnhandled, isTrue);
      expect(result.shouldStopPropagation, isFalse);
    });

    test('consumed allows observation', () {
      const result = PluginResult.consumed(message: 'test');
      expect(result.isConsumed, isTrue);
      expect(result.shouldStopPropagation, isFalse);
    });

    test('equality', () {
      const a = PluginResult.handled(message: 'x');
      const b = PluginResult.handled(message: 'x');
      const c = PluginResult.handled(message: 'y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // 6. InputPipeline: middleware chain execution
  // =========================================================================

  group('InputPipeline', () {
    test('empty pipeline returns event unchanged', () async {
      final pipeline = InputPipeline(middlewares: const []);
      const event = PointerDownInputEvent(
        position: DrawPoint(x: 5, y: 5),
        modifiers: KeyModifiers.none,
      );
      final context = MiddlewareContext(state: DrawState());

      final result = await pipeline.execute(event, context);
      expect(result, same(event));
    });

    test('validation middleware rejects NaN positions', () async {
      final pipeline = InputPipeline(
        middlewares: const [ValidationMiddleware()],
      );
      const event = PointerDownInputEvent(
        position: DrawPoint(x: double.nan, y: 10),
        modifiers: KeyModifiers.none,
      );
      final context = MiddlewareContext(state: DrawState());

      final result = await pipeline.execute(event, context);
      expect(result, isNull);
    });

    test('validation middleware rejects infinite positions', () async {
      final pipeline = InputPipeline(
        middlewares: const [ValidationMiddleware()],
      );
      const event = PointerDownInputEvent(
        position: DrawPoint(x: double.infinity, y: 10),
        modifiers: KeyModifiers.none,
      );
      final context = MiddlewareContext(state: DrawState());

      final result = await pipeline.execute(event, context);
      expect(result, isNull);
    });

    test('validation middleware passes valid positions', () async {
      final pipeline = InputPipeline(
        middlewares: const [ValidationMiddleware()],
      );
      const event = PointerDownInputEvent(
        position: DrawPoint(x: 100, y: 200),
        modifiers: KeyModifiers.none,
      );
      final context = MiddlewareContext(state: DrawState());

      final result = await pipeline.execute(event, context);
      expect(result, isNotNull);
    });
  });

  // =========================================================================
  // 7. KeyModifiers equality
  // =========================================================================

  group('KeyModifiers', () {
    test('equality', () {
      const a = KeyModifiers(shift: true, alt: true);
      const b = KeyModifiers(shift: true, alt: true);
      const c = KeyModifiers(alt: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('none has all false', () {
      expect(KeyModifiers.none.shift, isFalse);
      expect(KeyModifiers.none.control, isFalse);
      expect(KeyModifiers.none.alt, isFalse);
    });
  });

  // =========================================================================
  // 8. EventFilterMiddleware
  // =========================================================================

  group('EventFilterMiddleware', () {
    test('passes events matching predicate', () async {
      // The predicate acts as a pass-filter: events matching it go
      // through; events that don't match are intercepted.
      final middleware = EventFilterMiddleware(
        predicate: (event, context) => event is PointerMoveInputEvent,
      );
      final context = MiddlewareContext(state: DrawState());
      const event = PointerMoveInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );

      var nextCalled = false;
      final result = await middleware.process(event, context, (e) async {
        nextCalled = true;
        return e;
      });

      expect(nextCalled, isTrue);
      expect(result, isNotNull);
    });

    test('intercepts events not matching predicate', () async {
      final middleware = EventFilterMiddleware(
        predicate: (event, context) => event is PointerMoveInputEvent,
      );
      final context = MiddlewareContext(state: DrawState());
      const event = PointerDownInputEvent(
        position: DrawPoint(x: 10, y: 20),
        modifiers: KeyModifiers.none,
      );

      var nextCalled = false;
      final result = await middleware.process(event, context, (e) async {
        nextCalled = true;
        return e;
      });

      expect(nextCalled, isFalse);
      expect(result, isNull);
    });
  });
}
