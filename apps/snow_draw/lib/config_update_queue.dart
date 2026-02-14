import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';

/// Serializes config writes per [DrawStore] to avoid cross-adapter races.
///
/// Adapters that mutate [DrawStore.config] build a full [DrawConfig] snapshot
/// before dispatching [UpdateConfig]. If multiple adapters do this in parallel,
/// later writes can accidentally revert earlier fields that were not part of
/// the current update. Using a shared queue keeps writes ordered and ensures
/// each update reads the latest committed config.
class ConfigUpdateQueue {
  ConfigUpdateQueue._();

  static final _queues = Expando<_StoreQueue>('snow_draw_config_update_queue');

  /// Adds [update] to the per-store config write queue.
  ///
  /// Updates execute sequentially for a given [store] so each write can build
  /// from the latest committed config snapshot.
  static Future<void> enqueue(DrawStore store, Future<void> Function() update) {
    final queue = _queues[store] ??= _StoreQueue();
    return queue.enqueue(update);
  }
}

class _StoreQueue {
  var _pending = Future<void>.value();

  Future<void> enqueue(Future<void> Function() update) => _pending = _pending
      .catchError((Object _, StackTrace _) {})
      .then((_) => update());
}
