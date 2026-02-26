import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:snow_draw_engine/snow_draw_engine.dart';
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
