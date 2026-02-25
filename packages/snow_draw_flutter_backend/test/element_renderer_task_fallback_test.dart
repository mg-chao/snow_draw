import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
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

  test('renders tasks when a task encoder is available', () {
    final counters = _RenderCounters();
    const textMetricsService = _TestTextMetricsService();
    final elementRegistry = _buildElementRegistry(counters);

    _renderElement(
      elementRegistry: elementRegistry,
      textMetricsService: textMetricsService,
    );

    expect(counters.taskEncodes, 1);
    expect(counters.lastTextMetricsService, same(textMetricsService));
  });

  test('uses unknown-element fallback when task encoding throws', () {
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

  test('deduplicates repeated task-render failure fallback warnings', () {
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
          data: _UnknownTaskTestData('unknown_task_test_$index'),
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
    DefaultElementRegistry()..register<_TaskTestData>(
      ElementDefinition<_TaskTestData>(
        typeId: _TaskTestData.typeIdToken,
        displayName: 'task-test',
        hitTester: const _NoopHitTester(),
        createDefaultData: _TaskTestData.new,
        fromJson: (_) => const _TaskTestData(),
        taskEncoder: _CountingTaskEncoder(counters),
      ),
    );

DefaultElementRegistry _buildElementRegistryWithThrowingEncoder() =>
    DefaultElementRegistry()..register<_TaskTestData>(
      ElementDefinition<_TaskTestData>(
        typeId: _TaskTestData.typeIdToken,
        displayName: 'task-test',
        hitTester: const _NoopHitTester(),
        createDefaultData: _TaskTestData.new,
        fromJson: (_) => const _TaskTestData(),
        taskEncoder: const _ThrowingTaskEncoder(),
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
    id: 'task-test-element',
    rect: DrawRect(maxX: 40, maxY: 40),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: _TaskTestData(),
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
  var taskEncodes = 0;
  TextMetricsService? lastTextMetricsService;
}

class _TaskTestData extends ElementData {
  const _TaskTestData();

  static const typeIdToken = ElementTypeId<_TaskTestData>('task_test_data');

  @override
  ElementTypeId<_TaskTestData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => const {'typeId': 'task_test_data'};
}

class _UnknownTaskTestData extends ElementData {
  const _UnknownTaskTestData(this._typeIdValue);

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

final class _CountingTaskEncoder
    extends TypedElementRenderTaskEncoder<_TaskTestData> {
  _CountingTaskEncoder(this._counters);

  final _RenderCounters _counters;

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required _TaskTestData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    _counters.taskEncodes += 1;
    _counters.lastTextMetricsService = textMetricsService;
    return <RenderTask>[
      RectangleRenderTask(
        element: element,
        data: const RectangleData(
          color: DrawColor(0xFF1576FE),
          fillColor: DrawColor(0x221576FE),
        ),
        localeTag: localeTag,
      ),
    ];
  }
}

final class _ThrowingTaskEncoder
    extends TypedElementRenderTaskEncoder<_TaskTestData> {
  const _ThrowingTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required _TaskTestData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => throw StateError('test-only failing task encoder');
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
