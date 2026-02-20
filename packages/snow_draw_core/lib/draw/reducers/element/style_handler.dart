import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
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
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/element_style.dart';
import '../core/reducer_utils.dart';

DrawState handleUpdateElementsStyle(
  DrawState state,
  UpdateElementsStyle action,
  ElementReducerDeps _,
) {
  final targetIds = action.elementIds.toSet();
  if (targetIds.isEmpty) {
    return state;
  }

  final styleUpdate = ElementStyleUpdate(
    color: action.color,
    fillColor: action.fillColor,
    strokeWidth: action.strokeWidth,
    strokeStyle: action.strokeStyle,
    fillStyle: action.fillStyle,
    filterType: action.filterType,
    filterStrength: action.filterStrength,
    cornerRadius: action.cornerRadius,
    arrowType: action.arrowType,
    startArrowhead: action.startArrowhead,
    endArrowhead: action.endArrowhead,
    fontSize: action.fontSize,
    fontFamily: action.fontFamily,
    textAlign: action.textAlign,
    verticalAlign: action.verticalAlign,
    textStrokeColor: action.textStrokeColor,
    textStrokeWidth: action.textStrokeWidth,
    highlightShape: action.highlightShape,
    serialNumber: action.serialNumber,
  );

  final document = state.domain.document;
  final selectedIds = state.domain.selection.selectedIds;
  final trackSelectionOverlay = selectedIds.length > 1;
  var domainChanged = false;
  var selectionGeometryChanged = false;
  List<ElementState>? nextElements;

  for (final id in targetIds) {
    final orderIndex = document.getOrderIndex(id);
    if (orderIndex == null) {
      continue;
    }
    final element = document.elements[orderIndex];
    final update = _resolveElementStyleUpdate(
      element: element,
      styleUpdate: styleUpdate,
      opacity: action.opacity,
      trackGeometryChange: trackSelectionOverlay && selectedIds.contains(id),
      elementsById: document.elementMap,
    );
    if (update == null) {
      continue;
    }
    domainChanged = true;
    nextElements ??= [...document.elements];
    nextElements[orderIndex] = update.element;
    if (update.geometryChanged) {
      selectionGeometryChanged = true;
    }
  }

  final interaction = state.application.interaction;
  final nextTextEdit =
      interaction is TextEditingState &&
          targetIds.contains(interaction.elementId)
      ? _applyTextEditingStyleUpdate(interaction, styleUpdate, action.opacity)
      : null;
  final interactionChanged = nextTextEdit != null;

  if (!domainChanged && !interactionChanged) {
    return state;
  }

  final nextDomain = domainChanged
      ? state.domain.copyWith(
          document: document.copyWith(elements: nextElements),
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
}) {
  var next = element;
  var changed = false;
  var geometryChanged = false;
  final data = next.data;

  if (!styleUpdate.isEmpty && data is ElementStyleUpdatableData) {
    final updatedData = (data as ElementStyleUpdatableData).withStyleUpdate(
      styleUpdate,
    );
    if (updatedData != data) {
      next = next.copyWith(data: updatedData);
      changed = true;
      switch ((data, updatedData)) {
        case (TextData _, final TextData updatedTextData)
            when _shouldRelayoutText(styleUpdate):
          final nextRect = resolveTextEditingRect(
            origin: DrawPoint(x: next.rect.minX, y: next.rect.minY),
            currentRect: next.rect,
            data: updatedTextData,
            allowShrinkHeight: true,
          );
          if (nextRect != next.rect) {
            geometryChanged = trackGeometryChange;
            next = next.copyWith(rect: nextRect);
          }
        case (
              SerialNumberData _,
              final SerialNumberData updatedSerialNumberData,
            )
            when _shouldRelayoutSerialNumber(styleUpdate):
          final nextRect = resolveSerialNumberRect(
            origin: DrawPoint(x: next.rect.minX, y: next.rect.minY),
            data: updatedSerialNumberData,
          );
          if (nextRect != next.rect) {
            geometryChanged = trackGeometryChange;
            next = next.copyWith(rect: nextRect);
          }
        case (
              final ArrowData previousArrowData,
              final ArrowData updatedArrowData,
            )
            when previousArrowData.arrowType != updatedArrowData.arrowType:
          final result = _resolveArrowRectAndData(
            element: next,
            data: updatedArrowData,
            elementsById: elementsById,
          );
          if (result.rect != next.rect && trackGeometryChange) {
            geometryChanged = true;
          }
          next = next.copyWith(rect: result.rect, data: result.data);
        case _:
      }
    }
  }

  if (opacity != null && opacity != element.opacity) {
    next = next.copyWith(opacity: opacity);
    changed = true;
  }

  if (!changed) {
    return null;
  }

  return (element: next, geometryChanged: geometryChanged);
}

TextEditingState? _applyTextEditingStyleUpdate(
  TextEditingState interaction,
  ElementStyleUpdate styleUpdate,
  double? opacity,
) {
  final updatedData = styleUpdate.isEmpty
      ? interaction.draftData
      : interaction.draftData.withStyleUpdate(styleUpdate) as TextData;
  final dataChanged = updatedData != interaction.draftData;
  final opacityChanged = opacity != null && opacity != interaction.opacity;

  if (!dataChanged && !opacityChanged) {
    return null;
  }

  final nextRect = dataChanged
      ? resolveTextEditingRect(
          origin: DrawPoint(x: interaction.rect.minX, y: interaction.rect.minY),
          currentRect: interaction.rect,
          data: updatedData,
          allowShrinkHeight: true,
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

({DrawRect rect, ArrowData data}) _resolveArrowRectAndData({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
}) {
  if (data.arrowType == ArrowType.elbow) {
    final elbowData = data.copyWith(
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );
    final routed = routeElbowArrowForElement(
      element: element,
      data: elbowData,
      elementsById: elementsById,
    );
    final result = computeArrowRectAndPoints(
      localPoints: routed.localPoints,
      oldRect: element.rect,
      rotation: element.rotation,
      arrowType: data.arrowType,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );
    final updatedData = elbowData.copyWith(points: normalized);
    return (rect: result.rect, data: updatedData);
  }

  final sanitizedData = data.copyWith(
    fixedSegments: null,
    startIsSpecial: null,
    endIsSpecial: null,
  );

  final worldPoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: sanitizedData.points,
  ).map((offset) => DrawPoint(x: offset.dx, y: offset.dy)).toList();

  final newRect = ArrowGeometry.calculatePathBounds(
    worldPoints: worldPoints,
    arrowType: data.arrowType,
  );

  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: newRect,
  );

  final updatedData = sanitizedData.copyWith(points: normalizedPoints);

  return (rect: newRect, data: updatedData);
}
