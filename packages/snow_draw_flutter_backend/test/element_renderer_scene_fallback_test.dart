import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/element_renderer.dart';

void main() {
  test('renders scene primitives when scene encoder is available', () {
    final counters = _RenderCounters();
    final elementRegistry = _buildElementRegistry(counters);

    _renderElement(elementRegistry: elementRegistry);

    expect(counters.sceneEncodes, 1);
  });

  test('uses unknown-element fallback when scene encoding is unsupported', () {
    final elementRegistry = _buildElementRegistryWithUnsupportedEncoder();

    expect(
      () => _renderElement(elementRegistry: elementRegistry),
      returnsNormally,
    );
  });

  test('uses unknown-element fallback when scene encoding throws', () {
    final elementRegistry = _buildElementRegistryWithThrowingEncoder();

    expect(
      () => _renderElement(elementRegistry: elementRegistry),
      returnsNormally,
    );
  });

  test('uses unknown-element fallback when element type is unknown', () {
    final elementRegistry = DefaultElementRegistry();

    expect(
      () => _renderElement(elementRegistry: elementRegistry),
      returnsNormally,
    );
  });
}

DefaultElementRegistry _buildElementRegistry(_RenderCounters counters) =>
    DefaultElementRegistry()..register<_SceneTestData>(
      ElementDefinition<_SceneTestData>(
        typeId: _SceneTestData.typeIdToken,
        displayName: 'scene-test',
        hitTester: const _NoopHitTester(),
        createDefaultData: _SceneTestData.new,
        fromJson: (_) => const _SceneTestData(),
        sceneEncoder: _CountingSceneEncoder(counters),
      ),
    );

DefaultElementRegistry _buildElementRegistryWithUnsupportedEncoder() =>
    DefaultElementRegistry()..register<_SceneTestData>(
      ElementDefinition<_SceneTestData>(
        typeId: _SceneTestData.typeIdToken,
        displayName: 'scene-test',
        hitTester: const _NoopHitTester(),
        createDefaultData: _SceneTestData.new,
        fromJson: (_) => const _SceneTestData(),
        sceneEncoder: const _UnsupportedSceneEncoder(),
      ),
    );

DefaultElementRegistry _buildElementRegistryWithThrowingEncoder() =>
    DefaultElementRegistry()..register<_SceneTestData>(
      ElementDefinition<_SceneTestData>(
        typeId: _SceneTestData.typeIdToken,
        displayName: 'scene-test',
        hitTester: const _NoopHitTester(),
        createDefaultData: _SceneTestData.new,
        fromJson: (_) => const _SceneTestData(),
        sceneEncoder: const _ThrowingSceneEncoder(),
      ),
    );

void _renderElement({required DefaultElementRegistry elementRegistry}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const element = ElementState(
    id: 'scene-test-element',
    rect: DrawRect(maxX: 40, maxY: 40),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: _SceneTestData(),
  );

  elementRenderer.renderElement(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
    elementRegistry: elementRegistry,
  );
  recorder.endRecording().dispose();
}

class _RenderCounters {
  var sceneEncodes = 0;
}

class _SceneTestData extends ElementData {
  const _SceneTestData();

  static const typeIdToken = ElementTypeId<_SceneTestData>('scene_test_data');

  @override
  ElementTypeId<_SceneTestData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => const {'typeId': 'scene_test_data'};
}

class _NoopHitTester implements ElementHitTester {
  const _NoopHitTester();

  @override
  DrawRect getBounds(ElementState element) => element.rect;

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) => false;
}

class _CountingSceneEncoder implements ElementSceneEncoder<_SceneTestData> {
  _CountingSceneEncoder(this._counters);

  final _RenderCounters _counters;

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) {
    _counters.sceneEncodes += 1;
    return const RenderScene(
      primitives: <RenderPrimitive>[
        RenderPathFillPrimitive(
          path: RenderPath(<RenderPathCommand>[
            RenderMoveTo(DrawPoint.zero),
            RenderLineTo(DrawPoint(x: 10, y: 0)),
            RenderLineTo(DrawPoint(x: 10, y: 10)),
            RenderClosePath(),
          ]),
          colorArgb: 0xFF1576FE,
        ),
      ],
    );
  }
}

class _UnsupportedSceneEncoder implements ElementSceneEncoder<_SceneTestData> {
  const _UnsupportedSceneEncoder();

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) => throw const SceneEncodingNotSupported('test-only unsupported scene');
}

class _ThrowingSceneEncoder implements ElementSceneEncoder<_SceneTestData> {
  const _ThrowingSceneEncoder();

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) => throw StateError('test-only failing scene encoder');
}
