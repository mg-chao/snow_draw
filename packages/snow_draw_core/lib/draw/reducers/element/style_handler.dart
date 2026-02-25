import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../edit/apply/edit_apply.dart';
import '../../elements/core/element_style_updatable_data.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/elbow/elbow_router.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/serial_number/serial_number_layout.dart';
import '../../elements/types/text/text_data.dart';
import '../../elements/types/text/text_editing_geometry.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/text/text_metrics_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/element_style.dart';
import '../core/reducer_utils.dart';

DrawState handleUpdateElementsStyle(
  DrawState state,
  UpdateElementsStyle action,
  DrawContext context,
) {
  final targetIds = action.elementIds.toSet();
  if (targetIds.isEmpty || !action.hasUpdates) {
    return state;
  }

  final document = state.domain.document;
  final selectedIds = state.domain.selection.selectedIds;
  final trackSelectionOverlay = selectedIds.length > 1;
  final replacementsById = <String, ElementState>{};
  var selectionGeometryChanged = false;

  for (final id in targetIds) {
    final element = document.getElementById(id);
    if (element == null) {
      continue;
    }
    final update = _resolveElementStyleUpdate(
      element: element,
      styleUpdate: action.styleUpdate,
      opacity: action.opacity,
      trackGeometryChange: trackSelectionOverlay && selectedIds.contains(id),
      elementsById: document.elementMap,
      textMetricsService: context.textMetricsService,
    );
    if (update == null) {
      continue;
    }
    replacementsById[id] = update.element;
    if (update.geometryChanged) {
      selectionGeometryChanged = true;
    }
  }

  final nextTextEdit = _resolveTextEditingUpdate(
    state: state,
    targetIds: targetIds,
    styleUpdate: action.styleUpdate,
    opacity: action.opacity,
    context: context,
  );
  final domainChanged = replacementsById.isNotEmpty;
  final interactionChanged = nextTextEdit != null;

  if (!domainChanged && !interactionChanged) {
    return state;
  }

  final nextDomain = domainChanged
      ? state.domain.copyWith(
          document: document.copyWith(
            elements: EditApply.replaceElementsById(
              elements: document.elements,
              replacementsById: replacementsById,
            ),
          ),
        )
      : state.domain;
  final nextApplication = interactionChanged
      ? state.application.copyWith(interaction: nextTextEdit)
      : state.application;

  final nextState = state.copyWith(
    domain: nextDomain,
    application: nextApplication,
  );

  if (!selectionGeometryChanged) {
    return nextState;
  }

  return applySelectionChange(
    nextState,
    selectedIds,
    forceRefreshOverlay: true,
  );
}

({ElementState element, bool geometryChanged})? _resolveElementStyleUpdate({
  required ElementState element,
  required ElementStyleUpdate styleUpdate,
  required double? opacity,
  required bool trackGeometryChange,
  required Map<String, ElementState> elementsById,
  required TextMetricsService textMetricsService,
}) {
  final styleUpdated = _resolveDataStyleUpdate(
    element: element,
    styleUpdate: styleUpdate,
    trackGeometryChange: trackGeometryChange,
    elementsById: elementsById,
    textMetricsService: textMetricsService,
  );
  final baseElement = styleUpdated?.element ?? element;
  final nextElement = _resolveOpacityUpdate(baseElement, opacity);
  if (nextElement == element) {
    return null;
  }
  return (
    element: nextElement,
    geometryChanged: styleUpdated?.geometryChanged ?? false,
  );
}

({ElementState element, bool geometryChanged})? _resolveDataStyleUpdate({
  required ElementState element,
  required ElementStyleUpdate styleUpdate,
  required bool trackGeometryChange,
  required Map<String, ElementState> elementsById,
  required TextMetricsService textMetricsService,
}) {
  if (styleUpdate.isEmpty) {
    return null;
  }

  final data = element.data;
  if (data is! ElementStyleUpdatableData) {
    return null;
  }

  final updatedData = (data as ElementStyleUpdatableData).withStyleUpdate(
    styleUpdate,
  );
  if (updatedData == data) {
    return null;
  }

  var updatedElement = element.copyWith(data: updatedData);
  var geometryChanged = false;

  switch ((data, updatedData)) {
    case (TextData _, final TextData updatedTextData)
        when _shouldRelayoutText(styleUpdate):
      final nextRect = _resolveTextRect(
        rect: updatedElement.rect,
        data: updatedTextData,
        textMetricsService: textMetricsService,
      );
      if (nextRect != updatedElement.rect) {
        geometryChanged = trackGeometryChange;
        updatedElement = updatedElement.copyWith(rect: nextRect);
      }
    case (SerialNumberData _, final SerialNumberData updatedSerialNumberData)
        when _shouldRelayoutSerialNumber(styleUpdate):
      final nextRect = _resolveSerialNumberRect(
        rect: updatedElement.rect,
        data: updatedSerialNumberData,
        textMetricsService: textMetricsService,
      );
      if (nextRect != updatedElement.rect) {
        geometryChanged = trackGeometryChange;
        updatedElement = updatedElement.copyWith(rect: nextRect);
      }
    case (final ArrowData previousArrowData, final ArrowData updatedArrowData)
        when previousArrowData.arrowType != updatedArrowData.arrowType:
      final result = _resolveArrowRectAndData(
        element: updatedElement,
        data: updatedArrowData,
        elementsById: elementsById,
      );
      if (result.rect != updatedElement.rect && trackGeometryChange) {
        geometryChanged = true;
      }
      updatedElement = updatedElement.copyWith(
        rect: result.rect,
        data: result.data,
      );
    case _:
  }

  return (element: updatedElement, geometryChanged: geometryChanged);
}

ElementState _resolveOpacityUpdate(ElementState element, double? opacity) {
  if (opacity == null || opacity == element.opacity) {
    return element;
  }
  return element.copyWith(opacity: opacity);
}

TextEditingState? _resolveTextEditingUpdate({
  required DrawState state,
  required Set<String> targetIds,
  required ElementStyleUpdate styleUpdate,
  required double? opacity,
  required DrawContext context,
}) {
  final interaction = state.application.interaction;
  if (interaction is! TextEditingState ||
      !targetIds.contains(interaction.elementId)) {
    return null;
  }
  return _applyTextEditingStyleUpdate(
    interaction: interaction,
    styleUpdate: styleUpdate,
    opacity: opacity,
    context: context,
  );
}

TextEditingState? _applyTextEditingStyleUpdate({
  required TextEditingState interaction,
  required ElementStyleUpdate styleUpdate,
  required double? opacity,
  required DrawContext context,
}) {
  final updatedData = styleUpdate.isEmpty
      ? interaction.draftData
      : interaction.draftData.withStyleUpdate(styleUpdate) as TextData;
  final dataChanged = updatedData != interaction.draftData;
  final opacityChanged = opacity != null && opacity != interaction.opacity;

  if (!dataChanged && !opacityChanged) {
    return null;
  }

  final nextRect = dataChanged
      ? _resolveTextRect(
          rect: interaction.rect,
          data: updatedData,
          textMetricsService: context.textMetricsService,
        )
      : interaction.rect;

  return interaction.copyWith(
    draftData: updatedData,
    rect: nextRect,
    opacity: opacityChanged ? opacity : interaction.opacity,
  );
}

bool _shouldRelayoutText(ElementStyleUpdate update) =>
    update.fontSize != null || update.fontFamily != null;

bool _shouldRelayoutSerialNumber(ElementStyleUpdate update) =>
    update.fontSize != null ||
    update.fontFamily != null ||
    update.serialNumber != null;

DrawRect _resolveTextRect({
  required DrawRect rect,
  required TextData data,
  required TextMetricsService textMetricsService,
}) => resolveTextEditingRect(
  origin: DrawPoint(x: rect.minX, y: rect.minY),
  currentRect: rect,
  data: data,
  textMetricsService: textMetricsService,
  allowShrinkHeight: true,
);

DrawRect _resolveSerialNumberRect({
  required DrawRect rect,
  required SerialNumberData data,
  required TextMetricsService textMetricsService,
}) => resolveSerialNumberRect(
  origin: DrawPoint(x: rect.minX, y: rect.minY),
  data: data,
  textMetricsService: textMetricsService,
);

({DrawRect rect, ArrowData data}) _resolveArrowRectAndData({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
}) {
  final sanitizedData = data.copyWith(
    fixedSegments: null,
    startIsSpecial: null,
    endIsSpecial: null,
  );
  if (sanitizedData.arrowType == ArrowType.elbow) {
    final routed = routeElbowArrowForElement(
      element: element,
      data: sanitizedData,
      elementsById: elementsById,
    );
    final geometry = resolveArrowGeometryUpdate(
      localPoints: routed.localPoints,
      oldRect: element.rect,
      rotation: element.rotation,
      arrowType: sanitizedData.arrowType,
    );
    final updatedData = sanitizedData.copyWith(
      points: geometry.normalizedPoints,
    );
    return (rect: geometry.rect, data: updatedData);
  }

  final worldPoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: sanitizedData.points,
  );
  final rect = ArrowGeometry.calculatePathBounds(
    worldPoints: worldPoints,
    arrowType: sanitizedData.arrowType,
  );
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: rect,
  );
  final updatedData = sanitizedData.copyWith(points: normalizedPoints);
  return (rect: rect, data: updatedData);
}
