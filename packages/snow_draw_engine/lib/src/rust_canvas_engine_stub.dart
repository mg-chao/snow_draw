import 'dart:typed_data';

/// Raised when the Rust canvas engine cannot be used.
class RustCanvasEngineException implements Exception {
  const RustCanvasEngineException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'RustCanvasEngineException(statusCode: $statusCode, message: $message)';
}

/// FFI-backed Snow Draw engine bridge.
///
/// This stub is used on platforms without `dart:ffi` support.
class RustCanvasEngine {
  RustCanvasEngine._();

  static RustCanvasEngine create({Uint8List? configBytes}) {
    throw UnsupportedError(
      'RustCanvasEngine is unavailable on this platform (dart:ffi missing).',
    );
  }

  int get abiVersion =>
      throw UnsupportedError('RustCanvasEngine is unavailable.');

  int get capabilities =>
      throw UnsupportedError('RustCanvasEngine is unavailable.');

  static RustCanvasEngine createV2({Uint8List? initBytes}) {
    throw UnsupportedError(
      'RustCanvasEngine is unavailable on this platform (dart:ffi missing).',
    );
  }

  void dispatch(Uint8List commandBytes) {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  void dispatchBatch(List<Uint8List> commandBatch) {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  Uint8List getSnapshotBytes() {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  Uint8List? pollEventBytes() {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  void processInputV2(Uint8List inputBytes) {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  Uint8List? pollOutputV2() {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }

  void dispose() {
    throw UnsupportedError('RustCanvasEngine is unavailable.');
  }
}
