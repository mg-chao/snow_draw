import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../rust_canvas_engine.dart';
import '../actions/config_actions.dart';
import '../actions/draw_actions.dart';
import '../config/config_manager.dart';
import '../config/draw_config.dart';
import '../core/callbacks.dart';
import '../core/draw_context.dart';
import '../edit/core/edit_modifiers.dart';
import '../edit/core/edit_operation_params.dart';
import '../elements/core/element_data.dart';
import '../events/error_events.dart';
import '../events/event_bus.dart';
import '../events/state_events.dart';
import '../models/application_state.dart';
import '../models/camera_state.dart';
import '../models/document_state.dart';
import '../models/domain_state.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/global_elements_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_state.dart';
import '../models/view_state.dart';
import '../types/draw_color.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import 'draw_store_interface.dart';
import 'listener_registry.dart';
import 'selector.dart';
import 'state_change_detector.dart';

/// Rust-backed draw store adapter.
///
/// This store drives state transitions through the Rust engine C ABI.
class RustDrawStore implements DrawStore {
  RustDrawStore({
    required DrawContext context,
    DrawState? initialState,
    EventBus? eventBus,
    RustCanvasEngine? engine,
    Uint8List? engineConfigBytes,
  }) : _ownsEventBus = eventBus == null && context.eventBus == null,
       _eventBus = eventBus ?? context.eventBus ?? EventBus(),
       _engine =
           engine ?? RustCanvasEngine.create(configBytes: engineConfigBytes) {
    this.context = context.eventBus == _eventBus
        ? context
        : context.copyWith(eventBus: _eventBus);
    _configManager = this.context.configManager;
    _listenerRegistry = ListenerRegistry(
      onError: (error, stackTrace) {
        this.context.log.store.error(
          'Listener threw during notification',
          error,
          stackTrace,
        );
      },
    );

    if (initialState != null && !_isEmptyInitialState(initialState)) {
      throw UnsupportedError(
        'RustDrawStore currently supports only empty initialState.',
      );
    }

    _state = _decodeSnapshot(_engine.getSnapshotBytes());
    _canUndo = false;
    _canRedo = false;
    _syncHistoryFlagsFromSnapshot();
  }

  @override
  late final DrawContext context;

  late DrawState _state;
  late final ConfigManager _configManager;
  late final ListenerRegistry _listenerRegistry;
  final EventBus _eventBus;
  final bool _ownsEventBus;
  final RustCanvasEngine _engine;

  var _isDisposed = false;
  var _canUndo = false;
  var _canRedo = false;

  @override
  bool get canUndo => _canUndo;

  @override
  bool get canRedo => _canRedo;

  @override
  DrawState get state => _state;

  @override
  DrawConfig get config => _configManager.current;

  @override
  Stream<DrawConfig> get configStream => _configManager.stream;

  EventBus get eventBus => _eventBus;

  @override
  Stream<DrawEvent> get eventStream => _eventBus.stream;

  @override
  Stream<T> eventStreamOf<T extends DrawEvent>() => _eventBus.streamOf<T>();

  @override
  StreamSubscription<T> onEvent<T extends DrawEvent>(
    void Function(T event) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _eventBus.on<T>(
    handler,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    _checkNotDisposed();
    return _listenerRegistry.register(listener, changeTypes: changeTypes);
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _listenerRegistry.unregister(listener);
  }

  @override
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
    Set<DrawStateChange>? changeTypes,
  }) {
    _checkNotDisposed();

    final equalsFn = equals ?? selector.equals;
    var previousValue = selector.select(state);

    return listen((state) {
      final newValue = selector.select(state);
      if (!equalsFn(previousValue, newValue)) {
        previousValue = newValue;
        listener(newValue);
      }
    }, changeTypes: changeTypes);
  }

  @override
  Future<void> dispatch(DrawAction action) async {
    _checkNotDisposed();

    if (action is UpdateConfig) {
      _configManager.update(action.config);
      return;
    }
    if (action is UpdateSelectionConfig) {
      _configManager.update(
        _configManager.current.copyWith(selection: action.selection),
      );
      return;
    }
    if (action is UpdateCanvasConfig) {
      _configManager.update(
        _configManager.current.copyWith(canvas: action.canvas),
      );
      return;
    }

    final command = _RustProtoCodec.encodeAction(action, context: context);
    if (command == null) {
      _eventBus.emit(
        ValidationFailedEvent(
          action: action.runtimeType.toString(),
          reason: 'Unsupported by Rust command bridge',
        ),
      );
      throw UnsupportedError(
        'Unsupported action for RustDrawStore: ${action.runtimeType}',
      );
    }

    _engine.dispatch(command);
    _drainNativeEvents();
    _refreshSnapshotAndNotify();
  }

  @override
  Future<void> undo() => dispatch(const Undo());

  @override
  Future<void> redo() => dispatch(const Redo());

  @override
  Future<void> clearHistory() => dispatch(const ClearHistory());

  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _engine.dispose();

    unawaited(_configManager.dispose());
    if (_ownsEventBus) {
      unawaited(_eventBus.dispose());
    }
    _listenerRegistry.clear();
    context.log.dispose();
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('DrawStore has been disposed and cannot be used');
    }
  }

  bool _isEmptyInitialState(DrawState state) =>
      state.domain.document.elements.isEmpty &&
      state.domain.selection.selectedIds.isEmpty &&
      state.domain.document.elementsVersion == 0 &&
      state.domain.selection.selectionVersion == 0;

  void _refreshSnapshotAndNotify() {
    final previous = _state;
    final next = _decodeSnapshot(_engine.getSnapshotBytes());
    _state = next;

    _syncHistoryFlagsFromSnapshot();

    if (previous != next) {
      _listenerRegistry.notify(previous, next);
    }

    final changes = computeDrawStateChanges(previous, next);
    if (changes.contains(DrawStateChange.document)) {
      _eventBus.emit(
        DocumentChangedEvent(
          elementsVersion: next.domain.document.elementsVersion,
          elementCount: next.domain.document.elements.length,
        ),
      );
    }
    if (changes.contains(DrawStateChange.selection)) {
      _eventBus.emit(
        SelectionChangedEvent(
          selectedIds: next.domain.selection.selectedIds,
          selectionVersion: next.domain.selection.selectionVersion,
        ),
      );
    }
    if (changes.contains(DrawStateChange.view)) {
      _eventBus.emit(ViewChangedEvent(camera: next.application.view.camera));
    }
    if (changes.contains(DrawStateChange.interaction)) {
      _eventBus.emit(
        InteractionChangedEvent(interaction: next.application.interaction),
      );
    }
  }

  void _syncHistoryFlagsFromSnapshot() {
    final nextCanUndo = _RustProtoCodec.lastDecodedHistoryUndo > 0;
    final nextCanRedo = _RustProtoCodec.lastDecodedHistoryRedo > 0;

    if (nextCanUndo != _canUndo || nextCanRedo != _canRedo) {
      _canUndo = nextCanUndo;
      _canRedo = nextCanRedo;
      _eventBus.emit(
        HistoryAvailabilityChangedEvent(canUndo: _canUndo, canRedo: _canRedo),
      );
    } else {
      _canUndo = nextCanUndo;
      _canRedo = nextCanRedo;
    }
  }

  void _drainNativeEvents() {
    while (true) {
      final bytes = _engine.pollEventBytes();
      if (bytes == null) {
        break;
      }
      final event = _RustProtoCodec.decodeEvent(bytes);
      if (event == null) {
        continue;
      }
      if (event.kind == _RustProtoCodec.engineEventError) {
        _eventBus.emit(
          ErrorEvent(
            message: event.message ?? 'Rust engine error',
            error: event.message ?? 'rust_engine_error',
          ),
        );
      }
    }
  }

  DrawState _decodeSnapshot(Uint8List bytes) =>
      _RustProtoCodec.decodeSnapshot(bytes).toDrawState(context);
}

final class _RustProtoCodec {
  const _RustProtoCodec._();

  static const int _wireVarint = 0;
  static const int _wireFixed64 = 1;
  static const int _wireLengthDelimited = 2;

  static const int commandKindSelectElement = 1;
  static const int commandKindClearSelection = 2;
  static const int commandKindSelectAll = 3;
  static const int commandKindCreateElement = 4;
  static const int commandKindUpdateCreatingElement = 5;
  static const int commandKindAddArrowPoint = 6;
  static const int commandKindFinishCreateElement = 7;
  static const int commandKindCancelCreateElement = 8;
  static const int commandKindDeleteElements = 9;
  static const int commandKindDuplicateElements = 10;
  static const int commandKindChangeElementZIndex = 11;
  static const int commandKindChangeElementsZIndex = 12;
  static const int commandKindUpdateElementsStyle = 13;
  static const int commandKindUpdateGlobalElements = 14;
  static const int commandKindCreateSerialText = 15;
  static const int commandKindStartTextEdit = 16;
  static const int commandKindUpdateTextEdit = 17;
  static const int commandKindRefreshTextLayouts = 18;
  static const int commandKindFinishTextEdit = 19;
  static const int commandKindCancelTextEdit = 20;
  static const int commandKindStartEdit = 21;
  static const int commandKindUpdateEdit = 22;
  static const int commandKindFinishEdit = 23;
  static const int commandKindCancelEdit = 24;
  static const int commandKindSetDragPending = 25;
  static const int commandKindClearDragPending = 26;
  static const int commandKindStartBoxSelect = 27;
  static const int commandKindUpdateBoxSelect = 28;
  static const int commandKindFinishBoxSelect = 29;
  static const int commandKindCancelBoxSelect = 30;
  static const int commandKindMoveCamera = 31;
  static const int commandKindZoomCamera = 32;
  static const int commandKindUndo = 33;
  static const int commandKindRedo = 34;
  static const int commandKindClearHistory = 35;

  static const int _elementRectangle = 1;
  static const int _elementArrow = 2;
  static const int _elementLine = 3;
  static const int _elementFreeDraw = 4;
  static const int _elementFilter = 5;
  static const int _elementHighlight = 6;
  static const int _elementText = 7;
  static const int _elementSerialNumber = 8;

  static const int engineEventError = 3;

  static int lastDecodedHistoryUndo = 0;
  static int lastDecodedHistoryRedo = 0;

  static Uint8List? encodeAction(
    DrawAction action, {
    required DrawContext context,
  }) {
    return switch (action) {
      SelectElement(:final elementId, :final addToSelection, :final position) =>
        _encodeCommand(
          kind: commandKindSelectElement,
          payloadTag: 11,
          payload: _encodeSelectElement(
            elementId: elementId,
            addToSelection: addToSelection,
            position: position,
          ),
        ),
      ClearSelection() => _encodeCommand(kind: commandKindClearSelection),
      SelectAll() => _encodeCommand(kind: commandKindSelectAll),
      CreateElement(
        :final typeId,
        :final position,
        :final initialData,
        :final maintainAspectRatio,
        :final createFromCenter,
        :final snapOverride,
      ) =>
        _encodeCommand(
          kind: commandKindCreateElement,
          payloadTag: 10,
          payload: _encodeCreateElement(
            elementType: _elementTypeFromTypeValue(typeId.value),
            elementId: context.idGenerator(),
            position: position,
            payload: initialData == null
                ? Uint8List(0)
                : Uint8List.fromList(
                    utf8.encode(jsonEncode(initialData.toJson())),
                  ),
            maintainAspectRatio: maintainAspectRatio,
            createFromCenter: createFromCenter,
            snapOverride: snapOverride,
          ),
        ),
      UpdateCreatingElement(
        :final positions,
        :final maintainAspectRatio,
        :final createFromCenter,
        :final snapOverride,
      ) =>
        _encodeCommand(
          kind: commandKindUpdateCreatingElement,
          payloadTag: 16,
          payload: _encodeUpdateCreatingElement(
            positions: positions,
            maintainAspectRatio: maintainAspectRatio,
            createFromCenter: createFromCenter,
            snapOverride: snapOverride,
          ),
        ),
      AddArrowPoint(:final position, :final snapOverride) => _encodeCommand(
        kind: commandKindAddArrowPoint,
        payloadTag: 17,
        payload: _encodeAddArrowPoint(
          position: position,
          snapOverride: snapOverride,
        ),
      ),
      FinishCreateElement() => _encodeCommand(
        kind: commandKindFinishCreateElement,
      ),
      CancelCreateElement() => _encodeCommand(
        kind: commandKindCancelCreateElement,
      ),
      DeleteElements(:final elementIds) => _encodeCommand(
        kind: commandKindDeleteElements,
        payloadTag: 12,
        payload: _encodeDeleteElements(elementIds),
      ),
      DuplicateElements(:final elementIds, :final offsetX, :final offsetY) =>
        _encodeCommand(
          kind: commandKindDuplicateElements,
          payloadTag: 18,
          payload: _encodeDuplicateElements(
            elementIds: elementIds,
            offsetX: offsetX,
            offsetY: offsetY,
          ),
        ),
      ChangeElementZIndex(:final elementId, :final operation) => _encodeCommand(
        kind: commandKindChangeElementZIndex,
        payloadTag: 19,
        payload: _encodeChangeElementZIndex(
          elementId: elementId,
          operation: operation,
        ),
      ),
      ChangeElementsZIndex(:final elementIds, :final operation) =>
        _encodeCommand(
          kind: commandKindChangeElementsZIndex,
          payloadTag: 20,
          payload: _encodeChangeElementsZIndex(
            elementIds: elementIds,
            operation: operation,
          ),
        ),
      UpdateElementsStyle() => _encodeCommand(
        kind: commandKindUpdateElementsStyle,
        payloadTag: 13,
        payload: _encodeUpdateElementsStyle(action),
      ),
      UpdateGlobalElements(:final highlightMask, :final watermark) =>
        _encodeCommand(
          kind: commandKindUpdateGlobalElements,
          payloadTag: 21,
          payload: _encodeUpdateGlobalElements(
            highlightMask: highlightMask,
            watermark: watermark,
          ),
        ),
      CreateSerialNumberTextElements(:final elementIds) => _encodeCommand(
        kind: commandKindCreateSerialText,
        payloadTag: 22,
        payload: _encodeCreateSerialText(elementIds),
      ),
      StartTextEdit(:final elementId, :final position) => _encodeCommand(
        kind: commandKindStartTextEdit,
        payloadTag: 23,
        payload: _encodeStartTextEdit(elementId: elementId, position: position),
      ),
      UpdateTextEdit(:final text, :final rect) => _encodeCommand(
        kind: commandKindUpdateTextEdit,
        payloadTag: 24,
        payload: _encodeUpdateTextEdit(text: text, rect: rect),
      ),
      RefreshAutoResizeTextLayoutsAfterFontLoad() => _encodeCommand(
        kind: commandKindRefreshTextLayouts,
      ),
      FinishTextEdit(:final elementId, :final text, :final isNew) =>
        _encodeCommand(
          kind: commandKindFinishTextEdit,
          payloadTag: 25,
          payload: _encodeFinishTextEdit(
            elementId: elementId,
            text: text,
            isNew: isNew,
          ),
        ),
      CancelTextEdit() => _encodeCommand(kind: commandKindCancelTextEdit),
      StartEdit(:final operationId, :final position, :final params) =>
        _encodeCommand(
          kind: commandKindStartEdit,
          payloadTag: 26,
          payload: _encodeStartEdit(
            operationId: operationId,
            position: position,
            params: params,
          ),
        ),
      UpdateEdit(:final currentPosition, :final modifiers) => _encodeCommand(
        kind: commandKindUpdateEdit,
        payloadTag: 27,
        payload: _encodeUpdateEdit(
          currentPosition: currentPosition,
          modifiers: modifiers,
        ),
      ),
      FinishEdit() => _encodeCommand(kind: commandKindFinishEdit),
      CancelEdit() => _encodeCommand(kind: commandKindCancelEdit),
      SetDragPending(:final pointerDownPosition, :final intent) =>
        _encodeCommand(
          kind: commandKindSetDragPending,
          payloadTag: 28,
          payload: _encodeSetDragPending(
            pointerDownPosition: pointerDownPosition,
            intent: intent,
          ),
        ),
      ClearDragPending() => _encodeCommand(kind: commandKindClearDragPending),
      StartBoxSelect(:final startPosition) => _encodeCommand(
        kind: commandKindStartBoxSelect,
        payloadTag: 29,
        payload: _encodeStartBoxSelect(startPosition),
      ),
      UpdateBoxSelect(:final currentPosition) => _encodeCommand(
        kind: commandKindUpdateBoxSelect,
        payloadTag: 30,
        payload: _encodeUpdateBoxSelect(currentPosition),
      ),
      FinishBoxSelect() => _encodeCommand(kind: commandKindFinishBoxSelect),
      CancelBoxSelect() => _encodeCommand(kind: commandKindCancelBoxSelect),
      MoveCamera(:final dx, :final dy) => _encodeCommand(
        kind: commandKindMoveCamera,
        payloadTag: 14,
        payload: _encodeMoveCamera(dx: dx, dy: dy),
      ),
      ZoomCamera(:final scale, :final center) => _encodeCommand(
        kind: commandKindZoomCamera,
        payloadTag: 15,
        payload: _encodeZoomCamera(scale: scale, center: center),
      ),
      Undo() => _encodeCommand(kind: commandKindUndo),
      Redo() => _encodeCommand(kind: commandKindRedo),
      ClearHistory() => _encodeCommand(kind: commandKindClearHistory),
      _ => null,
    };
  }

  static _DecodedSnapshot decodeSnapshot(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final snapshot = _DecodedSnapshot();

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 2:
          snapshot.documentVersion = reader.readVarint();
        case 3:
          snapshot.selectionVersion = reader.readVarint();
        case 4:
          snapshot.interactionMode = reader.readVarint();
        case 5:
          final cameraReader = _ProtoReader(reader.readBytes());
          snapshot.camera = _decodeCamera(cameraReader);
        case 6:
          final elementReader = _ProtoReader(reader.readBytes());
          snapshot.elements.add(_decodeElement(elementReader));
        case 7:
          snapshot.selectedIds.add(reader.readString());
        case 8:
          snapshot.historyUndoLen = reader.readVarint();
        case 9:
          snapshot.historyRedoLen = reader.readVarint();
        case 10:
          snapshot.globalPayload = reader.readBytes();
        default:
          reader.skipField(wireType);
      }
    }

    lastDecodedHistoryUndo = snapshot.historyUndoLen;
    lastDecodedHistoryRedo = snapshot.historyRedoLen;
    return snapshot;
  }

  static _DecodedEvent? decodeEvent(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final event = _DecodedEvent();

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 1:
          event.kind = reader.readVarint();
        case 12:
          event.message = reader.readString();
        case 10:
          final errorReader = _ProtoReader(reader.readBytes());
          while (!errorReader.isDone) {
            final errorTag = errorReader.readTag();
            if (errorTag == 0) {
              break;
            }
            final errorField = errorTag >> 3;
            final errorWire = errorTag & 0x07;
            switch (errorField) {
              case 2:
                event.message = errorReader.readString();
              default:
                errorReader.skipField(errorWire);
            }
          }
        default:
          reader.skipField(wireType);
      }
    }

    return event.kind == 0 ? null : event;
  }

  static Uint8List _encodeCommand({
    required int kind,
    int? payloadTag,
    Uint8List? payload,
  }) {
    final writer = _ProtoWriter();
    writer.writeEnum(1, kind);
    if (payloadTag != null && payload != null) {
      writer.writeMessage(payloadTag, payload);
    }
    return writer.takeBytes();
  }

  static Uint8List _encodeSelectElement({
    required String elementId,
    required bool addToSelection,
    required DrawPoint position,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, elementId);
    writer.writeBool(2, addToSelection);
    writer.writeMessage(3, _encodePoint(position));
    return writer.takeBytes();
  }

  static Uint8List _encodeCreateElement({
    required int elementType,
    required String elementId,
    required DrawPoint position,
    required Uint8List payload,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required bool snapOverride,
  }) {
    final writer = _ProtoWriter();
    writer.writeEnum(1, elementType);
    writer.writeString(2, elementId);
    writer.writeMessage(3, _encodePoint(position));
    if (payload.isNotEmpty) {
      writer.writeBytes(4, payload);
    }
    writer.writeBool(5, maintainAspectRatio);
    writer.writeBool(6, createFromCenter);
    writer.writeBool(7, snapOverride);
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateCreatingElement({
    required List<DrawPoint> positions,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required bool snapOverride,
  }) {
    final writer = _ProtoWriter();
    for (final point in positions) {
      writer.writeMessage(1, _encodePoint(point));
    }
    writer.writeBool(2, maintainAspectRatio);
    writer.writeBool(3, createFromCenter);
    writer.writeBool(4, snapOverride);
    return writer.takeBytes();
  }

  static Uint8List _encodeAddArrowPoint({
    required DrawPoint position,
    required bool snapOverride,
  }) {
    final writer = _ProtoWriter();
    writer.writeMessage(1, _encodePoint(position));
    writer.writeBool(2, snapOverride);
    return writer.takeBytes();
  }

  static Uint8List _encodeDeleteElements(List<String> elementIds) {
    final writer = _ProtoWriter();
    for (final elementId in elementIds) {
      writer.writeString(1, elementId);
    }
    return writer.takeBytes();
  }

  static Uint8List _encodeDuplicateElements({
    required List<String> elementIds,
    required double offsetX,
    required double offsetY,
  }) {
    final writer = _ProtoWriter();
    for (final elementId in elementIds) {
      writer.writeString(1, elementId);
    }
    writer.writeDouble(2, offsetX);
    writer.writeDouble(3, offsetY);
    return writer.takeBytes();
  }

  static Uint8List _encodeChangeElementZIndex({
    required String elementId,
    required ZIndexOperation operation,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, elementId);
    writer.writeEnum(2, _zIndexOperationValue(operation));
    return writer.takeBytes();
  }

  static Uint8List _encodeChangeElementsZIndex({
    required List<String> elementIds,
    required ZIndexOperation operation,
  }) {
    final writer = _ProtoWriter();
    for (final elementId in elementIds) {
      writer.writeString(1, elementId);
    }
    writer.writeEnum(2, _zIndexOperationValue(operation));
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateElementsStyle(UpdateElementsStyle action) {
    final style = <String, dynamic>{};
    if (action.color != null) {
      style['color'] = action.color!.toARGB32();
    }
    if (action.fillColor != null) {
      style['fillColor'] = action.fillColor!.toARGB32();
    }
    if (action.strokeWidth != null) {
      style['strokeWidth'] = action.strokeWidth;
    }
    if (action.strokeStyle != null) {
      style['strokeStyle'] = action.strokeStyle!.name;
    }
    if (action.fillStyle != null) {
      style['fillStyle'] = action.fillStyle!.name;
    }
    if (action.filterType != null) {
      style['filterType'] = action.filterType!.name;
    }
    if (action.filterStrength != null) {
      style['filterStrength'] = action.filterStrength;
    }
    if (action.cornerRadius != null) {
      style['cornerRadius'] = action.cornerRadius;
    }
    if (action.arrowType != null) {
      style['arrowType'] = action.arrowType!.name;
    }
    if (action.startArrowhead != null) {
      style['startArrowhead'] = action.startArrowhead!.name;
    }
    if (action.endArrowhead != null) {
      style['endArrowhead'] = action.endArrowhead!.name;
    }
    if (action.fontSize != null) {
      style['fontSize'] = action.fontSize;
    }
    if (action.fontFamily != null) {
      style['fontFamily'] = action.fontFamily;
    }
    if (action.textAlign != null) {
      style['textAlign'] = action.textAlign!.name;
    }
    if (action.verticalAlign != null) {
      style['verticalAlign'] = action.verticalAlign!.name;
    }
    if (action.opacity != null) {
      style['opacity'] = action.opacity;
    }
    if (action.textStrokeColor != null) {
      style['textStrokeColor'] = action.textStrokeColor!.toARGB32();
    }
    if (action.textStrokeWidth != null) {
      style['textStrokeWidth'] = action.textStrokeWidth;
    }
    if (action.highlightShape != null) {
      style['highlightShape'] = action.highlightShape!.name;
    }
    if (action.serialNumber != null) {
      style['serialNumber'] = action.serialNumber;
    }

    final writer = _ProtoWriter();
    for (final elementId in action.elementIds) {
      writer.writeString(1, elementId);
    }
    writer.writeBytes(2, Uint8List.fromList(utf8.encode(jsonEncode(style))));
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateGlobalElements({
    required HighlightMaskConfig? highlightMask,
    required WatermarkConfig? watermark,
  }) {
    final payload = <String, dynamic>{};
    if (highlightMask != null) {
      payload['highlightMask'] = {
        'maskColor': highlightMask.maskColor.toARGB32(),
        'maskOpacity': highlightMask.maskOpacity,
      };
    }
    if (watermark != null) {
      payload['watermark'] = {
        'color': watermark.color.toARGB32(),
        'text': watermark.text,
        'fontSize': watermark.fontSize,
        'fontFamily': watermark.fontFamily,
        'angle': watermark.angle,
        'gap': watermark.gap,
        'opacity': watermark.opacity,
      };
    }

    final writer = _ProtoWriter();
    writer.writeBytes(1, Uint8List.fromList(utf8.encode(jsonEncode(payload))));
    return writer.takeBytes();
  }

  static Uint8List _encodeCreateSerialText(List<String> elementIds) {
    final writer = _ProtoWriter();
    for (final elementId in elementIds) {
      writer.writeString(1, elementId);
    }
    return writer.takeBytes();
  }

  static Uint8List _encodeStartTextEdit({
    required String? elementId,
    required DrawPoint position,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, elementId ?? '');
    writer.writeMessage(2, _encodePoint(position));
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateTextEdit({
    required String text,
    required DrawRect? rect,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, text);
    if (rect != null) {
      writer.writeMessage(2, _encodeRect(rect));
    }
    return writer.takeBytes();
  }

  static Uint8List _encodeFinishTextEdit({
    required String elementId,
    required String text,
    required bool isNew,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, elementId);
    writer.writeString(2, text);
    writer.writeBool(3, isNew);
    return writer.takeBytes();
  }

  static Uint8List _encodeStartEdit({
    required String operationId,
    required DrawPoint position,
    required Object params,
  }) {
    final writer = _ProtoWriter();
    writer.writeString(1, operationId);
    writer.writeMessage(2, _encodePoint(position));
    writer.writeBytes(
      3,
      Uint8List.fromList(utf8.encode(jsonEncode(_editParamsToJson(params)))),
    );
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateEdit({
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
  }) {
    final writer = _ProtoWriter();
    writer.writeMessage(1, _encodePoint(currentPosition));
    writer.writeBytes(
      2,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'maintainAspectRatio': modifiers.maintainAspectRatio,
            'fromCenter': modifiers.fromCenter,
            'discreteAngle': modifiers.discreteAngle,
            'snapOverride': modifiers.snapOverride,
          }),
        ),
      ),
    );
    return writer.takeBytes();
  }

  static Uint8List _encodeSetDragPending({
    required DrawPoint pointerDownPosition,
    required PendingIntent intent,
  }) {
    final writer = _ProtoWriter();
    writer.writeMessage(1, _encodePoint(pointerDownPosition));
    writer.writeString(2, intent.toString());
    return writer.takeBytes();
  }

  static Uint8List _encodeStartBoxSelect(DrawPoint startPosition) {
    final writer = _ProtoWriter();
    writer.writeMessage(1, _encodePoint(startPosition));
    return writer.takeBytes();
  }

  static Uint8List _encodeUpdateBoxSelect(DrawPoint currentPosition) {
    final writer = _ProtoWriter();
    writer.writeMessage(1, _encodePoint(currentPosition));
    return writer.takeBytes();
  }

  static Uint8List _encodeMoveCamera({required double dx, required double dy}) {
    final writer = _ProtoWriter();
    writer.writeDouble(1, dx);
    writer.writeDouble(2, dy);
    return writer.takeBytes();
  }

  static Uint8List _encodeZoomCamera({
    required double scale,
    required DrawPoint? center,
  }) {
    final writer = _ProtoWriter();
    writer.writeDouble(1, scale);
    if (center != null) {
      writer.writeMessage(2, _encodePoint(center));
    }
    return writer.takeBytes();
  }

  static Uint8List _encodePoint(DrawPoint point) {
    final writer = _ProtoWriter();
    writer.writeDouble(1, point.x);
    writer.writeDouble(2, point.y);
    writer.writeDouble(3, point.pressure);
    writer.writeUInt64(4, point.timestamp);
    return writer.takeBytes();
  }

  static Uint8List _encodeRect(DrawRect rect) {
    final writer = _ProtoWriter();
    writer.writeDouble(1, rect.minX);
    writer.writeDouble(2, rect.minY);
    writer.writeDouble(3, rect.maxX);
    writer.writeDouble(4, rect.maxY);
    return writer.takeBytes();
  }

  static int _elementTypeFromTypeValue(String typeValue) => switch (typeValue) {
    'rectangle' => _elementRectangle,
    'arrow' => _elementArrow,
    'line' => _elementLine,
    'free_draw' => _elementFreeDraw,
    'filter' => _elementFilter,
    'highlight' => _elementHighlight,
    'text' => _elementText,
    'serial_number' => _elementSerialNumber,
    _ => _elementRectangle,
  };

  static String _typeValueFromElementType(int elementType) =>
      switch (elementType) {
        _elementRectangle => 'rectangle',
        _elementArrow => 'arrow',
        _elementLine => 'line',
        _elementFreeDraw => 'free_draw',
        _elementFilter => 'filter',
        _elementHighlight => 'highlight',
        _elementText => 'text',
        _elementSerialNumber => 'serial_number',
        _ => 'rectangle',
      };

  static int _zIndexOperationValue(ZIndexOperation operation) =>
      switch (operation) {
        ZIndexOperation.bringToFront => 0,
        ZIndexOperation.sendToBack => 1,
        ZIndexOperation.bringForward => 2,
        ZIndexOperation.sendBackward => 3,
      };

  static Map<String, dynamic> _editParamsToJson(Object params) =>
      switch (params) {
        MoveOperationParams() => const {'type': 'move'},
        ResizeOperationParams(
          :final resizeMode,
          :final handleOffset,
          :final selectionPadding,
        ) =>
          {
            'type': 'resize',
            'resizeMode': resizeMode.name,
            'handleOffset': handleOffset == null
                ? null
                : {'x': handleOffset.x, 'y': handleOffset.y},
            'selectionPadding': selectionPadding,
          },
        RotateOperationParams(
          :final startRotationAngle,
          :final rotationSnapAngle,
        ) =>
          {
            'type': 'rotate',
            'startRotationAngle': startRotationAngle,
            'rotationSnapAngle': rotationSnapAngle,
          },
        ArrowPointOperationParams(
          :final elementId,
          :final pointKind,
          :final pointIndex,
          :final isDoubleClick,
        ) =>
          {
            'type': 'arrow_point',
            'elementId': elementId,
            'pointKind': pointKind.name,
            'pointIndex': pointIndex,
            'isDoubleClick': isDoubleClick,
          },
        _ => const {'type': 'unknown'},
      };

  static CameraState _decodeCamera(_ProtoReader reader) {
    var position = DrawPoint.zero;
    var zoom = 1.0;

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 1:
          position = _decodePoint(_ProtoReader(reader.readBytes()));
        case 2:
          zoom = reader.readDouble();
        default:
          reader.skipField(wireType);
      }
    }

    return CameraState(position: position, zoom: zoom);
  }

  static _DecodedElement _decodeElement(_ProtoReader reader) {
    final element = _DecodedElement();

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 1:
          element.id = reader.readString();
        case 2:
          element.elementType = reader.readVarint();
        case 3:
          element.rect = _decodeRect(_ProtoReader(reader.readBytes()));
        case 4:
          element.rotation = reader.readDouble();
        case 5:
          element.opacity = reader.readDouble();
        case 6:
          element.zIndex = reader.readVarint();
        case 7:
          element.payload = reader.readBytes();
        default:
          reader.skipField(wireType);
      }
    }

    return element;
  }

  static DrawPoint _decodePoint(_ProtoReader reader) {
    var x = 0.0;
    var y = 0.0;
    var pressure = 0.0;
    var timestamp = 0;

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 1:
          x = reader.readDouble();
        case 2:
          y = reader.readDouble();
        case 3:
          pressure = reader.readDouble();
        case 4:
          timestamp = reader.readVarint();
        default:
          reader.skipField(wireType);
      }
    }

    return DrawPoint(x: x, y: y, pressure: pressure, timestamp: timestamp);
  }

  static DrawRect _decodeRect(_ProtoReader reader) {
    var minX = 0.0;
    var minY = 0.0;
    var maxX = 0.0;
    var maxY = 0.0;

    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == 0) {
        break;
      }
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 1:
          minX = reader.readDouble();
        case 2:
          minY = reader.readDouble();
        case 3:
          maxX = reader.readDouble();
        case 4:
          maxY = reader.readDouble();
        default:
          reader.skipField(wireType);
      }
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}

final class _DecodedSnapshot {
  int documentVersion = 0;
  int selectionVersion = 0;
  int interactionMode = 0;
  CameraState camera = CameraState.initial;
  int historyUndoLen = 0;
  int historyRedoLen = 0;
  Uint8List globalPayload = Uint8List(0);
  final List<String> selectedIds = <String>[];
  final List<_DecodedElement> elements = <_DecodedElement>[];

  DrawState toDrawState(DrawContext context) {
    final builtElements =
        elements.map((decoded) => decoded.toElementState(context)).toList()
          ..sort((a, b) {
            final z = a.zIndex.compareTo(b.zIndex);
            if (z != 0) {
              return z;
            }
            return a.id.compareTo(b.id);
          });

    final document = DocumentState(
      elements: List<ElementState>.unmodifiable(builtElements),
      elementsVersion: documentVersion,
      globalElements: _decodeGlobalElements(globalPayload),
    );

    final selection = SelectionState(
      selectedIds: Set<String>.unmodifiable(selectedIds.toSet()),
      selectionVersion: selectionVersion,
    );

    final view = ViewState(camera: camera);
    final interaction = interactionMode == 4
        ? const BoxSelectingState(
            startPosition: DrawPoint.zero,
            currentPosition: DrawPoint.zero,
          )
        : const IdleState();

    return DrawState(
      domain: DomainState(document: document, selection: selection),
      application: ApplicationState(view: view, interaction: interaction),
    );
  }

  GlobalElementsState _decodeGlobalElements(Uint8List payload) {
    if (payload.isEmpty) {
      return const GlobalElementsState();
    }

    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        return const GlobalElementsState();
      }
      final map = decoded.cast<String, dynamic>();

      HighlightMaskConfig highlightMask = const HighlightMaskConfig();
      final rawMask = map['highlightMask'];
      if (rawMask is Map) {
        final mask = rawMask.cast<String, dynamic>();
        final color = mask['maskColor'];
        final opacity = mask['maskOpacity'];
        highlightMask = HighlightMaskConfig(
          maskColor: color is int
              ? DrawColor(color)
              : const HighlightMaskConfig().maskColor,
          maskOpacity: opacity is num
              ? opacity.toDouble()
              : const HighlightMaskConfig().maskOpacity,
        );
      }

      WatermarkConfig watermark = const WatermarkConfig();
      final rawWatermark = map['watermark'];
      if (rawWatermark is Map) {
        final wm = rawWatermark.cast<String, dynamic>();
        watermark = WatermarkConfig(
          color: wm['color'] is int
              ? DrawColor(wm['color'] as int)
              : const WatermarkConfig().color,
          text: wm['text'] is String
              ? wm['text'] as String
              : const WatermarkConfig().text,
          fontSize: wm['fontSize'] is num
              ? (wm['fontSize'] as num).toDouble()
              : const WatermarkConfig().fontSize,
          fontFamily: wm['fontFamily'] is String
              ? wm['fontFamily'] as String
              : const WatermarkConfig().fontFamily,
          angle: wm['angle'] is num
              ? (wm['angle'] as num).toDouble()
              : const WatermarkConfig().angle,
          gap: wm['gap'] is num
              ? (wm['gap'] as num).toDouble()
              : const WatermarkConfig().gap,
          opacity: wm['opacity'] is num
              ? (wm['opacity'] as num).toDouble()
              : const WatermarkConfig().opacity,
        );
      }

      return GlobalElementsState(
        highlightMask: highlightMask,
        watermark: watermark,
      );
    } catch (_) {
      return const GlobalElementsState();
    }
  }
}

final class _DecodedElement {
  String id = '';
  int elementType = 1;
  DrawRect rect = const DrawRect();
  double rotation = 0.0;
  double opacity = 1.0;
  int zIndex = 0;
  Uint8List payload = Uint8List(0);

  ElementState toElementState(DrawContext context) {
    final typeValue = _RustProtoCodec._typeValueFromElementType(elementType);
    final definition = context.elementRegistry.getDefinitionByValue(typeValue);

    ElementData data;
    if (definition == null) {
      final fallback = context.elementRegistry.getDefinitionByValue(
        'rectangle',
      );
      data = fallback == null
          ? throw StateError('No fallback rectangle definition registered')
          : (fallback as dynamic).createDefaultData() as ElementData;
    } else if (payload.isEmpty) {
      data = (definition as dynamic).createDefaultData() as ElementData;
    } else {
      try {
        final decoded = jsonDecode(utf8.decode(payload));
        final map = _asJsonMap(decoded);
        data = (definition as dynamic).fromJson(map) as ElementData;
      } catch (_) {
        data = (definition as dynamic).createDefaultData() as ElementData;
      }
    }

    return ElementState(
      id: id,
      rect: rect,
      rotation: rotation,
      opacity: opacity,
      zIndex: zIndex,
      data: data,
    );
  }
}

final class _DecodedEvent {
  int kind = 0;
  String? message;
}

Map<String, dynamic> _asJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

final class _ProtoWriter {
  _ProtoWriter() : _builder = BytesBuilder(copy: false);

  final BytesBuilder _builder;

  Uint8List takeBytes() => _builder.takeBytes();

  void writeEnum(int fieldNumber, int value) => writeUInt64(fieldNumber, value);

  void writeBool(int fieldNumber, bool value) {
    if (!value) {
      return;
    }
    writeUInt64(fieldNumber, 1);
  }

  void writeUInt64(int fieldNumber, int value) {
    writeTag(fieldNumber, _RustProtoCodec._wireVarint);
    writeRawVarint(value);
  }

  void writeDouble(int fieldNumber, double value) {
    writeTag(fieldNumber, _RustProtoCodec._wireFixed64);
    final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
    _builder.add(bytes.buffer.asUint8List());
  }

  void writeString(int fieldNumber, String value) {
    if (value.isEmpty) {
      return;
    }
    writeBytes(fieldNumber, Uint8List.fromList(utf8.encode(value)));
  }

  void writeBytes(int fieldNumber, Uint8List value) {
    writeTag(fieldNumber, _RustProtoCodec._wireLengthDelimited);
    writeRawVarint(value.length);
    _builder.add(value);
  }

  void writeMessage(int fieldNumber, Uint8List message) {
    writeBytes(fieldNumber, message);
  }

  void writeTag(int fieldNumber, int wireType) {
    writeRawVarint((fieldNumber << 3) | wireType);
  }

  void writeRawVarint(int value) {
    var v = value;
    while (v > 0x7f) {
      _builder.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _builder.addByte(v & 0x7f);
  }
}

final class _ProtoReader {
  _ProtoReader(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  int _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  int readTag() {
    if (isDone) {
      return 0;
    }
    return readVarint();
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (_offset < _bytes.length) {
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('Varint too long');
      }
    }
    throw const FormatException('Unexpected EOF while reading varint');
  }

  double readDouble() {
    if (_offset + 8 > _bytes.length) {
      throw const FormatException('Unexpected EOF while reading double');
    }
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getFloat64(0, Endian.little);
    _offset += 8;
    return value;
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (_offset + length > _bytes.length) {
      throw const FormatException('Unexpected EOF while reading bytes');
    }
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  String readString() => utf8.decode(readBytes());

  void skipField(int wireType) {
    switch (wireType) {
      case _RustProtoCodec._wireVarint:
        readVarint();
      case _RustProtoCodec._wireFixed64:
        _offset += 8;
      case _RustProtoCodec._wireLengthDelimited:
        final length = readVarint();
        _offset += length;
      default:
        throw FormatException('Unsupported wire type $wireType');
    }
    if (_offset > _bytes.length) {
      throw const FormatException('Unexpected EOF while skipping field');
    }
  }
}
