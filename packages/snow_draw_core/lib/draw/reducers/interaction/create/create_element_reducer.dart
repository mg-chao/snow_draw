import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../config/draw_config.dart';
import '../../../core/dependency_interfaces.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
import '../../../elements/core/element_definition.dart';
import '../../../elements/core/element_style_configurable_data.dart';
import '../../../elements/core/element_type_id.dart';
import '../../../elements/core/rect_creation_strategy.dart';
import '../../../elements/types/arrow/arrow_data.dart';
import '../../../elements/types/filter/filter_data.dart';
import '../../../elements/types/free_draw/free_draw_data.dart';
import '../../../elements/types/highlight/highlight_data.dart';
import '../../../elements/types/line/line_data.dart';
import '../../../elements/types/rectangle/rectangle_data.dart';
import '../../../elements/types/serial_number/serial_number_data.dart';
import '../../../elements/types/serial_number/serial_number_sequence.dart';
import '../../../elements/types/text/text_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/grid_snap_service.dart';
import '../../../types/draw_rect.dart';
import '../../../types/snap_guides.dart';
import '../../../utils/snapping_mode.dart';
import '../../core/reducer_utils.dart';

/// Reducer for element creation.
///
/// Handles: CreateElement, UpdateCreatingElement,
/// UpdateCreatingElementBatch, FinishCreateElement, CancelCreateElement.
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
    final UpdateCreatingElementBatch a => _updateCreatingElementBatch(
      state,
      a,
      context,
    ),
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
    final definition = _requireDefinition(context, action.typeId);
    final strategy =
        definition.creationStrategy ?? const RectCreationStrategy();
    final styleDefaults = _resolveStyleDefaults(state, config, action.typeId);
    final data = _resolveInitialData(
      initialData: action.initialData,
      createDefaultData: definition.createDefaultData,
      styleDefaults: styleDefaults,
    );

    final elementId = context.idGenerator();
    final gridConfig = config.grid;
    final snappingMode = _resolveSnappingMode(
      config: config,
      snapOverride: action.snapOverride,
    );
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: action.position,
            gridSize: gridConfig.size,
          )
        : action.position;
    final initialRect = DrawRect.fromPoint(startPosition);

    final startResult = strategy.start(
      data: data,
      startPosition: startPosition,
      textMetricsService: context.textMetricsService,
    );
    final nextZIndex = resolveNextZIndex(state.domain.document.elements);

    final newElement = ElementState(
      id: elementId,
      rect: initialRect,
      rotation: 0,
      opacity: styleDefaults.opacity,
      zIndex: nextZIndex,
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

  ElementDefinition<ElementData> _requireDefinition(
    CreateElementReducerDeps context,
    ElementTypeId<ElementData> typeId,
  ) {
    final definition = context.elementRegistry.getDefinition(typeId);
    if (definition == null) {
      throw StateError('Element type "$typeId" is not registered');
    }
    return definition;
  }

  ElementData _resolveInitialData({
    required ElementData? initialData,
    required ElementData Function() createDefaultData,
    required ElementStyleConfig styleDefaults,
  }) {
    if (initialData != null) {
      return initialData;
    }

    final defaultData = createDefaultData();
    if (defaultData is ElementStyleConfigurableData) {
      return (defaultData as ElementStyleConfigurableData).withElementStyle(
        styleDefaults,
      );
    }
    return defaultData;
  }

  ElementStyleConfig _resolveStyleDefaults(
    DrawState state,
    DrawConfig config,
    ElementTypeId<ElementData> typeId,
  ) => switch (typeId) {
    _ when typeId == RectangleData.typeIdToken => config.rectangleStyle,
    _ when typeId == ArrowData.typeIdToken => config.arrowStyle,
    _ when typeId == LineData.typeIdToken => config.lineStyle,
    _ when typeId == FreeDrawData.typeIdToken => config.freeDrawStyle,
    _ when typeId == HighlightData.typeIdToken => config.highlightStyle,
    _ when typeId == FilterData.typeIdToken => config.filterStyle,
    _ when typeId == TextData.typeIdToken => config.textStyle,
    _ when typeId == SerialNumberData.typeIdToken =>
      _resolveSerialNumberStyleDefaults(state, config.serialNumberStyle),
    _ => config.elementStyle,
  };

  ElementStyleConfig _resolveSerialNumberStyleDefaults(
    DrawState state,
    ElementStyleConfig defaults,
  ) {
    final nextSerialFromDocument = resolveNextSerialNumber(
      state.domain.document.elements,
    );
    if (nextSerialFromDocument == null) {
      return defaults;
    }
    if (defaults.serialNumber >= nextSerialFromDocument) {
      return defaults;
    }
    return defaults.copyWith(serialNumber: nextSerialFromDocument);
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
    final snappingMode = _resolveSnappingMode(
      config: context.config,
      snapOverride: action.snapOverride,
    );
    final updateResult = strategy.update(
      state: state,
      config: context.config,
      creatingState: interaction,
      currentPosition: action.currentPosition,
      maintainAspectRatio: action.maintainAspectRatio,
      createFromCenter: action.createFromCenter,
      snappingMode: snappingMode,
      textMetricsService: context.textMetricsService,
    );
    return _applyCreationUpdate(state, interaction, updateResult);
  }

  DrawState _updateCreatingElementBatch(
    DrawState state,
    UpdateCreatingElementBatch action,
    CreateElementReducerDeps context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState || action.positions.isEmpty) {
      return state;
    }

    final strategy = _resolveCreationStrategy(
      context,
      interaction.element.typeId,
    );
    final snappingMode = _resolveSnappingMode(
      config: context.config,
      snapOverride: action.snapOverride,
    );
    final updateResult = strategy.updateBatch(
      state: state,
      config: context.config,
      creatingState: interaction,
      positions: action.positions,
      maintainAspectRatio: action.maintainAspectRatio,
      createFromCenter: action.createFromCenter,
      snappingMode: snappingMode,
      textMetricsService: context.textMetricsService,
    );
    return _applyCreationUpdate(state, interaction, updateResult);
  }

  DrawState _finishCreateElement(
    DrawState state,
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
    final finishResult = strategy.finish(
      config: context.config,
      creatingState: interaction,
      textMetricsService: context.textMetricsService,
    );
    if (!finishResult.shouldCommit) {
      return _cancelCreateElement(state);
    }

    final updatedElement = interaction.element.copyWith(
      rect: finishResult.rect,
      data: finishResult.data,
      zIndex: resolveNextZIndex(state.domain.document.elements),
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
      return state;
    }

    final clearedState = applySelectionChange(state, const {});
    return clearedState.copyWith(
      application: clearedState.application.toIdle(),
    );
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
    final snappingMode = _resolveSnappingMode(
      config: context.config,
      snapOverride: action.snapOverride,
    );
    final updateResult = strategy.addPoint(
      state: state,
      config: context.config,
      creatingState: interaction,
      position: action.position,
      snappingMode: snappingMode,
      textMetricsService: context.textMetricsService,
    );
    if (updateResult == null) {
      return state;
    }
    return _applyCreationUpdate(state, interaction, updateResult);
  }

  CreationStrategy _resolveCreationStrategy(
    CreateElementReducerDeps context,
    ElementTypeId<ElementData> typeId,
  ) =>
      _requireDefinition(context, typeId).creationStrategy ??
      const RectCreationStrategy();

  SnappingMode _resolveSnappingMode({
    required DrawConfig config,
    required bool snapOverride,
  }) => resolveEffectiveSnappingModeForConfig(
    config: config,
    ctrlPressed: snapOverride,
  );

  DrawState _applyCreationUpdate(
    DrawState state,
    CreatingState interaction,
    CreationUpdateResult updateResult,
  ) {
    if (_isCreationStateUnchanged(interaction, updateResult)) {
      return state;
    }

    final nextElement = updateResult.data == interaction.elementData
        ? interaction.element
        : interaction.element.copyWith(data: updateResult.data);
    final nextInteraction = interaction.copyWith(
      element: nextElement,
      currentRect: updateResult.rect,
      snapGuides: updateResult.snapGuides,
      creationMode: updateResult.creationMode,
    );
    return state.copyWith(
      application: state.application.copyWith(interaction: nextInteraction),
    );
  }

  bool _isCreationStateUnchanged(
    CreatingState interaction,
    CreationUpdateResult updateResult,
  ) =>
      interaction.elementData == updateResult.data &&
      interaction.currentRect == updateResult.rect &&
      interaction.creationMode == updateResult.creationMode &&
      snapGuideListEquals(interaction.snapGuides, updateResult.snapGuides);
}
