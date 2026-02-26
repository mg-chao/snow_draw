import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;

import '../../src/proto/engine.pb.dart' as proto;
import '../../src/proto/engine_v2.pb.dart' as proto_v2;
import '../../rust_canvas_engine.dart';
import '../actions/config_actions.dart';
import '../actions/draw_actions.dart';
import '../config/config_manager.dart';
import '../config/draw_config.dart';
import '../core/callbacks.dart';
import '../core/draw_context.dart';
import '../edit/core/edit_operation_params.dart';
import '../elements/core/element_data.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/arrow/arrow_points.dart';
import '../elements/types/text/text_data.dart';
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
import '../render/tasks/frame_render_plan.dart';
import '../render/tasks/render_tasks.dart';
import '../services/text/text_metrics_service.dart';
import '../types/draw_color.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/edit_context.dart';
import '../types/edit_operation_id.dart';
import '../types/edit_transform.dart';
import '../types/element_geometry.dart';
import '../types/snap_guides.dart';
import '../utils/selection_calculator.dart';
import 'draw_store_interface.dart';
import 'listener_registry.dart';
import 'selector.dart';
import 'state_change_detector.dart';

/// Rust-backed draw store adapter.
///
/// This store drives state transitions through the Rust engine C ABI.
class RustDrawStore implements DrawStore {
  static const _requiredCapabilitiesMask =
      _RustProtoCodec.capabilityEventStream |
      _RustProtoCodec.capabilityFramePlan |
      _RustProtoCodec.capabilityDispatchBatch |
      _RustProtoCodec.capabilityInputPipeline |
      _RustProtoCodec.capabilityTextMetricsHost;

  RustDrawStore({
    required DrawContext context,
    DrawState? initialState,
    EventBus? eventBus,
    RustCanvasEngine? engine,
    Uint8List? engineConfigBytes,
  }) : _ownsEventBus = eventBus == null && context.eventBus == null,
       _eventBus = eventBus ?? context.eventBus ?? EventBus(),
       _engine = engine ?? _createV2Engine(engineConfigBytes) {
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

    _state = DrawState.initial();
    _canUndo = false;
    _canRedo = false;
    _drainNativeOutputs(applySnapshot: true);
    if (!_didValidateInitAck) {
      throw StateError(
        'RustDrawStore initialization failed: missing EngineInitAck from V2 runtime.',
      );
    }
    _pushRuntimeConfigEvent();
  }

  @override
  late final DrawContext context;

  late DrawState _state;
  late final ConfigManager _configManager;
  late final ListenerRegistry _listenerRegistry;
  final EventBus _eventBus;
  final bool _ownsEventBus;
  final RustCanvasEngine _engine;
  var _nextInputSequence = 1;

  var _isDisposed = false;
  var _canUndo = false;
  var _canRedo = false;
  var _didValidateInitAck = false;
  var _latestFramePlan = FrameRenderPlan.empty;
  DrawPoint? _creatingStartPositionHint;
  DrawPoint? _dragPendingPointerDownHint;
  PendingIntent? _dragPendingIntentHint;
  DrawPoint? _boxSelectStartHint;
  DrawPoint? _boxSelectCurrentHint;
  DrawPoint? _textEditStartHint;
  var _pendingTextEditIsNew = false;
  String? _activeTextEditElementId;
  var _activeTextEditIsNew = false;
  DrawPoint? _editStartHint;
  EditOperationId? _editOperationHint;
  var _editSessionSequence = 0;

  @override
  bool get canUndo => _canUndo;

  @override
  bool get canRedo => _canRedo;

  @override
  DrawState get state => _state;

  FrameRenderPlan get latestFramePlan => _latestFramePlan;

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
      _pushRuntimeConfigEvent();
      return;
    }
    if (action is UpdateSelectionConfig) {
      _configManager.update(
        _configManager.current.copyWith(selection: action.selection),
      );
      _pushRuntimeConfigEvent();
      return;
    }
    if (action is UpdateCanvasConfig) {
      _configManager.update(
        _configManager.current.copyWith(canvas: action.canvas),
      );
      _pushRuntimeConfigEvent();
      return;
    }

    _updateInteractionHints(action);

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

    final input = _RustProtoCodec.encodeInputCommand(
      command,
      sequence: _nextSequence(),
    );
    _engine.processInputV2(input);
    _drainNativeOutputs(applySnapshot: true);
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

  static RustCanvasEngine _createV2Engine(Uint8List? engineConfigBytes) {
    if (engineConfigBytes != null && engineConfigBytes.isNotEmpty) {
      throw UnsupportedError(
        'RustDrawStore V2 does not accept legacy engineConfigBytes payloads.',
      );
    }
    return RustCanvasEngine.createV2(
      initBytes: _RustProtoCodec.encodeInitRequest(
        requestedCapabilitiesMask: _requiredCapabilitiesMask,
      ),
    );
  }

  int _nextSequence() => _nextInputSequence++;

  void _pushRuntimeConfigEvent() {
    final input = _RustProtoCodec.encodeInputConfigEvent(
      _RustProtoCodec.encodeRuntimeConfigPayload(_configManager.current),
      sequence: _nextSequence(),
    );
    _engine.processInputV2(input);
    _drainNativeOutputs(applySnapshot: false);
  }

  void _refreshSnapshotAndNotify(DrawState next) {
    final previous = _state;
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

  void _drainNativeOutputs({required bool applySnapshot}) {
    _DecodedSnapshot? lastSnapshot;

    while (true) {
      final bytes = _engine.pollOutputV2();
      if (bytes == null) {
        break;
      }
      final output = _RustProtoCodec.decodeOutput(bytes);
      if (output == null) {
        continue;
      }
      switch (output.whichPayload()) {
        case proto_v2.EngineOutput_Payload.snapshot:
          lastSnapshot = _RustProtoCodec.decodeSnapshotV2(output.snapshot);
          break;
        case proto_v2.EngineOutput_Payload.event:
          _handleEngineEvent(output.event);
          break;
        case proto_v2.EngineOutput_Payload.initAck:
          _validateInitAck(output.initAck);
          break;
        case proto_v2.EngineOutput_Payload.stateDelta:
          // State is reconstructed from snapshots. Keep deltas for protocol
          // parity and future incremental application.
          break;
        case proto_v2.EngineOutput_Payload.framePlan:
          final stateForPlan = lastSnapshot == null
              ? _state
              : _buildStateFromSnapshot(
                  lastSnapshot,
                  previousState: _state,
                  updateHints: false,
                );
          _latestFramePlan = _RustProtoCodec.decodeFramePlanV2(
            output.framePlan,
            state: stateForPlan,
            config: _configManager.current,
          );
          break;
        case proto_v2.EngineOutput_Payload.hostRequest:
          _handleHostRequest(output.hostRequest);
          break;
        case proto_v2.EngineOutput_Payload.notSet:
          break;
      }
    }

    if (applySnapshot && lastSnapshot != null) {
      final nextState = _buildStateFromSnapshot(
        lastSnapshot,
        previousState: _state,
        updateHints: true,
      );
      _refreshSnapshotAndNotify(nextState);
    }
  }

  void _updateInteractionHints(DrawAction action) {
    switch (action) {
      case CreateElement(:final position):
        _creatingStartPositionHint = position;
        break;
      case FinishCreateElement() || CancelCreateElement():
        _creatingStartPositionHint = null;
        break;
      case SetDragPending(:final pointerDownPosition, :final intent):
        _dragPendingPointerDownHint = pointerDownPosition;
        _dragPendingIntentHint = intent;
        break;
      case ClearDragPending():
        _dragPendingPointerDownHint = null;
        _dragPendingIntentHint = null;
        break;
      case StartBoxSelect(:final startPosition):
        _boxSelectStartHint = startPosition;
        _boxSelectCurrentHint = startPosition;
        break;
      case UpdateBoxSelect(:final currentPosition):
        _boxSelectCurrentHint = currentPosition;
        break;
      case FinishBoxSelect() || CancelBoxSelect():
        _boxSelectStartHint = null;
        _boxSelectCurrentHint = null;
        break;
      case StartTextEdit(:final position, :final elementId):
        _textEditStartHint = position;
        _pendingTextEditIsNew = elementId == null || elementId.isEmpty;
        break;
      case FinishTextEdit() || CancelTextEdit():
        _pendingTextEditIsNew = false;
        _activeTextEditElementId = null;
        _activeTextEditIsNew = false;
        break;
      case StartEdit(:final position, :final operationId):
        _editStartHint = position;
        _editOperationHint = operationId;
        break;
      case FinishEdit() || CancelEdit():
        _editStartHint = null;
        _editOperationHint = null;
        break;
      case Undo() || Redo() || ClearHistory():
        _creatingStartPositionHint = null;
        _boxSelectStartHint = null;
        _boxSelectCurrentHint = null;
        _dragPendingPointerDownHint = null;
        _dragPendingIntentHint = null;
        _pendingTextEditIsNew = false;
        _activeTextEditElementId = null;
        _activeTextEditIsNew = false;
        _editStartHint = null;
        _editOperationHint = null;
        break;
      default:
        break;
    }
  }

  DrawState _buildStateFromSnapshot(
    _DecodedSnapshot snapshot, {
    required DrawState previousState,
    required bool updateHints,
  }) {
    final decoded = snapshot.toDrawState(context);
    final interaction = _resolveInteractionFromSnapshot(
      snapshot: snapshot,
      decodedState: decoded,
      previousState: previousState,
      updateHints: updateHints,
    );
    return decoded.copyWith(
      application: decoded.application.copyWith(interaction: interaction),
    );
  }

  InteractionState _resolveInteractionFromSnapshot({
    required _DecodedSnapshot snapshot,
    required DrawState decodedState,
    required DrawState previousState,
    required bool updateHints,
  }) {
    final previousInteraction = previousState.application.interaction;
    final mode =
        proto_v2.InteractionMode.valueOf(snapshot.interactionMode) ??
        proto_v2.InteractionMode.INTERACTION_MODE_IDLE;

    switch (mode) {
      case proto_v2.InteractionMode.INTERACTION_MODE_CREATING:
        return _resolveCreatingInteraction(
          decodedState: decodedState,
          previousInteraction: previousInteraction,
          updateHints: updateHints,
        );
      case proto_v2.InteractionMode.INTERACTION_MODE_EDITING:
        return _resolveEditingInteraction(
          decodedState: decodedState,
          previousInteraction: previousInteraction,
        );
      case proto_v2.InteractionMode.INTERACTION_MODE_TEXT_EDITING:
        return _resolveTextEditingInteraction(
          decodedState: decodedState,
          previousInteraction: previousInteraction,
          updateHints: updateHints,
        );
      case proto_v2.InteractionMode.INTERACTION_MODE_BOX_SELECTING:
        return _resolveBoxSelectingInteraction(
          previousInteraction: previousInteraction,
        );
      case proto_v2.InteractionMode.INTERACTION_MODE_DRAG_PENDING:
        return _resolveDragPendingInteraction(
          previousInteraction: previousInteraction,
        );
      case proto_v2.InteractionMode.INTERACTION_MODE_IDLE:
        if (updateHints && previousInteraction is TextEditingState) {
          _activeTextEditElementId = null;
          _activeTextEditIsNew = false;
          _pendingTextEditIsNew = false;
        }
        return const IdleState();
    }

    return const IdleState();
  }

  InteractionState _resolveCreatingInteraction({
    required DrawState decodedState,
    required InteractionState previousInteraction,
    required bool updateHints,
  }) {
    final selectedIds = decodedState.domain.selection.selectedIds;
    final selectedId = selectedIds.isEmpty ? null : selectedIds.first;
    if (selectedId == null) {
      return previousInteraction is CreatingState
          ? previousInteraction
          : const IdleState();
    }
    final element = decodedState.domain.document.getElementById(selectedId);
    if (element == null) {
      return previousInteraction is CreatingState
          ? previousInteraction
          : const IdleState();
    }

    final startPosition = switch (previousInteraction) {
      CreatingState(:final startPosition) => startPosition,
      _ => _creatingStartPositionHint ?? _pointFromRectTopLeft(element.rect),
    };
    if (updateHints) {
      _creatingStartPositionHint ??= startPosition;
    }

    final creationMode = _resolveCreationMode(
      element: element,
      previousInteraction: previousInteraction,
    );
    final snapGuides = switch (previousInteraction) {
      CreatingState(:final snapGuides) => snapGuides,
      _ => const <SnapGuide>[],
    };

    return CreatingState(
      element: element,
      startPosition: startPosition,
      currentRect: element.rect,
      snapGuides: snapGuides,
      creationMode: creationMode,
    );
  }

  CreationMode _resolveCreationMode({
    required ElementState element,
    required InteractionState previousInteraction,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      return const RectCreationMode();
    }

    final fixedPoints = _toArrowWorldPoints(data.points, element.rect);
    final previousPointMode = switch (previousInteraction) {
      CreatingState(:final creationMode)
          when creationMode is PointCreationMode =>
        creationMode as PointCreationMode,
      _ => null,
    };
    return PointCreationMode(
      fixedPoints: List<DrawPoint>.unmodifiable(fixedPoints),
      currentPoint:
          previousPointMode?.currentPoint ??
          (fixedPoints.isEmpty ? null : fixedPoints.last),
      sessionData: previousPointMode?.sessionData,
    );
  }

  List<DrawPoint> _toArrowWorldPoints(
    List<DrawPoint> normalizedPoints,
    DrawRect rect,
  ) {
    final width = rect.width;
    final height = rect.height;
    final worldPoints = <DrawPoint>[];
    for (final point in normalizedPoints) {
      final isNormalized =
          point.x >= 0.0 && point.x <= 1.0 && point.y >= 0.0 && point.y <= 1.0;
      worldPoints.add(
        isNormalized
            ? DrawPoint(
                x: rect.minX + point.x * width,
                y: rect.minY + point.y * height,
              )
            : DrawPoint(x: point.x, y: point.y),
      );
    }
    return worldPoints;
  }

  InteractionState _resolveTextEditingInteraction({
    required DrawState decodedState,
    required InteractionState previousInteraction,
    required bool updateHints,
  }) {
    final previous = previousInteraction is TextEditingState
        ? previousInteraction
        : null;
    final selectedIds = decodedState.domain.selection.selectedIds;
    final selectedId = selectedIds.isEmpty
        ? previous?.elementId
        : selectedIds.first;
    if (selectedId == null) {
      return previous ?? const IdleState();
    }

    final element = decodedState.domain.document.getElementById(selectedId);
    if (element == null || element.data is! TextData) {
      return previous ?? const IdleState();
    }
    final textData = element.data as TextData;
    final isNew = previous != null && previous.elementId == selectedId
        ? previous.isNew
        : (_activeTextEditElementId == selectedId
              ? _activeTextEditIsNew
              : _pendingTextEditIsNew);

    if (updateHints) {
      _activeTextEditElementId = selectedId;
      _activeTextEditIsNew = isNew;
      _pendingTextEditIsNew = false;
    }

    return TextEditingState(
      elementId: selectedId,
      draftData: textData,
      rect: element.rect,
      isNew: isNew,
      opacity: element.opacity,
      rotation: element.rotation,
      initialCursorPosition:
          previous?.initialCursorPosition ?? _textEditStartHint,
    );
  }

  InteractionState _resolveEditingInteraction({
    required DrawState decodedState,
    required InteractionState previousInteraction,
  }) {
    if (previousInteraction is EditingState) {
      return previousInteraction;
    }

    final selectedElements = <ElementState>[
      for (final id in decodedState.domain.selection.selectedIds)
        if (decodedState.domain.document.getElementById(id) case final element?)
          element,
    ];
    final startPosition = _editStartHint ?? DrawPoint.zero;
    final startBounds =
        SelectionCalculator.computeSelectionBoundsForElements(
          selectedElements,
        ) ??
        DrawRect.fromPoint(startPosition);
    final operationId = _editOperationHint ?? EditOperationIds.move;

    return EditingState(
      operationId: operationId,
      sessionId: 'rust_edit_${_editSessionSequence++}',
      context: MoveEditContext(
        startPosition: startPosition,
        startBounds: startBounds,
        selectedIdsAtStart: decodedState.domain.selection.selectedIds,
        selectionVersion: decodedState.domain.selection.selectionVersion,
        elementsVersion: decodedState.domain.document.elementsVersion,
        elementSnapshots: const <String, ElementMoveSnapshot>{},
      ),
      currentTransform: MoveTransform.zero,
    );
  }

  InteractionState _resolveBoxSelectingInteraction({
    required InteractionState previousInteraction,
  }) {
    final previous = previousInteraction is BoxSelectingState
        ? previousInteraction
        : null;
    final start =
        _boxSelectStartHint ??
        previous?.startPosition ??
        _boxSelectCurrentHint ??
        DrawPoint.zero;
    final current = _boxSelectCurrentHint ?? previous?.currentPosition ?? start;
    return BoxSelectingState(startPosition: start, currentPosition: current);
  }

  InteractionState _resolveDragPendingInteraction({
    required InteractionState previousInteraction,
  }) {
    if (previousInteraction is DragPendingState) {
      return previousInteraction;
    }
    return DragPendingState(
      pointerDownPosition: _dragPendingPointerDownHint ?? DrawPoint.zero,
      intent: _dragPendingIntentHint ?? const PendingMoveIntent(),
    );
  }

  DrawPoint _pointFromRectTopLeft(DrawRect rect) =>
      DrawPoint(x: rect.minX, y: rect.minY);

  void _validateInitAck(proto_v2.EngineInitAck ack) {
    if (_didValidateInitAck) {
      return;
    }

    final granted = ack.grantedCapabilitiesMask.toInt();
    final hasRequiredCapabilities =
        (granted & _requiredCapabilitiesMask) == _requiredCapabilitiesMask;
    final isAbiValid = ack.abiVersion == _RustProtoCodec.runtimeAbiVersion;
    final isSchemaValid =
        ack.schemaVersion == _RustProtoCodec.runtimeSchemaVersion;

    if (!isAbiValid || !isSchemaValid || !hasRequiredCapabilities) {
      throw StateError(
        'RustDrawStore init-ack validation failed: '
        'abi=${ack.abiVersion}, schema=${ack.schemaVersion}, '
        'grantedCapabilities=0x${granted.toRadixString(16)}',
      );
    }
    _didValidateInitAck = true;
  }

  void _handleHostRequest(proto_v2.HostRequest request) {
    switch (request.whichPayload()) {
      case proto_v2.HostRequest_Payload.textMetricsRequest:
        _respondToTextMetricsRequest(request);
        break;
      case proto_v2.HostRequest_Payload.pointerHostRequest:
      case proto_v2.HostRequest_Payload.keyboardHostRequest:
      case proto_v2.HostRequest_Payload.toolHostRequest:
      case proto_v2.HostRequest_Payload.notSet:
        // Reserved for non-text host services in later parity passes.
        break;
    }
  }

  void _respondToTextMetricsRequest(proto_v2.HostRequest request) {
    final payload = request.textMetricsRequest;
    try {
      final metrics = context.textMetricsService.measure(
        TextLayoutRequest(
          data: TextData(
            text: payload.text,
            fontSize: payload.fontSize > 0 ? payload.fontSize : 21,
            fontFamily: payload.fontFamily.trim().isEmpty
                ? null
                : payload.fontFamily.trim(),
          ),
          maxWidth: payload.maxWidth > 0 ? payload.maxWidth : 4096,
          minWidth: payload.minWidth > 0 ? payload.minWidth : null,
          localeTag: payload.localeTag.trim().isEmpty
              ? null
              : payload.localeTag,
          isResizing: payload.isResizing,
        ),
      );

      final response = proto_v2.TextMetricsResponse(
        requestId: request.requestId,
        ok: true,
        metrics: proto_v2.TextMetricsResult(
          width: metrics.width,
          height: metrics.height,
          lineHeight: metrics.lineHeight,
          lines: metrics.lines
              .map(
                (line) => proto_v2.TextMetricsLine(
                  width: line.width,
                  height: line.height,
                ),
              )
              .toList(),
        ),
      );
      _engine.processInputV2(
        _RustProtoCodec.encodeInputTextMetricsResponse(
          response,
          sequence: _nextSequence(),
        ),
      );
    } on Object catch (error) {
      final response = proto_v2.TextMetricsResponse(
        requestId: request.requestId,
        ok: false,
        error: proto_v2.EngineError(
          code: 5001,
          message: 'Text metrics host service failed',
          details: error.toString(),
        ),
      );
      _engine.processInputV2(
        _RustProtoCodec.encodeInputTextMetricsResponse(
          response,
          sequence: _nextSequence(),
        ),
      );
    }
  }

  void _handleEngineEvent(proto_v2.EngineEvent event) {
    if (event.kind != proto_v2.EngineEventKind.ENGINE_EVENT_KIND_ERROR) {
      return;
    }

    final message = switch (event.whichPayload()) {
      proto_v2.EngineEvent_Payload.error => event.error.message,
      proto_v2.EngineEvent_Payload.message => event.message,
      proto_v2.EngineEvent_Payload.blob => 'Rust engine error',
      proto_v2.EngineEvent_Payload.notSet => 'Rust engine error',
    };

    _eventBus.emit(ErrorEvent(message: message, error: message));
  }
}

final class _RustProtoCodec {
  const _RustProtoCodec._();

  static const runtimeAbiVersion = 2;
  static const runtimeSchemaVersion = 2;
  static const capabilityEventStream = 1 << 0;
  static const capabilityFramePlan = 1 << 1;
  static const capabilityDispatchBatch = 1 << 2;
  static const capabilityInputPipeline = 1 << 3;
  static const capabilityTextMetricsHost = 1 << 4;
  static const _isProductMode = bool.fromEnvironment('dart.vm.product');
  static const _allowRawPayloadInRelease = bool.fromEnvironment(
    'snow_draw_engine.allow_raw_payload_v2',
  );

  static int lastDecodedHistoryUndo = 0;
  static int lastDecodedHistoryRedo = 0;

  static Uint8List? encodeAction(
    DrawAction action, {
    required DrawContext context,
  }) {
    final command = switch (action) {
      SelectElement(:final elementId, :final addToSelection, :final position) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_SELECT_ELEMENT,
          selectElement: proto.SelectElementCommand(
            elementId: elementId,
            addToSelection: addToSelection,
            position: _encodePoint(position),
          ),
        ),
      ClearSelection() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CLEAR_SELECTION,
      ),
      SelectAll() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_SELECT_ALL,
      ),
      CreateElement(
        :final typeId,
        :final position,
        :final initialData,
        :final maintainAspectRatio,
        :final createFromCenter,
        :final snapOverride,
      ) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CREATE_ELEMENT,
          createElement: proto.CreateElementCommand(
            elementType: _elementTypeFromTypeValue(typeId.value),
            elementId: context.idGenerator(),
            position: _encodePoint(position),
            initialPayload: initialData == null
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
        proto.EngineCommand(
          kind: proto
              .EngineCommandKind
              .ENGINE_COMMAND_KIND_UPDATE_CREATING_ELEMENT,
          updateCreatingElement: proto.UpdateCreatingElementCommand(
            positions: positions.map(_encodePoint).toList(),
            maintainAspectRatio: maintainAspectRatio,
            createFromCenter: createFromCenter,
            snapOverride: snapOverride,
          ),
        ),
      AddArrowPoint(:final position, :final snapOverride) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_ADD_ARROW_POINT,
          addArrowPoint: proto.AddArrowPointCommand(
            position: _encodePoint(position),
            snapOverride: snapOverride,
          ),
        ),
      FinishCreateElement() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_FINISH_CREATE_ELEMENT,
      ),
      CancelCreateElement() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CANCEL_CREATE_ELEMENT,
      ),
      DeleteElements(:final elementIds) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_DELETE_ELEMENTS,
        deleteElements: proto.DeleteElementsCommand(elementIds: elementIds),
      ),
      DuplicateElements(:final elementIds, :final offsetX, :final offsetY) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_DUPLICATE_ELEMENTS,
          duplicateElements: proto.DuplicateElementsCommand(
            elementIds: elementIds,
            offsetX: offsetX,
            offsetY: offsetY,
          ),
        ),
      ChangeElementZIndex(:final elementId, :final operation) =>
        proto.EngineCommand(
          kind: proto
              .EngineCommandKind
              .ENGINE_COMMAND_KIND_CHANGE_ELEMENT_Z_INDEX,
          changeElementZIndex: proto.ChangeElementZIndexCommand(
            elementId: elementId,
            operation: _zIndexOperationValue(operation),
          ),
        ),
      ChangeElementsZIndex(:final elementIds, :final operation) =>
        proto.EngineCommand(
          kind: proto
              .EngineCommandKind
              .ENGINE_COMMAND_KIND_CHANGE_ELEMENTS_Z_INDEX,
          changeElementsZIndex: proto.ChangeElementsZIndexCommand(
            elementIds: elementIds,
            operation: _zIndexOperationValue(operation),
          ),
        ),
      UpdateElementsStyle() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_UPDATE_ELEMENTS_STYLE,
        updateElementsStyle: proto.UpdateElementsStyleCommand(
          elementIds: action.elementIds,
          stylePayload: _encodeUpdateElementsStyle(action),
        ),
      ),
      UpdateGlobalElements(:final highlightMask, :final watermark) =>
        proto.EngineCommand(
          kind: proto
              .EngineCommandKind
              .ENGINE_COMMAND_KIND_UPDATE_GLOBAL_ELEMENTS,
          updateGlobalElements: proto.UpdateGlobalElementsCommand(
            payload: _encodeUpdateGlobalElements(
              highlightMask: highlightMask,
              watermark: watermark,
            ),
          ),
        ),
      CreateSerialNumberTextElements(:final elementIds) => proto.EngineCommand(
        kind: proto
            .EngineCommandKind
            .ENGINE_COMMAND_KIND_CREATE_SERIAL_NUMBER_TEXT_ELEMENTS,
        createSerialNumberTextElements:
            proto.CreateSerialNumberTextElementsCommand(elementIds: elementIds),
      ),
      StartTextEdit(:final elementId, :final position) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_START_TEXT_EDIT,
        startTextEdit: proto.StartTextEditCommand(
          elementId: elementId ?? '',
          position: _encodePoint(position),
        ),
      ),
      UpdateTextEdit(:final text, :final rect) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_UPDATE_TEXT_EDIT,
        updateTextEdit: proto.UpdateTextEditCommand(
          text: text,
          rect: rect == null ? null : _encodeRect(rect),
        ),
      ),
      RefreshAutoResizeTextLayoutsAfterFontLoad() => proto.EngineCommand(
        kind: proto
            .EngineCommandKind
            .ENGINE_COMMAND_KIND_REFRESH_AUTO_RESIZE_TEXT_LAYOUTS_AFTER_FONT_LOAD,
      ),
      FinishTextEdit(:final elementId, :final text, :final isNew) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_FINISH_TEXT_EDIT,
          finishTextEdit: proto.FinishTextEditCommand(
            elementId: elementId,
            text: text,
            isNew: isNew,
          ),
        ),
      CancelTextEdit() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CANCEL_TEXT_EDIT,
      ),
      StartEdit(:final operationId, :final position, :final params) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_START_EDIT,
          startEdit: proto.StartEditCommand(
            operationId: operationId,
            position: _encodePoint(position),
            params: Uint8List.fromList(
              utf8.encode(jsonEncode(_editParamsToJson(params))),
            ),
          ),
        ),
      UpdateEdit(:final currentPosition, :final modifiers) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_UPDATE_EDIT,
          updateEdit: proto.UpdateEditCommand(
            currentPosition: _encodePoint(currentPosition),
            modifiers: Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'maintainAspectRatio': modifiers.maintainAspectRatio,
                  'fromCenter': modifiers.fromCenter,
                  'discreteAngle': modifiers.discreteAngle,
                  'snapOverride': modifiers.snapOverride,
                }),
              ),
            ),
          ),
        ),
      FinishEdit() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_FINISH_EDIT,
      ),
      CancelEdit() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CANCEL_EDIT,
      ),
      SetDragPending(:final pointerDownPosition, :final intent) =>
        proto.EngineCommand(
          kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_SET_DRAG_PENDING,
          setDragPending: proto.SetDragPendingCommand(
            pointerDownPosition: _encodePoint(pointerDownPosition),
            intent: intent.toString(),
          ),
        ),
      ClearDragPending() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CLEAR_DRAG_PENDING,
      ),
      StartBoxSelect(:final startPosition) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_START_BOX_SELECT,
        startBoxSelect: proto.StartBoxSelectCommand(
          startPosition: _encodePoint(startPosition),
        ),
      ),
      UpdateBoxSelect(:final currentPosition) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_UPDATE_BOX_SELECT,
        updateBoxSelect: proto.UpdateBoxSelectCommand(
          currentPosition: _encodePoint(currentPosition),
        ),
      ),
      FinishBoxSelect() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_FINISH_BOX_SELECT,
      ),
      CancelBoxSelect() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CANCEL_BOX_SELECT,
      ),
      MoveCamera(:final dx, :final dy) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_MOVE_CAMERA,
        moveCamera: proto.MoveCameraCommand(dx: dx, dy: dy),
      ),
      ZoomCamera(:final scale, :final center) => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_ZOOM_CAMERA,
        zoomCamera: proto.ZoomCameraCommand(
          scale: scale,
          center: center == null ? null : _encodePoint(center),
        ),
      ),
      Undo() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_UNDO,
      ),
      Redo() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_REDO,
      ),
      ClearHistory() => proto.EngineCommand(
        kind: proto.EngineCommandKind.ENGINE_COMMAND_KIND_CLEAR_HISTORY,
      ),
      _ => null,
    };

    return command?.writeToBuffer();
  }

  static Uint8List encodeInitRequest({
    int requestedAbiVersion = runtimeAbiVersion,
    int schemaVersion = runtimeSchemaVersion,
    String localeTag = 'en-US',
    double scaleFactor = 1.0,
    int requestedCapabilitiesMask =
        capabilityEventStream |
        capabilityFramePlan |
        capabilityInputPipeline |
        capabilityTextMetricsHost,
    int deterministicSeed = 0,
  }) => Uint8List.fromList(
    proto_v2.EngineInitRequest(
      requestedAbiVersion: requestedAbiVersion,
      schemaVersion: schemaVersion,
      localeTag: localeTag,
      scaleFactor: scaleFactor,
      requestedCapabilitiesMask: $fixnum.Int64(requestedCapabilitiesMask),
      deterministicSeed: $fixnum.Int64(deterministicSeed),
    ).writeToBuffer(),
  );

  static Uint8List encodeInputCommand(
    Uint8List commandBytes, {
    required int sequence,
  }) => Uint8List.fromList(
    proto_v2.EngineInput(
      sequence: $fixnum.Int64(sequence),
      commandEvent: proto_v2.CommandEvent(commandBytes: commandBytes),
    ).writeToBuffer(),
  );

  static Uint8List encodeInputConfigEvent(
    Uint8List configPayload, {
    required int sequence,
  }) => Uint8List.fromList(
    proto_v2.EngineInput(
      sequence: $fixnum.Int64(sequence),
      configEvent: proto_v2.ConfigEvent(
        localeTag: '',
        scaleFactor: 0,
        configPayload: configPayload,
      ),
    ).writeToBuffer(),
  );

  static Uint8List encodeInputTextMetricsResponse(
    proto_v2.TextMetricsResponse response, {
    required int sequence,
  }) => Uint8List.fromList(
    proto_v2.EngineInput(
      sequence: $fixnum.Int64(sequence),
      textMetricsResponse: response,
    ).writeToBuffer(),
  );

  static proto_v2.EngineOutput? decodeOutput(Uint8List bytes) {
    try {
      return proto_v2.EngineOutput.fromBuffer(bytes);
    } on Object {
      return null;
    }
  }

  static _DecodedSnapshot decodeSnapshotV2(proto_v2.EngineSnapshot message) {
    final snapshot = _DecodedSnapshot()
      ..documentVersion = message.documentVersion.toInt()
      ..selectionVersion = message.selectionVersion.toInt()
      ..interactionMode = message.interactionMode.value;

    if (message.hasCamera()) {
      snapshot.camera = _decodeCameraV2(message.camera);
    }

    snapshot.elements.addAll(message.elements.map(_decodeElementV2));
    snapshot.selectedIds.addAll(message.selectedIds);
    snapshot.historyUndoLen = message.historyUndoLen.toInt();
    snapshot.historyRedoLen = message.historyRedoLen.toInt();
    snapshot.globalPayload = Uint8List.fromList(message.globalElementsPayload);

    lastDecodedHistoryUndo = snapshot.historyUndoLen;
    lastDecodedHistoryRedo = snapshot.historyRedoLen;
    return snapshot;
  }

  static FrameRenderPlan decodeFramePlanV2(
    proto_v2.FrameRenderPlan message, {
    required DrawState state,
    required DrawConfig config,
  }) {
    final tasks = <FrameRenderTask>[];
    final localeTag = message.localeTag.trim().isEmpty
        ? null
        : message.localeTag;
    final elementById = <String, ElementState>{
      for (final element in state.domain.document.elements) element.id: element,
    };
    final selectedElements = SelectionCalculator.getSelectedElements(state);
    final selectionBounds =
        SelectionCalculator.computeSelectionBoundsForElements(selectedElements);

    for (final task in message.tasks) {
      switch (task.kind) {
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_BACKGROUND:
          tasks.add(BackgroundRenderTask(color: config.canvas.backgroundColor));
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_GRID:
          final grid = config.grid;
          tasks.add(
            GridRenderTask(
              enabled: grid.enabled,
              size: grid.size,
              lineWidth: grid.lineWidth,
              lineColor: grid.lineColor,
              lineOpacity: grid.lineOpacity,
              majorLineEvery: grid.majorLineEvery,
              majorLineOpacity: grid.majorLineOpacity,
              minScreenSpacing: grid.minScreenSpacing,
              minRenderSpacing: grid.minRenderSpacing,
            ),
          );
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_SELECTION_OUTLINE:
          if (selectionBounds != null) {
            tasks.add(
              SelectionOutlineRenderTask(
                bounds: selectionBounds,
                config: config.selection,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_SELECTION_CONTROLS:
          if (selectionBounds != null) {
            tasks.add(
              SelectionControlsRenderTask(
                bounds: selectionBounds,
                config: config.selection,
                cornerHandleOffset: config.selection.rotateHandleOffset,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_BOX_SELECTION:
          final payload = _decodeFrameTaskPayload(task);
          final bounds =
              _decodeRectMap(payload?['bounds']) ??
              switch (state.application.interaction) {
                BoxSelectingState(:final bounds) => bounds,
                _ => null,
              };
          if (bounds != null) {
            tasks.add(
              BoxSelectionRenderTask(
                bounds: bounds,
                config: config.boxSelection,
                selectionConfig: config.selection,
                previewElements: selectedElements,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_ARROW_POINT_OVERLAY:
          final payload = _decodeFrameTaskPayload(task);
          final handles = _decodeArrowPointHandles(payload?['handles']);
          if (handles.isNotEmpty) {
            tasks.add(
              ArrowPointOverlayRenderTask(
                handles: List<ArrowPointHandle>.unmodifiable(handles),
                selectionConfig: config.selection,
                activeHandle: _decodeArrowPointHandle(payload?['activeHandle']),
                hoveredHandle: _decodeArrowPointHandle(
                  payload?['hoveredHandle'],
                ),
                deleteIndicatorVisible:
                    payload?['deleteIndicatorVisible'] == true,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT:
          final payload = _decodeFrameTaskPayload(task);
          final elementIds = _decodeStringList(payload?['elementIds']);
          if (elementIds.isNotEmpty) {
            tasks.add(
              ArrowBindingHighlightRenderTask(
                elementIds: List<String>.unmodifiable(elementIds),
                strokeColor: config.selection.render.strokeColor,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_HOVER_OUTLINE:
          final payload = _decodeFrameTaskPayload(task);
          final hoverId = payload?['elementId'];
          if (hoverId is String && hoverId.trim().isNotEmpty) {
            final element = elementById[hoverId];
            if (element != null) {
              tasks.add(
                HoverOutlineRenderTask(
                  element: element,
                  config: config.selection,
                  useTextUnderlineStyle:
                      payload?['useTextUnderlineStyle'] == true ||
                      element.data is TextData,
                ),
              );
            }
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_SNAP_GUIDES:
          final payload = _decodeFrameTaskPayload(task);
          final guides = _decodeSnapGuides(payload?['guides']);
          if (guides.isNotEmpty) {
            tasks.add(
              SnapGuidesRenderTask(
                guides: List<SnapGuide>.unmodifiable(guides),
                snapConfig: config.snap,
              ),
            );
          }
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_HIGHLIGHT_MASK:
          tasks.add(
            HighlightMaskRenderTask(
              config: state.domain.document.globalElements.highlightMask,
              highlights: state.domain.document.elements
                  .where((element) => element.data.typeId.value == 'highlight')
                  .toList(growable: false),
            ),
          );
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_WATERMARK:
          tasks.add(
            WatermarkRenderTask(
              config: state.domain.document.globalElements.watermark,
            ),
          );
          break;
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_RECTANGLE:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_LINE:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_ARROW:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_FREE_DRAW:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_TEXT:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_SERIAL_NUMBER:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_HIGHLIGHT:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_FILTER:
        case proto_v2.FrameTaskKind.FRAME_TASK_KIND_UNKNOWN:
          break;
      }
    }

    return FrameRenderPlan(
      tasks: List<FrameRenderTask>.unmodifiable(tasks),
      camera: message.hasCamera()
          ? _decodeCameraV2(message.camera)
          : state.application.view.camera,
      scaleFactor: _resolveScaleFactor(message.scaleFactor),
      localeTag: localeTag,
    );
  }

  static Map<String, dynamic>? _decodeFrameTaskPayload(
    proto_v2.FrameTask task,
  ) {
    if (!task.hasPayload()) {
      return null;
    }
    final payload = task.payload;
    List<int>? bytes;
    switch (payload.whichPayload()) {
      case proto_v2.ElementPayload_Payload.rawJsonPayload:
        bytes = payload.rawJsonPayload;
        break;
      case proto_v2.ElementPayload_Payload.rawBinaryPayload:
        bytes = payload.rawBinaryPayload;
        break;
      case proto_v2.ElementPayload_Payload.rectangle:
      case proto_v2.ElementPayload_Payload.arrow:
      case proto_v2.ElementPayload_Payload.line:
      case proto_v2.ElementPayload_Payload.freeDraw:
      case proto_v2.ElementPayload_Payload.filter:
      case proto_v2.ElementPayload_Payload.highlight:
      case proto_v2.ElementPayload_Payload.text:
      case proto_v2.ElementPayload_Payload.serialNumber:
      case proto_v2.ElementPayload_Payload.notSet:
        bytes = null;
        break;
    }
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        return null;
      }
      return decoded.cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  static List<ArrowPointHandle> _decodeArrowPointHandles(Object? raw) {
    if (raw is! List) {
      return const <ArrowPointHandle>[];
    }
    final handles = <ArrowPointHandle>[];
    for (final entry in raw) {
      final handle = _decodeArrowPointHandle(entry);
      if (handle != null) {
        handles.add(handle);
      }
    }
    return handles;
  }

  static ArrowPointHandle? _decodeArrowPointHandle(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<String, dynamic>();
    final elementId = map['elementId'];
    if (elementId is! String || elementId.trim().isEmpty) {
      return null;
    }
    final kind = _decodeArrowPointKind(map['kind']);
    if (kind == null) {
      return null;
    }
    final index = map['index'];
    final position =
        _decodePointMap(map['position']) ??
        _decodePointMap(map) ??
        DrawPoint.zero;
    return ArrowPointHandle(
      elementId: elementId,
      kind: kind,
      index: index is num ? index.toInt() : 0,
      position: position,
      isFixed: map['isFixed'] == true,
    );
  }

  static ArrowPointKind? _decodeArrowPointKind(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    final normalized = raw.trim().split('.').last;
    return switch (normalized) {
      'turning' => ArrowPointKind.turning,
      'addable' => ArrowPointKind.addable,
      'loopStart' => ArrowPointKind.loopStart,
      'loopEnd' => ArrowPointKind.loopEnd,
      _ => null,
    };
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final ids = <String>{};
    for (final entry in raw) {
      if (entry is String && entry.trim().isNotEmpty) {
        ids.add(entry);
      }
    }
    return ids.toList(growable: false);
  }

  static List<SnapGuide> _decodeSnapGuides(Object? raw) {
    if (raw is! List) {
      return const <SnapGuide>[];
    }
    final guides = <SnapGuide>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.cast<String, dynamic>();
      final kind = _decodeSnapGuideKind(map['kind']);
      final axis = _decodeSnapGuideAxis(map['axis']);
      final start = _decodePointMap(map['start']);
      final end = _decodePointMap(map['end']);
      if (kind == null || axis == null || start == null || end == null) {
        continue;
      }
      final markers = <DrawPoint>[];
      final rawMarkers = map['markers'];
      if (rawMarkers is List) {
        for (final marker in rawMarkers) {
          final point = _decodePointMap(marker);
          if (point != null) {
            markers.add(point);
          }
        }
      }
      final rawLabel = map['label'];
      guides.add(
        SnapGuide(
          kind: kind,
          axis: axis,
          start: start,
          end: end,
          markers: List<DrawPoint>.unmodifiable(markers),
          label: rawLabel is num ? rawLabel.toDouble() : null,
        ),
      );
    }
    return guides;
  }

  static SnapGuideKind? _decodeSnapGuideKind(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    final normalized = raw.trim().split('.').last;
    return switch (normalized) {
      'point' => SnapGuideKind.point,
      'gap' => SnapGuideKind.gap,
      _ => null,
    };
  }

  static SnapGuideAxis? _decodeSnapGuideAxis(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    final normalized = raw.trim().split('.').last;
    return switch (normalized) {
      'horizontal' => SnapGuideAxis.horizontal,
      'vertical' => SnapGuideAxis.vertical,
      _ => null,
    };
  }

  static DrawRect? _decodeRectMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<String, dynamic>();
    final minX = _asDouble(map['minX'] ?? map['min_x']);
    final minY = _asDouble(map['minY'] ?? map['min_y']);
    final maxX = _asDouble(map['maxX'] ?? map['max_x']);
    final maxY = _asDouble(map['maxY'] ?? map['max_y']);
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }
    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static DrawPoint? _decodePointMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<String, dynamic>();
    final x = _asDouble(map['x']);
    final y = _asDouble(map['y']);
    if (x == null || y == null) {
      return null;
    }
    return DrawPoint(x: x, y: y);
  }

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  static double _resolveScaleFactor(double value) =>
      value.isFinite && value > 0 ? value : 1.0;

  static proto.DrawPoint _encodePoint(DrawPoint point) => proto.DrawPoint(
    x: point.x,
    y: point.y,
    pressure: point.pressure,
    timestampUs: $fixnum.Int64(point.timestamp),
  );

  static proto.DrawRect _encodeRect(DrawRect rect) => proto.DrawRect(
    minX: rect.minX,
    minY: rect.minY,
    maxX: rect.maxX,
    maxY: rect.maxY,
  );

  static CameraState _decodeCameraV2(proto_v2.CameraState camera) =>
      CameraState(
        position: camera.hasPosition()
            ? _decodePointV2(camera.position)
            : DrawPoint.zero,
        zoom: camera.zoom,
      );

  static _DecodedElement _decodeElementV2(proto_v2.Element element) =>
      _DecodedElement()
        ..id = element.id
        ..elementType = element.elementType.value
        ..rect = element.hasRect()
            ? _decodeRectV2(element.rect)
            : const DrawRect()
        ..rotation = element.rotation
        ..opacity = element.opacity
        ..zIndex = element.zIndex
        ..payload = element.hasPayload()
            ? _decodeElementPayloadV2(element.elementType, element.payload)
            : Uint8List(0);

  static DrawPoint _decodePointV2(proto_v2.DrawPoint point) => DrawPoint(
    x: point.x,
    y: point.y,
    pressure: point.pressure,
    timestamp: point.timestampUs.toInt(),
  );

  static DrawRect _decodeRectV2(proto_v2.DrawRect rect) => DrawRect(
    minX: rect.minX,
    minY: rect.minY,
    maxX: rect.maxX,
    maxY: rect.maxY,
  );

  static Uint8List _decodeElementPayloadV2(
    proto_v2.ElementType elementType,
    proto_v2.ElementPayload payload,
  ) {
    switch (payload.whichPayload()) {
      case proto_v2.ElementPayload_Payload.rawJsonPayload:
        _guardRawPayload(elementType, payload.whichPayload());
        return Uint8List.fromList(payload.rawJsonPayload);
      case proto_v2.ElementPayload_Payload.rawBinaryPayload:
        _guardRawPayload(elementType, payload.whichPayload());
        return Uint8List.fromList(payload.rawBinaryPayload);
      case proto_v2.ElementPayload_Payload.rectangle:
        return _jsonBytes({
          'color': payload.rectangle.colorArgb32.toInt(),
          'fillColor': payload.rectangle.fillColorArgb32.toInt(),
          'strokeWidth': payload.rectangle.strokeWidth,
        });
      case proto_v2.ElementPayload_Payload.arrow:
        return _jsonBytes({
          'points': payload.arrow.points.map(_pointToJsonV2).toList(),
          'arrowType': payload.arrow.arrowType,
        });
      case proto_v2.ElementPayload_Payload.line:
        return _jsonBytes({
          'points': payload.line.points.map(_pointToJsonV2).toList(),
          'strokeStyle': payload.line.lineType,
        });
      case proto_v2.ElementPayload_Payload.freeDraw:
        return _jsonBytes({
          'points': payload.freeDraw.points.map(_pointToJsonV2).toList(),
        });
      case proto_v2.ElementPayload_Payload.filter:
        return _jsonBytes({
          'type': payload.filter.filterType,
          'strength': payload.filter.strength,
        });
      case proto_v2.ElementPayload_Payload.highlight:
        return _jsonBytes({
          'shape': payload.highlight.shape,
          'color': payload.highlight.colorArgb32.toInt(),
        });
      case proto_v2.ElementPayload_Payload.text:
        return _jsonBytes({
          'typeId': 'text',
          'text': payload.text.text,
          'fontSize': payload.text.fontSize,
          'fontFamily': payload.text.fontFamily,
          'color': 0xFF1E1E1E,
          'horizontalAlign': 'left',
          'verticalAlign': 'center',
          'fillColor': 0,
          'fillStyle': 'solid',
          'strokeColor': 0xFFF8F4EC,
          'strokeWidth': 0.0,
          'cornerRadius': 0.0,
          'autoResize': true,
        });
      case proto_v2.ElementPayload_Payload.serialNumber:
        return _jsonBytes({
          'number': payload.serialNumber.number,
          'textElementId': payload.serialNumber.textElementId,
        });
      case proto_v2.ElementPayload_Payload.notSet:
        return Uint8List(0);
    }
  }

  static void _guardRawPayload(
    proto_v2.ElementType elementType,
    proto_v2.ElementPayload_Payload payloadKind,
  ) {
    if (payloadKind == proto_v2.ElementPayload_Payload.rawJsonPayload) {
      return;
    }
    if (!_isProductMode || _allowRawPayloadInRelease) {
      return;
    }
    if (elementType == proto_v2.ElementType.ELEMENT_TYPE_UNKNOWN) {
      return;
    }
    throw StateError(
      'Unsupported raw V2 binary payload in release mode for elementType=$elementType, payload=$payloadKind',
    );
  }

  static Map<String, Object?> _pointToJsonV2(proto_v2.DrawPoint point) => {
    'x': point.x,
    'y': point.y,
  };

  static Uint8List _jsonBytes(Map<String, Object?> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

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
    return Uint8List.fromList(utf8.encode(jsonEncode(style)));
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
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  static Map<String, Object?> _encodeElementStyleConfig(
    ElementStyleConfig style,
  ) => {
    'opacity': style.opacity,
    'serialNumber': style.serialNumber,
    'color': style.color.toARGB32(),
    'fillColor': style.fillColor.toARGB32(),
    'strokeWidth': style.strokeWidth,
    'strokeStyle': style.strokeStyle.name,
    'fillStyle': style.fillStyle.name,
    'highlightShape': style.highlightShape.name,
    'filterType': style.filterType.name,
    'filterStrength': style.filterStrength,
    'cornerRadius': style.cornerRadius,
    'arrowType': style.arrowType.name,
    'startArrowhead': style.startArrowhead.name,
    'endArrowhead': style.endArrowhead.name,
    'fontSize': style.fontSize,
    'fontFamily': style.fontFamily ?? '',
    'textAlign': style.textAlign.name,
    'verticalAlign': style.verticalAlign.name,
    'textStrokeColor': style.textStrokeColor.toARGB32(),
    'textStrokeWidth': style.textStrokeWidth,
  };

  static Uint8List encodeRuntimeConfigPayload(DrawConfig config) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'grid': {'enabled': config.grid.enabled, 'size': config.grid.size},
            'snap': {
              'enabled': config.snap.enabled,
              'distance': config.snap.distance,
            },
            'styles': {
              'rectangle': _encodeElementStyleConfig(config.rectangleStyle),
              'arrow': _encodeElementStyleConfig(config.arrowStyle),
              'line': _encodeElementStyleConfig(config.lineStyle),
              'freeDraw': _encodeElementStyleConfig(config.freeDrawStyle),
              'text': _encodeElementStyleConfig(config.textStyle),
              'serialNumber': _encodeElementStyleConfig(
                config.serialNumberStyle,
              ),
              'filter': _encodeElementStyleConfig(config.filterStyle),
              'highlight': _encodeElementStyleConfig(config.highlightStyle),
            },
          }),
        ),
      );

  static proto.ElementType _elementTypeFromTypeValue(String typeValue) =>
      switch (typeValue) {
        'rectangle' => proto.ElementType.ELEMENT_TYPE_RECTANGLE,
        'arrow' => proto.ElementType.ELEMENT_TYPE_ARROW,
        'line' => proto.ElementType.ELEMENT_TYPE_LINE,
        'free_draw' => proto.ElementType.ELEMENT_TYPE_FREE_DRAW,
        'filter' => proto.ElementType.ELEMENT_TYPE_FILTER,
        'highlight' => proto.ElementType.ELEMENT_TYPE_HIGHLIGHT,
        'text' => proto.ElementType.ELEMENT_TYPE_TEXT,
        'serial_number' => proto.ElementType.ELEMENT_TYPE_SERIAL_NUMBER,
        _ => proto.ElementType.ELEMENT_TYPE_RECTANGLE,
      };

  static String _typeValueFromElementType(int elementType) {
    final resolved =
        proto.ElementType.valueOf(elementType) ??
        proto.ElementType.ELEMENT_TYPE_RECTANGLE;
    return switch (resolved) {
      proto.ElementType.ELEMENT_TYPE_RECTANGLE => 'rectangle',
      proto.ElementType.ELEMENT_TYPE_ARROW => 'arrow',
      proto.ElementType.ELEMENT_TYPE_LINE => 'line',
      proto.ElementType.ELEMENT_TYPE_FREE_DRAW => 'free_draw',
      proto.ElementType.ELEMENT_TYPE_FILTER => 'filter',
      proto.ElementType.ELEMENT_TYPE_HIGHLIGHT => 'highlight',
      proto.ElementType.ELEMENT_TYPE_TEXT => 'text',
      proto.ElementType.ELEMENT_TYPE_SERIAL_NUMBER => 'serial_number',
      _ => 'rectangle',
    };
  }

  static proto.ZIndexOperation _zIndexOperationValue(
    ZIndexOperation operation,
  ) => switch (operation) {
    ZIndexOperation.bringToFront =>
      proto.ZIndexOperation.Z_INDEX_OPERATION_BRING_TO_FRONT,
    ZIndexOperation.sendToBack =>
      proto.ZIndexOperation.Z_INDEX_OPERATION_SEND_TO_BACK,
    ZIndexOperation.bringForward =>
      proto.ZIndexOperation.Z_INDEX_OPERATION_BRING_FORWARD,
    ZIndexOperation.sendBackward =>
      proto.ZIndexOperation.Z_INDEX_OPERATION_SEND_BACKWARD,
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
    final interaction =
        interactionMode ==
            proto.InteractionMode.INTERACTION_MODE_BOX_SELECTING.value
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
  int elementType = proto.ElementType.ELEMENT_TYPE_RECTANGLE.value;
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

Map<String, dynamic> _asJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return raw.map((key, value) => MapEntry(key.toString(), value));
}
