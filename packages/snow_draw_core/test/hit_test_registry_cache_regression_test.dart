import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_definition.dart';
import 'package:snow_draw_core/draw/elements/core/element_hit_tester.dart';
import 'package:snow_draw_core/draw/elements/core/element_render_task_encoder.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/render/tasks/render_tasks.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/utils/hit_test.dart';

void main() {
  test('hit-test cache does not reuse results across registries', () {
    final hitRegistry = DefaultElementRegistry()
      ..register(_testElementDefinition(shouldHit: true));
    final missRegistry = DefaultElementRegistry()
      ..register(_testElementDefinition(shouldHit: false));
    final state = DrawState(
      domain: DomainState(
        document: DocumentState(
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 20, maxY: 20),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: _TestElementData(),
            ),
          ],
        ),
      ),
    );
    final stateView = DrawStateView.fromState(state);
    const position = DrawPoint(x: 10, y: 10);
    final selectionConfig = DrawConfig.defaultConfig.selection;

    final firstResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: hitRegistry,
    );
    final secondResult = hitTest.test(
      stateView: stateView,
      position: position,
      config: selectionConfig,
      registry: missRegistry,
    );

    expect(firstResult.isElementHit, isTrue);
    expect(secondResult.isHit, isFalse);
    expect(secondResult.target, HitTestTarget.none);
  });
}

ElementDefinition<_TestElementData> _testElementDefinition({
  required bool shouldHit,
}) => ElementDefinition<_TestElementData>(
  typeId: _TestElementData.typeIdToken,
  displayName: 'Test Element',
  hitTester: _ToggleHitTester(shouldHit: shouldHit),
  createDefaultData: () => const _TestElementData(),
  fromJson: (_) => const _TestElementData(),
  taskEncoder: const _NoopTaskEncoder(),
);

class _TestElementData extends ElementData {
  const _TestElementData();

  static const typeIdToken = ElementTypeId<_TestElementData>(
    'hit_test_registry_cache_probe',
  );

  @override
  ElementTypeId<_TestElementData> get typeId => typeIdToken;

  @override
  Map<String, dynamic> toJson() => {'typeId': typeId.value};
}

class _ToggleHitTester implements ElementHitTester {
  const _ToggleHitTester({required this.shouldHit});

  final bool shouldHit;

  @override
  DrawRect getBounds(ElementState element) => element.rect;

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) => shouldHit;
}

class _NoopTaskEncoder implements ElementRenderTaskEncoder<_TestElementData> {
  const _NoopTaskEncoder();

  @override
  List<RenderTask> encodeTasks({
    required ElementState element,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => const <RenderTask>[];
}
