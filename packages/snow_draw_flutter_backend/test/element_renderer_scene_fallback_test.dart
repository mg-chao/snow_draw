import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/element_renderer.dart';

void main() {
  late LogConfig previousLogConfig;

  setUp(() {
    previousLogConfig = LogService.fallback.config;
    LogService.fallback.updateConfig(LogConfig.silent);
    ElementRenderer.clearFallbackWarningCache();
  });

  tearDown(() {
    LogService.fallback.updateConfig(previousLogConfig);
    ElementRenderer.clearFallbackWarningCache();
  });

  test('renders scene primitives when scene encoder is available', () {
    final counters = _RenderCounters();
    const textMetricsService = _TestTextMetricsService();
    final elementRegistry = _buildElementRegistry(counters);

    _renderElement(
      elementRegistry: elementRegistry,
      textMetricsService: textMetricsService,
    );

    expect(counters.sceneEncodes, 1);
    expect(counters.lastTextMetricsService, same(textMetricsService));
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

  test('deduplicates repeated scene-render failure fallback warnings', () {
    final elementRegistry = _buildElementRegistryWithThrowingEncoder();

    _renderElement(elementRegistry: elementRegistry);
    _renderElement(elementRegistry: elementRegistry);

    expect(ElementRenderer.fallbackWarningCount, 1);
  });

  test('caps fallback warning cache size', () {
    final elementRegistry = DefaultElementRegistry();
    final totalUnknownElements =
        ElementRenderer.maxFallbackWarningCacheEntries + 1;

    for (var index = 0; index < totalUnknownElements; index += 1) {
      _renderElement(
        elementRegistry: elementRegistry,
        element: ElementState(
          id: 'unknown-$index',
          rect: const DrawRect(maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: _UnknownSceneTestData('unknown_scene_test_$index'),
        ),
      );
    }

    expect(
      ElementRenderer.fallbackWarningCount,
      ElementRenderer.maxFallbackWarningCacheEntries,
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

void _renderElement({
  required DefaultElementRegistry elementRegistry,
  TextMetricsService? textMetricsService,
  ElementState? element,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const fallbackElement = ElementState(
    id: 'scene-test-element',
    rect: DrawRect(maxX: 40, maxY: 40),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: _SceneTestData(),
  );

  elementRenderer.renderElement(
    canvas: canvas,
    element: element ?? fallbackElement,
    scaleFactor: 1,
    elementRegistry: elementRegistry,
    textMetricsService: textMetricsService,
  );
  recorder.endRecording().dispose();
}

class _RenderCounters {
  var sceneEncodes = 0;
  TextMetricsService? lastTextMetricsService;
}

class _SceneTestData extends ElementData {
  const _SceneTestData();

  static const typeIdToken = ElementTypeId<_SceneTestData>('scene_test_data');

  @override
  ElementTypeId<_SceneTestData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => const {'typeId': 'scene_test_data'};
}

class _UnknownSceneTestData extends ElementData {
  const _UnknownSceneTestData(this._typeIdValue);

  final String _typeIdValue;

  @override
  ElementTypeId<ElementData> get typeId =>
      ElementTypeId<ElementData>(_typeIdValue);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'typeId': _typeIdValue};
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
    TextMetricsService? textMetricsService,
  }) {
    _counters.sceneEncodes += 1;
    _counters.lastTextMetricsService = textMetricsService;
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

class _ThrowingSceneEncoder implements ElementSceneEncoder<_SceneTestData> {
  const _ThrowingSceneEncoder();

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => throw StateError('test-only failing scene encoder');
}

class _TestTextMetricsService implements TextMetricsService {
  const _TestTextMetricsService();

  @override
  TextMetrics measure(TextLayoutRequest request) => const TextMetrics(
    width: 1,
    height: 1,
    lineHeight: 1,
    lines: <TextLineMetrics>[TextLineMetrics(width: 1, height: 1)],
  );

  @override
  void clearCaches() {}
}
