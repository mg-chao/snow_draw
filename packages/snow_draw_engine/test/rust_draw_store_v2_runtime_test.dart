import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_engine/src/proto/engine.pb.dart' as proto;
import 'package:snow_draw_engine/src/proto/engine_v2.pb.dart' as proto_v2;
import 'package:test/test.dart';

void main() {
  test('RustDrawStore rejects runtime without init ack', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);

    expect(
      () => RustDrawStore(
        context: context,
        engine: _FakeRustCanvasEngine.noAck(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'RustDrawStore hydrates non-empty initialState through V2 config bootstrap',
    () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final initialElement = ElementState(
        id: 'bootstrap-rect',
        rect: const DrawRect(minX: 12, minY: 24, maxX: 132, maxY: 94),
        rotation: 0.2,
        opacity: 0.75,
        zIndex: 4,
        data: const RectangleData(
          color: DrawColor(0xFF336699),
          fillColor: DrawColor(0x00000000),
          strokeWidth: 3.5,
        ),
      );
      final initialState = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: [initialElement],
            elementsVersion: 7,
          ),
          selection: const SelectionState(
            selectedIds: {'bootstrap-rect'},
            selectionVersion: 3,
          ),
        ),
        application: const ApplicationState(
          view: ViewState(
            camera: CameraState(position: DrawPoint(x: 50, y: -30), zoom: 1.5),
          ),
          interaction: IdleState(),
        ),
      );

      final store = RustDrawStore(
        context: context,
        initialState: initialState,
        engine: _BootstrapConfigRustCanvasEngine(),
      );
      addTearDown(store.dispose);

      final hydrated = store.state.domain.document.getElementById(
        'bootstrap-rect',
      );
      expect(hydrated, isNotNull);
      expect(hydrated!.rect, initialElement.rect);
      expect(store.state.domain.document.elementsVersion, 7);
      expect(store.state.domain.selection.selectionVersion, 3);
      expect(
        store.state.application.view.camera,
        const CameraState(position: DrawPoint(x: 50, y: -30), zoom: 1.5),
      );
      expect(store.state.domain.selection.selectedIds, {'bootstrap-rect'});
    },
  );

  test('RustDrawStore consumes V2 command input and snapshot output', () async {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);

    final fakeEngine = _FakeRustCanvasEngine();
    final store = RustDrawStore(context: context, engine: fakeEngine);
    addTearDown(store.dispose);

    await store.dispatch(
      const CreateElement(
        typeId: RectangleData.typeIdToken,
        position: DrawPoint.zero,
      ),
    );

    expect(fakeEngine.v2InputCount, 1);
    expect(store.state.domain.document.elements, hasLength(1));
    expect(store.canUndo, isTrue);
  });

  test(
    'RustDrawStore decodes V2 frame plan element and overlay tasks',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final fakeEngine = _FakeRustCanvasEngine.withFramePlan();
      final store = RustDrawStore(context: context, engine: fakeEngine);
      addTearDown(store.dispose);

      await store.dispatch(
        const CreateElement(
          typeId: RectangleData.typeIdToken,
          position: DrawPoint.zero,
        ),
      );

      final plan = store.latestFramePlan;
      expect(plan.tasks.whereType<BackgroundRenderTask>(), hasLength(1));

      final arrowOverlay = plan.tasks.whereType<ArrowPointOverlayRenderTask>();
      expect(arrowOverlay, hasLength(1));
      expect(arrowOverlay.single.handles, hasLength(1));
      expect(arrowOverlay.single.deleteIndicatorVisible, isTrue);

      final binding = plan.tasks.whereType<ArrowBindingHighlightRenderTask>();
      expect(binding, hasLength(1));
      expect(binding.single.elementIds, contains('bind-target'));

      final hover = plan.tasks.whereType<HoverOutlineRenderTask>();
      expect(hover, hasLength(1));
      expect(hover.single.element.id, 'v2-text-1');
      expect(hover.single.useTextUnderlineStyle, isTrue);

      final guides = plan.tasks.whereType<SnapGuidesRenderTask>();
      expect(guides, hasLength(1));
      expect(guides.single.guides, hasLength(1));
      expect(guides.single.guides.single.axis, SnapGuideAxis.horizontal);

      final boxSelection = plan.tasks.whereType<BoxSelectionRenderTask>();
      expect(boxSelection, hasLength(1));
      expect(
        boxSelection.single.bounds,
        const DrawRect(minX: 1, minY: 2, maxX: 3, maxY: 4),
      );
    },
  );

  test(
    'RustDrawStore preserves creating interaction from V2 snapshots',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final store = RustDrawStore(
        context: context,
        engine: _ScriptedRustCanvasEngine(
          (_) => proto_v2.EngineSnapshot(
            schemaVersion: 2,
            documentVersion: $fixnum.Int64(1),
            selectionVersion: $fixnum.Int64(1),
            interactionMode: proto_v2.InteractionMode.INTERACTION_MODE_CREATING,
            camera: _cameraPayload,
            elements: [_rectangleElementPayload(id: 'create-rect')],
            selectedIds: const ['create-rect'],
            historyUndoLen: $fixnum.Int64(1),
            historyRedoLen: $fixnum.Int64(0),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        const CreateElement(
          typeId: RectangleData.typeIdToken,
          position: DrawPoint(x: 32, y: 40),
        ),
      );

      final interaction = store.state.application.interaction;
      expect(interaction, isA<CreatingState>());
      final creating = interaction as CreatingState;
      expect(creating.element.id, 'create-rect');
      expect(creating.startPosition, const DrawPoint(x: 32, y: 40));
    },
  );

  test(
    'RustDrawStore preserves text editing interaction from V2 snapshots',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final store = RustDrawStore(
        context: context,
        engine: _ScriptedRustCanvasEngine(
          (_) => proto_v2.EngineSnapshot(
            schemaVersion: 2,
            documentVersion: $fixnum.Int64(3),
            selectionVersion: $fixnum.Int64(2),
            interactionMode:
                proto_v2.InteractionMode.INTERACTION_MODE_TEXT_EDITING,
            camera: _cameraPayload,
            elements: [_textElementPayload(id: 'text-1', text: 'draft')],
            selectedIds: const ['text-1'],
            historyUndoLen: $fixnum.Int64(1),
            historyRedoLen: $fixnum.Int64(0),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        const StartTextEdit(position: DrawPoint(x: 12, y: 18)),
      );

      final interaction = store.state.application.interaction;
      expect(interaction, isA<TextEditingState>());
      final textEditing = interaction as TextEditingState;
      expect(textEditing.elementId, 'text-1');
      expect(textEditing.draftData.text, 'draft');
      expect(textEditing.isNew, isTrue);
    },
  );

  test(
    'RustDrawStore preserves styled text payload fields from raw V2 snapshots',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final store = RustDrawStore(
        context: context,
        engine: _ScriptedRustCanvasEngine(
          (_) => proto_v2.EngineSnapshot(
            schemaVersion: 2,
            documentVersion: $fixnum.Int64(4),
            selectionVersion: $fixnum.Int64(1),
            interactionMode: proto_v2.InteractionMode.INTERACTION_MODE_IDLE,
            camera: _cameraPayload,
            elements: [
              proto_v2.Element(
                id: 'styled-text',
                elementType: proto_v2.ElementType.ELEMENT_TYPE_TEXT,
                rect: proto_v2.DrawRect(
                  minX: 12,
                  minY: 18,
                  maxX: 220,
                  maxY: 88,
                ),
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                payload: proto_v2.ElementPayload(
                  rawJsonPayload: Uint8List.fromList(
                    utf8.encode(
                      jsonEncode({
                        'typeId': 'text',
                        'text': 'styled',
                        'color': 0xFF112233,
                        'fontSize': 19.0,
                        'fontFamily': 'Fira Code',
                        'horizontalAlign': 'center',
                        'verticalAlign': 'top',
                        'fillColor': 0xFF445566,
                        'fillStyle': 'line',
                        'strokeColor': 0xFF778899,
                        'strokeWidth': 1.5,
                        'cornerRadius': 3.0,
                        'autoResize': false,
                      }),
                    ),
                  ),
                ),
              ),
            ],
            selectedIds: const [],
            historyUndoLen: $fixnum.Int64(0),
            historyRedoLen: $fixnum.Int64(0),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(const SelectAll());

      final element = store.state.domain.document.getElementById('styled-text');
      expect(element, isNotNull);
      final data = element!.data;
      expect(data, isA<TextData>());
      final text = data as TextData;
      expect(text.text, 'styled');
      expect(text.color, const DrawColor(0xFF112233));
      expect(text.fontSize, 19.0);
      expect(text.fontFamily, 'Fira Code');
      expect(text.horizontalAlign, TextHorizontalAlign.center);
      expect(text.verticalAlign, TextVerticalAlign.top);
      expect(text.fillColor, const DrawColor(0xFF445566));
      expect(text.fillStyle, FillStyle.line);
      expect(text.strokeColor, const DrawColor(0xFF778899));
      expect(text.strokeWidth, 1.5);
      expect(text.cornerRadius, 3.0);
      expect(text.autoResize, isFalse);
    },
  );

  test(
    'RustDrawStore restores drag pending metadata from action hints',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);

      final store = RustDrawStore(
        context: context,
        engine: _ScriptedRustCanvasEngine(
          (_) => proto_v2.EngineSnapshot(
            schemaVersion: 2,
            documentVersion: $fixnum.Int64(2),
            selectionVersion: $fixnum.Int64(1),
            interactionMode:
                proto_v2.InteractionMode.INTERACTION_MODE_DRAG_PENDING,
            camera: _cameraPayload,
            elements: const [],
            selectedIds: const [],
            historyUndoLen: $fixnum.Int64(0),
            historyRedoLen: $fixnum.Int64(0),
          ),
        ),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        const SetDragPending(
          pointerDownPosition: DrawPoint(x: 55, y: 77),
          intent: PendingMoveIntent(),
        ),
      );

      final interaction = store.state.application.interaction;
      expect(interaction, isA<DragPendingState>());
      final dragPending = interaction as DragPendingState;
      expect(dragPending.pointerDownPosition, const DrawPoint(x: 55, y: 77));
      expect(dragPending.intent, const PendingMoveIntent());
    },
  );
}

final _cameraPayload = proto_v2.CameraState(
  position: proto_v2.DrawPoint(
    x: 0,
    y: 0,
    pressure: 0,
    timestampUs: $fixnum.Int64(0),
  ),
  zoom: 1,
);

proto_v2.Element _rectangleElementPayload({required String id}) =>
    proto_v2.Element(
      id: id,
      elementType: proto_v2.ElementType.ELEMENT_TYPE_RECTANGLE,
      rect: proto_v2.DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 70),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      payload: proto_v2.ElementPayload(
        rawJsonPayload: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'color': 0xFF1E1E1E,
              'fillColor': 0,
              'strokeWidth': 2.0,
              'strokeStyle': 'solid',
              'fillStyle': 'solid',
              'cornerRadius': 4.0,
            }),
          ),
        ),
      ),
    );

proto_v2.Element _textElementPayload({
  required String id,
  required String text,
}) => proto_v2.Element(
  id: id,
  elementType: proto_v2.ElementType.ELEMENT_TYPE_TEXT,
  rect: proto_v2.DrawRect(minX: 20, minY: 24, maxX: 160, maxY: 52),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  payload: proto_v2.ElementPayload(
    text: proto_v2.TextPayload(text: text, fontSize: 21.0, fontFamily: ''),
  ),
);

final class _ScriptedRustCanvasEngine implements RustCanvasEngine {
  _ScriptedRustCanvasEngine(this._snapshotForCommand) {
    _outputs.add(
      Uint8List.fromList(
        proto_v2.EngineOutput(
          sequence: $fixnum.Int64(0),
          initAck: proto_v2.EngineInitAck(
            abiVersion: 2,
            schemaVersion: 2,
            grantedCapabilitiesMask: $fixnum.Int64(0x1F),
            message: 'ok',
          ),
        ).writeToBuffer(),
      ),
    );
  }

  final proto_v2.EngineSnapshot Function(proto.EngineCommand command)
  _snapshotForCommand;
  final _outputs = <Uint8List>[];

  @override
  int get abiVersion => 2;

  @override
  int get capabilities => 0;

  @override
  void processInputV2(Uint8List inputBytes) {
    final input = proto_v2.EngineInput.fromBuffer(inputBytes);
    if (input.whichPayload() != proto_v2.EngineInput_Payload.commandEvent) {
      return;
    }

    final command = proto.EngineCommand.fromBuffer(
      input.commandEvent.commandBytes,
    );
    final snapshot = _snapshotForCommand(command);
    _outputs.add(
      Uint8List.fromList(
        proto_v2.EngineOutput(
          sequence: $fixnum.Int64(1),
          snapshot: snapshot,
        ).writeToBuffer(),
      ),
    );
  }

  @override
  Uint8List? pollOutputV2() {
    if (_outputs.isEmpty) {
      return null;
    }
    return _outputs.removeAt(0);
  }

  @override
  void dispose() {}

  @override
  void dispatch(Uint8List commandBytes) {
    throw UnimplementedError();
  }

  @override
  void dispatchBatch(List<Uint8List> commandBatch) {
    throw UnimplementedError();
  }

  @override
  Uint8List getSnapshotBytes() {
    throw UnimplementedError();
  }

  @override
  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    throw UnimplementedError();
  }

  @override
  Uint8List? pollEventBytes() {
    throw UnimplementedError();
  }
}

final class _BootstrapConfigRustCanvasEngine implements RustCanvasEngine {
  _BootstrapConfigRustCanvasEngine() {
    _outputs.add(
      Uint8List.fromList(
        proto_v2.EngineOutput(
          sequence: $fixnum.Int64(0),
          initAck: proto_v2.EngineInitAck(
            abiVersion: 2,
            schemaVersion: 2,
            grantedCapabilitiesMask: $fixnum.Int64(0x1F),
            message: 'ok',
          ),
        ).writeToBuffer(),
      ),
    );
  }

  static const _bootstrapSnapshotConfigKey = '__bootstrapSnapshotV1ProtoBase64';

  final _outputs = <Uint8List>[];

  @override
  int get abiVersion => 2;

  @override
  int get capabilities => 0;

  @override
  void processInputV2(Uint8List inputBytes) {
    final input = proto_v2.EngineInput.fromBuffer(inputBytes);
    if (input.whichPayload() != proto_v2.EngineInput_Payload.configEvent) {
      return;
    }
    final payload = input.configEvent.configPayload;
    if (payload.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        return;
      }
      final map = decoded.cast<String, dynamic>();
      final encoded = map[_bootstrapSnapshotConfigKey];
      if (encoded is! String || encoded.isEmpty) {
        return;
      }
      final snapshot = proto.EngineSnapshot.fromBuffer(base64Decode(encoded));
      _outputs.add(
        Uint8List.fromList(
          proto_v2.EngineOutput(
            sequence: $fixnum.Int64(1),
            snapshot: _toSnapshotV2(snapshot),
          ).writeToBuffer(),
        ),
      );
    } on Object {
      // Ignore malformed bootstrap payloads in fake engine tests.
    }
  }

  static proto_v2.EngineSnapshot _toSnapshotV2(proto.EngineSnapshot snapshot) =>
      proto_v2.EngineSnapshot(
        schemaVersion: snapshot.schemaVersion,
        documentVersion: snapshot.documentVersion,
        selectionVersion: snapshot.selectionVersion,
        interactionMode:
            proto_v2.InteractionMode.valueOf(snapshot.interactionMode.value) ??
            proto_v2.InteractionMode.INTERACTION_MODE_IDLE,
        camera: snapshot.hasCamera()
            ? proto_v2.CameraState(
                position: snapshot.camera.hasPosition()
                    ? proto_v2.DrawPoint(
                        x: snapshot.camera.position.x,
                        y: snapshot.camera.position.y,
                        pressure: snapshot.camera.position.pressure,
                        timestampUs: snapshot.camera.position.timestampUs,
                      )
                    : null,
                zoom: snapshot.camera.zoom,
              )
            : null,
        elements: snapshot.elements
            .map(
              (element) => proto_v2.Element(
                id: element.id,
                elementType:
                    proto_v2.ElementType.valueOf(element.elementType.value) ??
                    proto_v2.ElementType.ELEMENT_TYPE_UNKNOWN,
                rect: element.hasRect()
                    ? proto_v2.DrawRect(
                        minX: element.rect.minX,
                        minY: element.rect.minY,
                        maxX: element.rect.maxX,
                        maxY: element.rect.maxY,
                      )
                    : null,
                rotation: element.rotation,
                opacity: element.opacity,
                zIndex: element.zIndex,
                payload: proto_v2.ElementPayload(
                  rawJsonPayload: Uint8List.fromList(element.payload),
                ),
              ),
            )
            .toList(growable: false),
        selectedIds: snapshot.selectedIds,
        historyUndoLen: snapshot.historyUndoLen,
        historyRedoLen: snapshot.historyRedoLen,
        globalElementsPayload: snapshot.globalElementsPayload,
      );

  @override
  Uint8List? pollOutputV2() {
    if (_outputs.isEmpty) {
      return null;
    }
    return _outputs.removeAt(0);
  }

  @override
  void dispose() {}

  @override
  void dispatch(Uint8List commandBytes) {
    throw UnimplementedError();
  }

  @override
  void dispatchBatch(List<Uint8List> commandBatch) {
    throw UnimplementedError();
  }

  @override
  Uint8List getSnapshotBytes() {
    throw UnimplementedError();
  }

  @override
  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    throw UnimplementedError();
  }

  @override
  Uint8List? pollEventBytes() {
    throw UnimplementedError();
  }
}

final class _FakeRustCanvasEngine implements RustCanvasEngine {
  _FakeRustCanvasEngine({bool withInitAck = true, this.emitFramePlan = false}) {
    if (!withInitAck) {
      return;
    }
    _outputs.add(
      Uint8List.fromList(
        proto_v2.EngineOutput(
          sequence: $fixnum.Int64(0),
          initAck: proto_v2.EngineInitAck(
            abiVersion: 2,
            schemaVersion: 2,
            grantedCapabilitiesMask: $fixnum.Int64(0x1F),
            message: 'ok',
          ),
        ).writeToBuffer(),
      ),
    );
  }

  factory _FakeRustCanvasEngine.noAck() =>
      _FakeRustCanvasEngine(withInitAck: false);
  factory _FakeRustCanvasEngine.withFramePlan() =>
      _FakeRustCanvasEngine(emitFramePlan: true);

  final _outputs = <Uint8List>[];
  final bool emitFramePlan;
  var v2InputCount = 0;

  @override
  int get abiVersion => 2;

  @override
  int get capabilities => 0;

  @override
  void processInputV2(Uint8List inputBytes) {
    final input = proto_v2.EngineInput.fromBuffer(inputBytes);
    switch (input.whichPayload()) {
      case proto_v2.EngineInput_Payload.commandEvent:
        v2InputCount += 1;
        _outputs.add(
          Uint8List.fromList(
            proto_v2.EngineOutput(
              sequence: $fixnum.Int64(1),
              snapshot: emitFramePlan
                  ? _snapshotWithFramePlanPayload
                  : _snapshotPayload,
            ).writeToBuffer(),
          ),
        );
        if (emitFramePlan) {
          _outputs.add(
            Uint8List.fromList(
              proto_v2.EngineOutput(
                sequence: $fixnum.Int64(2),
                framePlan: proto_v2.FrameRenderPlan(
                  schemaVersion: 2,
                  camera: proto_v2.CameraState(
                    position: proto_v2.DrawPoint(
                      x: 0,
                      y: 0,
                      pressure: 0,
                      timestampUs: $fixnum.Int64(0),
                    ),
                    zoom: 1,
                  ),
                  scaleFactor: 1,
                  localeTag: 'en-US',
                  tasks: [
                    proto_v2.FrameTask(
                      kind: proto_v2.FrameTaskKind.FRAME_TASK_KIND_BACKGROUND,
                    ),
                    proto_v2.FrameTask(
                      kind: proto_v2.FrameTaskKind.FRAME_TASK_KIND_RECTANGLE,
                      elementId: 'v2-rect-1',
                      elementType: proto_v2.ElementType.ELEMENT_TYPE_RECTANGLE,
                    ),
                    proto_v2.FrameTask(
                      kind: proto_v2
                          .FrameTaskKind
                          .FRAME_TASK_KIND_ARROW_POINT_OVERLAY,
                      payload: proto_v2.ElementPayload(
                        rawJsonPayload: Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'handles': [
                                {
                                  'elementId': 'v2-rect-1',
                                  'kind': 'turning',
                                  'index': 0,
                                  'position': {'x': 1.5, 'y': 2.5},
                                },
                              ],
                              'deleteIndicatorVisible': true,
                            }),
                          ),
                        ),
                      ),
                    ),
                    proto_v2.FrameTask(
                      kind: proto_v2
                          .FrameTaskKind
                          .FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT,
                      payload: proto_v2.ElementPayload(
                        rawJsonPayload: Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'elementIds': ['bind-target'],
                            }),
                          ),
                        ),
                      ),
                    ),
                    proto_v2.FrameTask(
                      kind:
                          proto_v2.FrameTaskKind.FRAME_TASK_KIND_HOVER_OUTLINE,
                      payload: proto_v2.ElementPayload(
                        rawJsonPayload: Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'elementId': 'v2-text-1',
                              'useTextUnderlineStyle': true,
                            }),
                          ),
                        ),
                      ),
                    ),
                    proto_v2.FrameTask(
                      kind: proto_v2.FrameTaskKind.FRAME_TASK_KIND_SNAP_GUIDES,
                      payload: proto_v2.ElementPayload(
                        rawJsonPayload: Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'guides': [
                                {
                                  'kind': 'point',
                                  'axis': 'horizontal',
                                  'start': {'x': 0.0, 'y': 10.0},
                                  'end': {'x': 100.0, 'y': 10.0},
                                },
                              ],
                            }),
                          ),
                        ),
                      ),
                    ),
                    proto_v2.FrameTask(
                      kind:
                          proto_v2.FrameTaskKind.FRAME_TASK_KIND_BOX_SELECTION,
                      payload: proto_v2.ElementPayload(
                        rawJsonPayload: Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'bounds': {
                                'minX': 1.0,
                                'minY': 2.0,
                                'maxX': 3.0,
                                'maxY': 4.0,
                              },
                            }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ).writeToBuffer(),
            ),
          );
        }
        break;
      case proto_v2.EngineInput_Payload.textMetricsResponse:
      case proto_v2.EngineInput_Payload.keyboardEvent:
      case proto_v2.EngineInput_Payload.pointerEvent:
      case proto_v2.EngineInput_Payload.toolEvent:
      case proto_v2.EngineInput_Payload.configEvent:
      case proto_v2.EngineInput_Payload.notSet:
        break;
    }
  }

  @override
  Uint8List? pollOutputV2() {
    if (_outputs.isEmpty) {
      return null;
    }
    return _outputs.removeAt(0);
  }

  @override
  void dispose() {}

  @override
  void dispatch(Uint8List commandBytes) {
    throw UnimplementedError();
  }

  @override
  void dispatchBatch(List<Uint8List> commandBatch) {
    throw UnimplementedError();
  }

  @override
  Uint8List getSnapshotBytes() {
    throw UnimplementedError();
  }

  @override
  Uint8List buildFramePlanBytes(Uint8List requestBytes) {
    throw UnimplementedError();
  }

  @override
  Uint8List? pollEventBytes() {
    throw UnimplementedError();
  }

  static final _snapshotPayload = proto_v2.EngineSnapshot(
    schemaVersion: 2,
    documentVersion: $fixnum.Int64(1),
    selectionVersion: $fixnum.Int64(0),
    interactionMode: proto_v2.InteractionMode.INTERACTION_MODE_IDLE,
    camera: proto_v2.CameraState(
      position: proto_v2.DrawPoint(
        x: 0,
        y: 0,
        pressure: 0,
        timestampUs: $fixnum.Int64(0),
      ),
      zoom: 1,
    ),
    elements: [
      proto_v2.Element(
        id: 'v2-rect-1',
        elementType: proto_v2.ElementType.ELEMENT_TYPE_RECTANGLE,
        rect: proto_v2.DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        payload: proto_v2.ElementPayload(
          rawJsonPayload: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'color': 0xFF1E1E1E,
                'fillColor': 0,
                'strokeWidth': 2.0,
                'strokeStyle': 'solid',
                'fillStyle': 'solid',
                'cornerRadius': 4.0,
              }),
            ),
          ),
        ),
      ),
    ],
    selectedIds: const [],
    historyUndoLen: $fixnum.Int64(1),
    historyRedoLen: $fixnum.Int64(0),
    globalElementsPayload: Uint8List(0),
  );

  static final _snapshotWithFramePlanPayload = proto_v2.EngineSnapshot(
    schemaVersion: 2,
    documentVersion: $fixnum.Int64(1),
    selectionVersion: $fixnum.Int64(0),
    interactionMode: proto_v2.InteractionMode.INTERACTION_MODE_IDLE,
    camera: proto_v2.CameraState(
      position: proto_v2.DrawPoint(
        x: 0,
        y: 0,
        pressure: 0,
        timestampUs: $fixnum.Int64(0),
      ),
      zoom: 1,
    ),
    elements: [
      ..._snapshotPayload.elements,
      proto_v2.Element(
        id: 'v2-text-1',
        elementType: proto_v2.ElementType.ELEMENT_TYPE_TEXT,
        rect: proto_v2.DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        payload: proto_v2.ElementPayload(
          rawJsonPayload: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'text': 'hello',
                'fontSize': 20.0,
                'fontFamily': '',
                'color': 0xFF1E1E1E,
                'fillColor': 0,
                'strokeWidth': 0.0,
              }),
            ),
          ),
        ),
      ),
    ],
    selectedIds: const [],
    historyUndoLen: $fixnum.Int64(1),
    historyRedoLen: $fixnum.Int64(0),
    globalElementsPayload: Uint8List(0),
  );
}
