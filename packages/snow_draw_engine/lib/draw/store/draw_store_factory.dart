import 'dart:typed_data';

import '../../rust_canvas_engine.dart';
import '../core/draw_context.dart';
import '../events/event_bus.dart';
import '../models/draw_state.dart';
import 'draw_store.dart';
import 'draw_store_interface.dart';
import 'rust_draw_store.dart';

/// Store backend strategy used by [createDrawStore].
enum DrawStoreBackend {
  /// Use Rust when available and fall back to legacy Dart on failure.
  auto,

  /// Always create a Rust-backed store.
  rust,

  /// Always create the legacy Dart store.
  legacyDart,
}

/// Creates a draw store with Rust-first backend selection.
DrawStore createDrawStore({
  required DrawContext context,
  DrawState? initialState,
  bool includeSelectionInHistory = false,
  EventBus? eventBus,
  DrawStoreBackend backend = DrawStoreBackend.rust,
  RustCanvasEngine? engine,
  Uint8List? engineConfigBytes,
  void Function(Object error, StackTrace stackTrace)? onRustFallback,
}) {
  if (backend == DrawStoreBackend.legacyDart) {
    return DefaultDrawStore(
      context: context,
      initialState: initialState,
      includeSelectionInHistory: includeSelectionInHistory,
      eventBus: eventBus,
    );
  }

  if (backend == DrawStoreBackend.rust) {
    return RustDrawStore(
      context: context,
      initialState: initialState,
      eventBus: eventBus,
      engine: engine,
      engineConfigBytes: engineConfigBytes,
    );
  }

  try {
    return RustDrawStore(
      context: context,
      initialState: initialState,
      eventBus: eventBus,
      engine: engine,
      engineConfigBytes: engineConfigBytes,
    );
  } on Object catch (error, stackTrace) {
    onRustFallback?.call(error, stackTrace);
    return DefaultDrawStore(
      context: context,
      initialState: initialState,
      includeSelectionInHistory: includeSelectionInHistory,
      eventBus: eventBus,
    );
  }
}
