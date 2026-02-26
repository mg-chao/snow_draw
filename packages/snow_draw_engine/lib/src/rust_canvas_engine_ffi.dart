import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _sdStatusOk = 0;
const _sdStatusNoEvent = 1;

/// Raised when a native Rust engine operation fails.
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
/// This class exposes a byte-level lifecycle API over the Rust C ABI.
class RustCanvasEngine {
  RustCanvasEngine._(this._bindings, this._handle);

  final _RustBindings _bindings;
  ffi.Pointer<_SdEngine> _handle;
  var _disposed = false;

  static RustCanvasEngine create({
    Uint8List? configBytes,
    ffi.DynamicLibrary? dynamicLibrary,
  }) {
    final library = dynamicLibrary ?? _RustBindings.openDefaultLibrary();
    final bindings = _RustBindings(library);

    final configNative = _NativeBytes.fromDart(configBytes ?? Uint8List(0));
    final configBytesPtr = calloc<_SdBytes>();
    final statusPtr = calloc<ffi.Uint32>();
    final errorPtr = calloc<_SdBytes>();

    try {
      _setSdBytes(configBytesPtr, configNative.pointer, configNative.length);
      final handle = bindings.engineCreate(
        configBytesPtr.ref,
        statusPtr,
        errorPtr,
      );

      final status = statusPtr.value;
      final errorBytes = bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_create',
        nullHandle: handle == ffi.nullptr,
      );

      return RustCanvasEngine._(bindings, handle);
    } finally {
      configNative.dispose();
      calloc.free(configBytesPtr);
      calloc.free(statusPtr);
      calloc.free(errorPtr);
    }
  }

  static RustCanvasEngine createV2({
    Uint8List? initBytes,
    ffi.DynamicLibrary? dynamicLibrary,
  }) {
    final library = dynamicLibrary ?? _RustBindings.openDefaultLibrary();
    final bindings = _RustBindings(library);

    final initNative = _NativeBytes.fromDart(initBytes ?? Uint8List(0));
    final initBytesPtr = calloc<_SdBytes>();
    final statusPtr = calloc<ffi.Uint32>();
    final errorPtr = calloc<_SdBytes>();

    try {
      _setSdBytes(initBytesPtr, initNative.pointer, initNative.length);
      final handle = bindings.engineV2Create(
        initBytesPtr.ref,
        statusPtr,
        errorPtr,
      );

      final status = statusPtr.value;
      final errorBytes = bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_v2_create',
        nullHandle: handle == ffi.nullptr,
      );

      return RustCanvasEngine._(bindings, handle);
    } finally {
      initNative.dispose();
      calloc.free(initBytesPtr);
      calloc.free(statusPtr);
      calloc.free(errorPtr);
    }
  }

  int get abiVersion {
    _checkNotDisposed();
    return _bindings.engineAbiVersion();
  }

  int get capabilities {
    _checkNotDisposed();
    return _bindings.engineCapabilities();
  }

  void dispatch(Uint8List commandBytes) {
    _checkNotDisposed();

    final commandNative = _NativeBytes.fromDart(commandBytes);
    final commandBytesPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();
    try {
      _setSdBytes(commandBytesPtr, commandNative.pointer, commandNative.length);
      final status = _bindings.engineDispatch(
        _handle,
        commandBytesPtr.ref,
        errorPtr,
      );
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_dispatch',
      );
    } finally {
      commandNative.dispose();
      calloc.free(commandBytesPtr);
      calloc.free(errorPtr);
    }
  }

  void dispatchBatch(List<Uint8List> commandBatch) {
    _checkNotDisposed();

    final nativeCommands = <_NativeBytes>[];
    final array = calloc<_SdBytes>(commandBatch.length);
    final errorPtr = calloc<_SdBytes>();

    try {
      for (var i = 0; i < commandBatch.length; i++) {
        final native = _NativeBytes.fromDart(commandBatch[i]);
        nativeCommands.add(native);
        _setSdBytes(array + i, native.pointer, native.length);
      }

      final status = _bindings.engineDispatchBatch(
        _handle,
        array,
        commandBatch.length,
        errorPtr,
      );
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_dispatch_batch',
      );
    } finally {
      for (final native in nativeCommands) {
        native.dispose();
      }
      calloc.free(array);
      calloc.free(errorPtr);
    }
  }

  Uint8List getSnapshotBytes() {
    _checkNotDisposed();

    final snapshotPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();

    try {
      final status = _bindings.engineGetSnapshot(
        _handle,
        snapshotPtr,
        errorPtr,
      );
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_get_snapshot',
      );
      return _bindings.takeOwnedBytes(snapshotPtr.ref);
    } finally {
      calloc.free(snapshotPtr);
      calloc.free(errorPtr);
    }
  }

  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    _checkNotDisposed();

    final requestNative = _NativeBytes.fromDart(requestBytes);
    final requestBytesPtr = calloc<_SdBytes>();
    final planPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();

    try {
      _setSdBytes(requestBytesPtr, requestNative.pointer, requestNative.length);
      final status = _bindings.engineBuildFramePlan(
        _handle,
        requestBytesPtr.ref,
        planPtr,
        errorPtr,
      );
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_build_frame_plan',
      );
      return _bindings.takeOwnedBytes(planPtr.ref);
    } finally {
      requestNative.dispose();
      calloc.free(requestBytesPtr);
      calloc.free(planPtr);
      calloc.free(errorPtr);
    }
  }

  Uint8List? pollEventBytes() {
    _checkNotDisposed();

    final eventPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();

    try {
      final status = _bindings.enginePollEvent(_handle, eventPtr, errorPtr);
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      if (status == _sdStatusNoEvent) {
        return null;
      }
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_poll_event',
      );
      return _bindings.takeOwnedBytes(eventPtr.ref);
    } finally {
      calloc.free(eventPtr);
      calloc.free(errorPtr);
    }
  }

  void processInputV2(Uint8List inputBytes) {
    _checkNotDisposed();

    final inputNative = _NativeBytes.fromDart(inputBytes);
    final inputBytesPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();
    try {
      _setSdBytes(inputBytesPtr, inputNative.pointer, inputNative.length);
      final status = _bindings.engineV2ProcessInput(
        _handle,
        inputBytesPtr.ref,
        errorPtr,
      );
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_v2_process_input',
      );
    } finally {
      inputNative.dispose();
      calloc.free(inputBytesPtr);
      calloc.free(errorPtr);
    }
  }

  Uint8List? pollOutputV2() {
    _checkNotDisposed();

    final outputPtr = calloc<_SdBytes>();
    final errorPtr = calloc<_SdBytes>();

    try {
      final status = _bindings.engineV2PollOutput(_handle, outputPtr, errorPtr);
      final errorBytes = _bindings.takeOwnedBytes(errorPtr.ref);
      if (status == _sdStatusNoEvent) {
        return null;
      }
      _throwIfNotOk(
        status: status,
        errorBytes: errorBytes,
        operation: 'sd_engine_v2_poll_output',
      );
      return _bindings.takeOwnedBytes(outputPtr.ref);
    } finally {
      calloc.free(outputPtr);
      calloc.free(errorPtr);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.engineDestroy(_handle);
    _handle = ffi.nullptr;
    _disposed = true;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const RustCanvasEngineException(
        'Engine handle is disposed.',
        statusCode: -1,
      );
    }
  }

  static void _throwIfNotOk({
    required int status,
    required Uint8List errorBytes,
    required String operation,
    bool nullHandle = false,
  }) {
    if (status == _sdStatusOk && !nullHandle) {
      return;
    }

    throw RustCanvasEngineException(
      '$operation failed with status=$status. ${_formatErrorBytes(errorBytes)}',
      statusCode: status,
    );
  }

  static String _formatErrorBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return 'No native error payload.';
    }

    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) {
        return 'error="${text.length > 200 ? '${text.substring(0, 200)}...' : text}"';
      }
    } catch (_) {
      // Fallback to hex preview.
    }

    final previewLength = bytes.length < 32 ? bytes.length : 32;
    final preview = bytes
        .sublist(0, previewLength)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'error_bytes=0x$preview${bytes.length > previewLength ? '...' : ''}';
  }
}

final class _RustBindings {
  _RustBindings(ffi.DynamicLibrary library)
    : engineAbiVersion = library
          .lookupFunction<_EngineAbiVersionNative, _EngineAbiVersionDart>(
            'sd_engine_abi_version',
          ),
      engineCapabilities = library
          .lookupFunction<_EngineCapabilitiesNative, _EngineCapabilitiesDart>(
            'sd_engine_capabilities',
          ),
      engineCreate = library
          .lookupFunction<_EngineCreateNative, _EngineCreateDart>(
            'sd_engine_create',
          ),
      engineV2Create = library
          .lookupFunction<_EngineCreateNative, _EngineCreateDart>(
            'sd_engine_v2_create',
          ),
      engineDestroy = library
          .lookupFunction<_EngineDestroyNative, _EngineDestroyDart>(
            'sd_engine_destroy',
          ),
      engineDispatch = library
          .lookupFunction<_EngineDispatchNative, _EngineDispatchDart>(
            'sd_engine_dispatch',
          ),
      engineDispatchBatch = library
          .lookupFunction<_EngineDispatchBatchNative, _EngineDispatchBatchDart>(
            'sd_engine_dispatch_batch',
          ),
      engineGetSnapshot = library
          .lookupFunction<_EngineGetSnapshotNative, _EngineGetSnapshotDart>(
            'sd_engine_get_snapshot',
          ),
      engineBuildFramePlan = library
          .lookupFunction<
            _EngineBuildFramePlanNative,
            _EngineBuildFramePlanDart
          >('sd_engine_build_frame_plan'),
      enginePollEvent = library
          .lookupFunction<_EnginePollEventNative, _EnginePollEventDart>(
            'sd_engine_poll_event',
          ),
      engineV2ProcessInput = library
          .lookupFunction<
            _EngineV2ProcessInputNative,
            _EngineV2ProcessInputDart
          >('sd_engine_v2_process_input'),
      engineV2PollOutput = library
          .lookupFunction<_EngineV2PollOutputNative, _EngineV2PollOutputDart>(
            'sd_engine_v2_poll_output',
          ),
      bytesFree = library.lookupFunction<_BytesFreeNative, _BytesFreeDart>(
        'sd_bytes_free',
      );

  final _EngineAbiVersionDart engineAbiVersion;
  final _EngineCapabilitiesDart engineCapabilities;
  final _EngineCreateDart engineCreate;
  final _EngineCreateDart engineV2Create;
  final _EngineDestroyDart engineDestroy;
  final _EngineDispatchDart engineDispatch;
  final _EngineDispatchBatchDart engineDispatchBatch;
  final _EngineGetSnapshotDart engineGetSnapshot;
  final _EngineBuildFramePlanDart engineBuildFramePlan;
  final _EnginePollEventDart enginePollEvent;
  final _EngineV2ProcessInputDart engineV2ProcessInput;
  final _EngineV2PollOutputDart engineV2PollOutput;
  final _BytesFreeDart bytesFree;

  Uint8List takeOwnedBytes(_SdBytes bytes) {
    if (bytes.ptr == ffi.nullptr || bytes.len == 0) {
      return Uint8List(0);
    }

    final result = Uint8List.fromList(bytes.ptr.asTypedList(bytes.len));
    bytesFree(bytes);
    return result;
  }

  static ffi.DynamicLibrary openDefaultLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libsnow_draw_engine_capi.dylib');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('snow_draw_engine_capi.dll');
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libsnow_draw_engine_capi.so');
    }

    throw UnsupportedError(
      'Rust engine ABI library loading is not supported on this platform.',
    );
  }
}

final class _NativeBytes {
  _NativeBytes._(this.pointer, this.length);

  final ffi.Pointer<ffi.Uint8> pointer;
  final int length;

  void dispose() {
    if (pointer != ffi.nullptr) {
      calloc.free(pointer);
    }
  }

  static _NativeBytes fromDart(Uint8List bytes) {
    if (bytes.isEmpty) {
      return _NativeBytes._(ffi.nullptr, 0);
    }

    final pointer = calloc<ffi.Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return _NativeBytes._(pointer, bytes.length);
  }
}

void _setSdBytes(
  ffi.Pointer<_SdBytes> target,
  ffi.Pointer<ffi.Uint8> ptr,
  int len,
) {
  target.ref.ptr = ptr;
  target.ref.len = len;
}

final class _SdEngine extends ffi.Opaque {}

final class _SdBytes extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.Size()
  external int len;
}

typedef _EngineAbiVersionNative = ffi.Uint32 Function();
typedef _EngineAbiVersionDart = int Function();

typedef _EngineCapabilitiesNative = ffi.Uint64 Function();
typedef _EngineCapabilitiesDart = int Function();

typedef _EngineCreateNative =
    ffi.Pointer<_SdEngine> Function(
      _SdBytes configBytes,
      ffi.Pointer<ffi.Uint32> outStatus,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineCreateDart =
    ffi.Pointer<_SdEngine> Function(
      _SdBytes configBytes,
      ffi.Pointer<ffi.Uint32> outStatus,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineDestroyNative = ffi.Void Function(ffi.Pointer<_SdEngine> engine);
typedef _EngineDestroyDart = void Function(ffi.Pointer<_SdEngine> engine);

typedef _EngineDispatchNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes commandBytes,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineDispatchDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes commandBytes,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineDispatchBatchNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> commandBytes,
      ffi.Size commandCount,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineDispatchBatchDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> commandBytes,
      int commandCount,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineGetSnapshotNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outSnapshot,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineGetSnapshotDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outSnapshot,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineBuildFramePlanNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes requestBytes,
      ffi.Pointer<_SdBytes> outPlan,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineBuildFramePlanDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes requestBytes,
      ffi.Pointer<_SdBytes> outPlan,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EnginePollEventNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outEvent,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EnginePollEventDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outEvent,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineV2ProcessInputNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes inputBytes,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineV2ProcessInputDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      _SdBytes inputBytes,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _EngineV2PollOutputNative =
    ffi.Uint32 Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outOutput,
      ffi.Pointer<_SdBytes> outError,
    );
typedef _EngineV2PollOutputDart =
    int Function(
      ffi.Pointer<_SdEngine> engine,
      ffi.Pointer<_SdBytes> outOutput,
      ffi.Pointer<_SdBytes> outError,
    );

typedef _BytesFreeNative = ffi.Void Function(_SdBytes bytes);
typedef _BytesFreeDart = void Function(_SdBytes bytes);
