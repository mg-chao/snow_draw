import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../config/draw_config.dart';
import '../../../core/dependency_interfaces.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
import '../../../elements/core/element_style_configurable_data.dart';
import '../../../elements/core/element_type_id.dart';
import '../../../elements/core/rect_creation_strategy.dart';
import '../../../elements/types/arrow/arrow_data.dart';
import '../../../elements/types/free_draw/free_draw_data.dart';
import '../../../elements/types/highlight/highlight_data.dart';
import '../../../elements/types/line/line_data.dart';
import '../../../elements/types/rectangle/rectangle_data.dart';
import '../../../elements/types/serial_number/serial_number_data.dart';
import '../../../elements/types/text/text_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/grid_snap_service.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/snapping_mode.dart';
import '../../core/reducer_utils.dart';

/// Reducer for element creation.
///
/// Handles: CreateElement, UpdateCreatingElement, FinishCreateElement,
/// CancelCreateElement.
@immutable
class CreateElementReducer {
  const CreateElementReducer();

  /// Try to handle element creation actions.
  ///
  /// Returns null if the action is not a creation operation.
  DrawState? reduce(
    DrawState state,
    DrawAction action,
    CreateElementReducerDeps context,
  ) => switch (action) {
    final CreateElement a => _startCreateElement(state, a, context),
    final UpdateCreatingElement a => _updateCreatingElement(state, a, context),
    final AddArrowPoint a => _addCreationPoint(state, a, context),
    FinishCreateElement _ => _finishCreateElement(state, context),
    CancelCreateElement _ => _cancelCreateElement(state),
    _ => null,
  };

  DrawState _startCreateElement(
    DrawState state,
    CreateElement action,
    CreateElementReducerDeps context,
  ) {
    final config = context.config;
    final definition = context.elementRegistry.getDefinition(action.typeId);
    if (definition == null) {
      throw StateError('Element type "${action.typeId}" is not registered');
    }

    final strategy =
        definition.creationStrategy ?? const RectCreationStrategy();
    final styleDefaults = _resolveStyleDefaults(config, action.typeId);
    var data = action.initialData ?? definition.createDefaultData();
    if (action.initialData == null && data is ElementStyleConfigurableData) {
      data = (data as ElementStyleConfigurableData).withElementStyle(
        styleDefaults,
      );
    }

    final elementId = context.idGenerator();
    final gridConfig = config.grid;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: action.snapOverride,
    );
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: action.position,
            gridSize: gridConfig.size,
          )
        : action.position;
    final initialRect = DrawRect(
      minX: startPosition.x,
      minY: startPosition.y,
      maxX: startPosition.x,
      maxY: startPosition.y,
    );

    final startResult = strategy.start(
      data: data,
      startPosition: startPosition,
    );

    final newElement = ElementState(
      id: elementId,
      rect: initialRect,
      rotation: 0,
      opacity: styleDefaults.opacity,
      zIndex: state.domain.document.elements.length,
      data: startResult.data,
    );

    final clearedState = applySelectionChange(state, const {});
    final nextInteraction = CreatingState(
      element: newElement,
      startPosition: startPosition,
      currentRect: startResult.rect,
      snapGuides: startResult.snapGuides,
      creationMode: startResult.creationMode,
    );
    final nextApplication = clearedState.application.copyWith(
      interaction: nextInteraction,
    );
    return clearedState.copyWith(application: nextApplication);
  }

  ElementStyleConfig _resolveStyleDefaults(
    DrawConfig config,
    ElementTypeId<ElementData> typeId,
  ) {
    if (typeId == RectangleData.typeIdToken) {
      return config.rectangleStyle;
    }
    if (typeId == ArrowData.typeIdToken) {
      return config.arrowStyle;
    }
    if (typeId == LineData.typeIdToken) {
      return config.lineStyle;
    }
    if (typeId == FreeDrawData.typeIdToken) {
      return config.freeDrawStyle;
    }
    if (typeId == HighlightData.typeIdToken) {
      return config.highlightStyle;
    }
    if (typeId == TextData.typeIdToken) {
      return config.textStyle;
    }
    if (typeId == SerialNumberData.typeIdToken) {
      return config.serialNumberStyle;
    }
    return config.elementStyle;
  }

  DrawState _updateCreatingElement(
    DrawState state,
    UpdateCreatingElement action,
    CreateElementReducerDeps context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state;
    }

    final strategy = _resolveCreationStrategy(
      context,
      interaction.element.typeId,
    );
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: context.config,
      ctrlPressed: action.snapOverride,
    );
    final updateResult = strategy.update(
      state: state,
      config: context.config,
      creatingState: interaction,
      currentPosition: action.currentPosition,
      maintainAspectRatio: action.maintainAspectRatio,
      createFromCenter: action.createFromCenter,
      snappingMode: snappingMode,
    );
    final updatedElement = interaction.element.copyWith(
      data: updateResult.data,
    );
    final nextInteraction = interaction.copyWith(
      element: updatedElement,
      currentRect: updateResult.rect,
      snapGuides: updateResult.snapGuides,
      creationMode: updateResult.creationMode,
    );
    return state.copyWith(
      application: state.application.copyWith(interaction: nextInteraction),
    );
  }

  DrawState _finishCreateElement(
    DrawState state,
    CreateElementReducerDeps context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state.copyWith(application: state.application.toIdle());
    }

    final strategy = _resolveCreationStrategy(
      context,
      interaction.element.typeId,
    );
    final finishResult = strategy.finish(
      config: context.config,
      creatingState: interaction,
    );
    if (!finishResult.shouldCommit) {
      return _cancelCreateElement(state);
    }

    final updatedElement = interaction.element.copyWith(
      rect: finishResult.rect,
      data: finishResult.data,
      zIndex: state.domain.document.elements.length,
    );
    final newElements = [...state.domain.document.elements, updatedElement];

    final nextState = state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(elements: newElements),
      ),
      application: state.application.toIdle(),
    );
    nextState.domain.document.warmCaches();
    return nextState;
  }

  DrawState _cancelCreateElement(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state.copyWith(application: state.application.toIdle());
    }

    final clearedState = applySelectionChange(state, const {});
    final nextApplication = clearedState.application.copyWith(
      interaction: const IdleState(),
    );
    return clearedState.copyWith(application: nextApplication);
  }

  DrawState _addCreationPoint(
    DrawState state,
    AddArrowPoint action,
    CreateElementReducerDeps context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state;
    }

    final strategy = _resolveCreationStrategy(
      context,
      interaction.element.typeId,
    );
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: context.config,
      ctrlPressed: action.snapOverride,
    );
    final updateResult = strategy.addPoint(
      state: state,
      config: context.config,
      creatingState: interaction,
      position: action.position,
      snappingMode: snappingMode,
    );
    if (updateResult == null) {
      return state;
    }
    final updatedElement = interaction.element.copyWith(
      data: updateResult.data,
    );
    final nextInteraction = interaction.copyWith(
      element: updatedElement,
      currentRect: updateResult.rect,
      snapGuides: updateResult.snapGuides,
      creationMode: updateResult.creationMode,
    );
    return state.copyWith(
      application: state.application.copyWith(interaction: nextInteraction),
    );
  }

  CreationStrategy _resolveCreationStrategy(
    CreateElementReducerDeps context,
    ElementTypeId<ElementData> typeId,
  ) {
    final definition = context.elementRegistry.getDefinition(typeId);
    return definition?.creationStrategy ?? const RectCreationStrategy();
  }
}
