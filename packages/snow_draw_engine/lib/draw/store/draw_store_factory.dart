import 'dart:typed_data';

import '../../rust_canvas_engine.dart';
import '../core/draw_context.dart';
import '../events/event_bus.dart';
import '../models/draw_state.dart';
import 'draw_store_interface.dart';
import 'rust_draw_store.dart';

/// Store backend strategy used by [createDrawStore].
enum DrawStoreBackend {
  /// Use the Rust V2 runtime path.
  rust,
}

/// Creates a draw store with the Rust V2 runtime.
DrawStore createDrawStore({
  required DrawContext context,
  DrawState? initialState,
  bool includeSelectionInHistory = false,
  EventBus? eventBus,
  DrawStoreBackend backend = DrawStoreBackend.rust,
  RustCanvasEngine? engine,
  Uint8List? engineConfigBytes,
}) {
  if (backend != DrawStoreBackend.rust) {
    throw UnsupportedError('Only DrawStoreBackend.rust is supported.');
  }
  return RustDrawStore(
    context: context,
    initialState: initialState,
    eventBus: eventBus,
    engine: engine,
    engineConfigBytes: engineConfigBytes,
  );
}
