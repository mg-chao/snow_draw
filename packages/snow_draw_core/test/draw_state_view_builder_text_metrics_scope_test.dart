import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/edit_operations.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';
import 'package:test/test.dart';

void main() {
  test('editing preview uses injected text metrics during text resize', () {
    const textId = 'text-1';
    const element = ElementState(
      id: textId,
      rect: DrawRect(maxX: 260, maxY: 60),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: TextData(text: 'ABCDEFGHIJ'),
    );
    final baseState = DrawState(
      domain: DomainState(
        document: DocumentState(elements: const [element]),
        selection: const SelectionState(selectedIds: {textId}),
      ),
    );

    final registry = DefaultEditOperationRegistry.withDefaults();
    final operation = registry.getOperation(EditOperationIds.resize)!;
    final startPosition = DrawPoint(
      x: element.rect.maxX,
      y: element.rect.centerY,
    );
    final context = operation.createContext(
      state: baseState,
      position: startPosition,
      params: const ResizeOperationParams(resizeMode: ResizeMode.right),
    );
    final initialTransform = operation.initialTransform(
      state: baseState,
      context: context,
      startPosition: startPosition,
    );
    final update = operation.update(
      state: baseState,
      context: context,
      transform: initialTransform,
      currentPosition: const DrawPoint(x: 40, y: 30),
      modifiers: const EditModifiers(),
      config: DrawConfig.defaultConfig,
    );
    final editingState = EditingState(
      operationId: operation.id,
      sessionId: 'session-1',
      context: context,
      currentTransform: update.transform,
    );
    final state = baseState.copyWith(
      application: ApplicationState.initial().copyWith(
        interaction: editingState,
      ),
    );

    final fallbackView = DrawStateViewBuilder(
      editOperations: registry,
    ).build(state);
    final fallbackWidth = fallbackView.effectiveSelection.bounds!.width;

    final customView = DrawStateViewBuilder(
      editOperations: registry,
      textMetricsService: const _WideGlyphTextMetricsService(),
    ).build(state);
    final customWidth = customView.effectiveSelection.bounds!.width;

    expect(customWidth, greaterThan(fallbackWidth + 80));
    expect(customView.previewElementsById[textId]!.rect.width, customWidth);
  });
}

final class _WideGlyphTextMetricsService implements TextMetricsService {
  const _WideGlyphTextMetricsService();

  static const _glyphWidth = 20.0;
  static const _lineHeight = 20.0;

  @override
  TextMetrics measure(TextLayoutRequest request) {
    final text = request.data.text.isEmpty ? ' ' : request.data.text;
    final lineMetrics = text
        .split('\n')
        .map(
          (line) => TextLineMetrics(
            width: (line.isEmpty ? 1 : line.runes.length) * _glyphWidth,
            height: _lineHeight,
          ),
        )
        .toList(growable: false);

    var maxLineWidth = 0.0;
    for (final line in lineMetrics) {
      if (line.width > maxLineWidth) {
        maxLineWidth = line.width;
      }
    }

    var width = maxLineWidth > request.maxWidth
        ? request.maxWidth
        : maxLineWidth;
    final minWidth = request.minWidth;
    if (minWidth != null && width < minWidth) {
      width = minWidth;
    }

    return TextMetrics(
      width: width,
      height: _lineHeight * lineMetrics.length,
      lineHeight: _lineHeight,
      lines: List<TextLineMetrics>.unmodifiable(lineMetrics),
    );
  }

  @override
  void clearCaches() {}
}
