import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

const _bridgeGlobalSymbol = '__snowDrawEngineWasmBridge';

/// Raised when a web Rust engine operation fails.
class RustCanvasEngineException implements Exception {
  const RustCanvasEngineException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'RustCanvasEngineException(statusCode: $statusCode, message: $message)';
}

/// WASM-backed Snow Draw engine bridge.
///
/// The web host must register `globalThis.__snowDrawEngineWasmBridge` with
/// `create`, `createV2`, and instance methods compatible with this adapter.
class RustCanvasEngine {
  RustCanvasEngine._(this._instance);

  final JSObject _instance;
  var _disposed = false;

  static RustCanvasEngine create({Uint8List? configBytes}) {
    final instance = _createInstance('create', configBytes ?? Uint8List(0));
    return RustCanvasEngine._(instance);
  }

  static RustCanvasEngine createV2({Uint8List? initBytes}) {
    final instance = _createInstance('createV2', initBytes ?? Uint8List(0));
    return RustCanvasEngine._(instance);
  }

  int get abiVersion {
    _checkNotDisposed();
    return _toInt(_invoke('abiVersion', const []), label: 'abiVersion');
  }

  int get capabilities {
    _checkNotDisposed();
    return _toInt(_invoke('capabilities', const []), label: 'capabilities');
  }

  void dispatch(Uint8List commandBytes) {
    _checkNotDisposed();
    _invoke('dispatch', <JSAny?>[_toWireBytes(commandBytes)]);
  }

  void dispatchBatch(List<Uint8List> commandBatch) {
    _checkNotDisposed();
    final batch = commandBatch
        .map<JSAny?>((bytes) => _toWireBytes(bytes))
        .toList(growable: false)
        .jsify();
    _invoke('dispatchBatch', <JSAny?>[batch]);
  }

  Uint8List getSnapshotBytes() {
    _checkNotDisposed();
    return _toBytes(_invoke('getSnapshotBytes', const []), label: 'snapshot');
  }

  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    _checkNotDisposed();
    return _toBytes(
      _invoke('buildFramePlanBytes', <JSAny?>[_toWireBytes(requestBytes)]),
      label: 'frame plan',
    );
  }

  Uint8List? pollEventBytes() {
    _checkNotDisposed();
    final raw = _invoke('pollEventBytes', const []);
    if (raw.isUndefinedOrNull) {
      return null;
    }
    return _toBytes(raw, label: 'event');
  }

  void processInputV2(Uint8List inputBytes) {
    _checkNotDisposed();
    _invoke('processInputV2', <JSAny?>[_toWireBytes(inputBytes)]);
  }

  Uint8List? pollOutputV2() {
    _checkNotDisposed();
    final raw = _invoke('pollOutputV2', const []);
    if (raw.isUndefinedOrNull) {
      return null;
    }
    return _toBytes(raw, label: 'output');
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _invoke('dispose', const []);
    _disposed = true;
  }

  JSAny? _invoke(String method, List<JSAny?> args) {
    try {
      return _instance.callMethodVarArgs<JSAny?>(method.toJS, args);
    } on Object catch (error) {
      throw RustCanvasEngineException(
        'WASM bridge invocation failed: $method ($error)',
      );
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('RustCanvasEngine has been disposed');
    }
  }

  static JSObject _createInstance(String method, Uint8List bytes) {
    final bridgeAny = globalContext[_bridgeGlobalSymbol];
    if (bridgeAny.isUndefinedOrNull || bridgeAny is! JSObject) {
      throw UnsupportedError(
        'Rust WASM bridge is unavailable. '
        'Expected globalThis.$_bridgeGlobalSymbol.',
      );
    }

    try {
      final instanceAny = bridgeAny.callMethodVarArgs<JSAny?>(
        method.toJS,
        <JSAny?>[_toWireBytes(bytes)],
      );
      if (instanceAny is! JSObject) {
        throw const RustCanvasEngineException(
          'WASM bridge returned invalid engine instance.',
        );
      }
      return instanceAny;
    } on RustCanvasEngineException {
      rethrow;
    } on Object catch (error) {
      throw RustCanvasEngineException(
        'WASM bridge failed to create engine ($method): $error',
      );
    }
  }

  static JSAny? _toWireBytes(Uint8List bytes) => bytes.jsify();

  static Uint8List _toBytes(JSAny? raw, {required String label}) {
    if (raw.isUndefinedOrNull) {
      return Uint8List(0);
    }

    if (raw is JSUint8Array) {
      return raw.toDart;
    }

    if (raw is JSArrayBuffer) {
      return raw.toDart.asUint8List();
    }

    final dartified = raw.dartify();
    if (dartified is Uint8List) {
      return dartified;
    }
    if (dartified is ByteBuffer) {
      return dartified.asUint8List();
    }
    if (dartified is List<Object?>) {
      final values = <int>[];
      for (final value in dartified) {
        if (value is num) {
          values.add(value.toInt());
        } else {
          throw RustCanvasEngineException(
            'Unexpected non-byte value in WASM $label payload: $value',
          );
        }
      }
      return Uint8List.fromList(values);
    }

    throw RustCanvasEngineException(
      'Unexpected WASM $label payload type: ${dartified.runtimeType}',
    );
  }

  static int _toInt(JSAny? raw, {required String label}) {
    if (raw.isUndefinedOrNull) {
      throw RustCanvasEngineException('Missing WASM $label value.');
    }

    if (raw is JSNumber) {
      return raw.toDartInt;
    }

    final dartified = raw.dartify();
    if (dartified is num) {
      return dartified.toInt();
    }

    throw RustCanvasEngineException(
      'Unexpected WASM $label type: ${dartified.runtimeType}',
    );
  }
}
