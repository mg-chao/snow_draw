#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::draw::config::draw_config::{DrawConfig, ElementStyleConfig, ElementStyleConfigPatch};
use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::core::creation_strategy::{
    CreatingState, CreationStrategy, CreationUpdateResult, DrawState as CreationStrategyDrawState,
    ElementData as StrategyElementData, ElementState as CreationElementState,
};
use crate::draw::elements::core::element_data::{
    DynElementData as CoreDynElementData, ElementTypeId,
};
use crate::draw::elements::core::element_registry::{
    DefaultElementRegistry, ElementDefinition as RuntimeElementDefinition,
};
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::services::grid_snap_service::GRID_SNAP_SERVICE;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::TextMetricsService;
use crate::draw::types::snap_guides::snap_guide_list_equals;
use crate::draw::utils::snapping_mode::{resolve_effective_snapping_mode_for_config, SnappingMode};

/// Action payload for starting element creation.
///
/// Mirrors Dart `CreateElement`.
pub struct CreateElement {
    pub type_id: ElementTypeId<CoreDynElementData>,
    pub position: DrawPoint,
    pub initial_data: Option<Arc<dyn StrategyElementData>>,
    pub maintain_aspect_ratio: bool,
    pub create_from_center: bool,
    pub snap_override: bool,
}

impl CreateElement {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        type_id: ElementTypeId<CoreDynElementData>,
        position: DrawPoint,
        initial_data: Option<Arc<dyn StrategyElementData>>,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snap_override: bool,
    ) -> Self {
        Self {
            type_id,
            position,
            initial_data,
            maintain_aspect_ratio,
            create_from_center,
            snap_override,
        }
    }
}

/// Action payload for updating an in-progress creation interaction.
///
/// Mirrors Dart `UpdateCreatingElement`.
pub struct UpdateCreatingElement {
    pub positions: Vec<DrawPoint>,
    pub maintain_aspect_ratio: bool,
    pub create_from_center: bool,
    pub snap_override: bool,
}

impl UpdateCreatingElement {
    pub fn new(
        positions: Vec<DrawPoint>,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snap_override: bool,
    ) -> Self {
        assert!(
            !positions.is_empty(),
            "UpdateCreatingElement.positions must not be empty"
        );
        Self {
            positions,
            maintain_aspect_ratio,
            create_from_center,
            snap_override,
        }
    }

    pub fn current_position(&self) -> DrawPoint {
        self.positions[self.positions.len() - 1]
    }

    pub fn is_batch(&self) -> bool {
        self.positions.len() > 1
    }
}

/// Action payload for confirming one point in point-creation mode.
///
/// Mirrors Dart `AddArrowPoint`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AddArrowPoint {
    pub position: DrawPoint,
    pub snap_override: bool,
}

impl AddArrowPoint {
    pub const fn new(position: DrawPoint, snap_override: bool) -> Self {
        Self {
            position,
            snap_override,
        }
    }
}

/// Action payload for committing the currently creating element.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FinishCreateElement;

/// Action payload for cancelling the currently creating element.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CancelCreateElement;

/// Action surface handled by [`CreateElementReducer`].
pub enum CreateElementReducerAction {
    CreateElement(CreateElement),
    UpdateCreatingElement(UpdateCreatingElement),
    AddArrowPoint(AddArrowPoint),
    FinishCreateElement(FinishCreateElement),
    CancelCreateElement(CancelCreateElement),
    Other,
}

impl Default for CreateElementReducerAction {
    fn default() -> Self {
        Self::Other
    }
}

/// State contract required by [`CreateElementReducer`].
///
/// This trait keeps the reducer compile-friendly and testable while remaining
/// close to the original Dart behavior.
pub trait CreateElementReducerState: Clone {
    fn document_elements(&self) -> &[CreationElementState];

    fn current_creating_state(&self) -> Option<&CreatingState>;

    fn with_creating_state(&self, creating_state: Option<CreatingState>) -> Self;

    fn with_document_elements(&self, elements: Vec<CreationElementState>) -> Self;

    fn clear_selection(&self) -> Self;

    fn warm_document_caches(&self) {}

    fn creation_strategy_state(&self) -> CreationStrategyDrawState {
        CreationStrategyDrawState::default()
    }
}

/// Context contract required by [`CreateElementReducer`].
pub trait CreateElementReducerContext {
    fn draw_config(&self) -> DrawConfig;

    fn next_element_id(&self) -> String;

    fn text_metrics_service(&self) -> Option<Arc<dyn TextMetricsService>>;

    fn element_registry(&self) -> &DefaultElementRegistry;
}

impl CreateElementReducerContext for DrawContext {
    fn draw_config(&self) -> DrawConfig {
        self.config()
    }

    fn next_element_id(&self) -> String {
        self.next_id()
    }

    fn text_metrics_service(&self) -> Option<Arc<dyn TextMetricsService>> {
        Some(Arc::clone(&self.text_metrics_service))
    }

    fn element_registry(&self) -> &DefaultElementRegistry {
        self.element_registry.as_ref()
    }
}

/// Reducer for element creation interactions.
///
/// Handles:
/// - `CreateElement`
/// - `UpdateCreatingElement`
/// - `AddArrowPoint`
/// - `FinishCreateElement`
/// - `CancelCreateElement`
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CreateElementReducer;

impl CreateElementReducer {
    pub const fn new() -> Self {
        Self
    }

    /// Tries to reduce a creation-related action.
    ///
    /// Returns `None` when `action` is not handled by this reducer.
    pub fn reduce<S, C>(
        &self,
        state: &S,
        action: &CreateElementReducerAction,
        context: &C,
    ) -> Option<S>
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
    {
        match action {
            CreateElementReducerAction::CreateElement(action) => {
                Some(self.start_create_element(state, action, context))
            }
            CreateElementReducerAction::UpdateCreatingElement(action) => {
                Some(self.update_creating_element(state, action, context))
            }
            CreateElementReducerAction::AddArrowPoint(action) => {
                Some(self.add_creation_point(state, action, context))
            }
            CreateElementReducerAction::FinishCreateElement(_) => {
                Some(self.finish_create_element(state, context))
            }
            CreateElementReducerAction::CancelCreateElement(_) => {
                Some(self.cancel_create_element(state))
            }
            CreateElementReducerAction::Other => None,
        }
    }

    fn start_create_element<S, C>(&self, state: &S, action: &CreateElement, context: &C) -> S
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
    {
        let config = context.draw_config();
        let definition =
            require_registered_definition(context.element_registry(), action.type_id.as_str());
        let strategy = resolve_creation_strategy_for_definition(definition.as_ref());
        let style_defaults = resolve_style_defaults(state, &config, action.type_id.as_str());
        let data = resolve_initial_data(
            action.initial_data.clone(),
            definition.as_ref(),
            &style_defaults,
        );

        let element_id = context.next_element_id();
        let snapping_mode = resolve_snapping_mode(&config, action.snap_override);
        let start_position = if snapping_mode == SnappingMode::Grid {
            GRID_SNAP_SERVICE.snap_point(action.position, config.grid.size)
        } else {
            action.position
        };
        let initial_rect = DrawRect::from_point(start_position);

        let start_result = strategy.start(data, start_position, context.text_metrics_service());
        let next_z_index = resolve_next_z_index(state.document_elements());

        let new_element = CreationElementState {
            id: element_id,
            type_id_value: action.type_id.as_str().to_owned(),
            rect: initial_rect,
            rotation: 0.0,
            opacity: style_defaults.opacity,
            z_index: next_z_index,
            data: Arc::clone(&start_result.data),
        };

        let cleared_state = state.clear_selection();
        let next_interaction = CreatingState {
            element: new_element,
            start_position,
            current_rect: start_result.rect,
            snap_guides: start_result.snap_guides,
            creation_mode: start_result.creation_mode,
        };

        cleared_state.with_creating_state(Some(next_interaction))
    }

    fn update_creating_element<S, C>(
        &self,
        state: &S,
        action: &UpdateCreatingElement,
        context: &C,
    ) -> S
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
    {
        self.run_creation_update(
            state,
            context,
            action.snap_override,
            |interaction, strategy, snapping_mode, strategy_state, config, text_metrics_service| {
                if action.is_batch() {
                    return Some(strategy.update_batch(
                        strategy_state,
                        config,
                        interaction,
                        action.positions.as_slice(),
                        action.maintain_aspect_ratio,
                        action.create_from_center,
                        snapping_mode,
                        action.snap_override,
                        text_metrics_service,
                    ));
                }

                Some(strategy.update(
                    strategy_state,
                    config,
                    interaction,
                    action.current_position(),
                    action.maintain_aspect_ratio,
                    action.create_from_center,
                    snapping_mode,
                    action.snap_override,
                    text_metrics_service,
                ))
            },
        )
    }

    fn add_creation_point<S, C>(&self, state: &S, action: &AddArrowPoint, context: &C) -> S
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
    {
        self.run_creation_update(
            state,
            context,
            action.snap_override,
            |interaction, strategy, snapping_mode, strategy_state, config, text_metrics_service| {
                strategy.add_point(
                    strategy_state,
                    config,
                    interaction,
                    action.position,
                    snapping_mode,
                    action.snap_override,
                    text_metrics_service,
                )
            },
        )
    }

    fn finish_create_element<S, C>(&self, state: &S, context: &C) -> S
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
    {
        let Some(interaction) = state.current_creating_state().cloned() else {
            return state.clone();
        };

        let strategy = resolve_creation_strategy_for_type(
            context.element_registry(),
            interaction.element.type_id_value.as_str(),
        );
        let config = context.draw_config();
        let strategy_state = state.creation_strategy_state();
        let finish_result = strategy.finish(
            &strategy_state,
            &config,
            &interaction,
            context.text_metrics_service(),
        );
        if !finish_result.should_commit {
            return self.cancel_create_element(state);
        }

        let updated_element = interaction.element.copy_with(
            None,
            Some(finish_result.rect),
            None,
            None,
            Some(resolve_next_z_index(state.document_elements())),
            Some(finish_result.data),
        );

        let mut new_elements = state.document_elements().to_vec();
        new_elements.push(updated_element);
        new_elements = reorder_creation_elements_by_id_order(
            new_elements,
            finish_result.ordered_element_ids.as_deref(),
        );

        let next_state = state
            .with_document_elements(new_elements)
            .with_creating_state(None);
        next_state.warm_document_caches();
        next_state
    }

    fn cancel_create_element<S>(&self, state: &S) -> S
    where
        S: CreateElementReducerState,
    {
        if state.current_creating_state().is_none() {
            return state.clone();
        }

        state.clear_selection().with_creating_state(None)
    }

    fn run_creation_update<S, C, F>(
        &self,
        state: &S,
        context: &C,
        snap_override: bool,
        resolver: F,
    ) -> S
    where
        S: CreateElementReducerState,
        C: CreateElementReducerContext,
        F: FnOnce(
            &CreatingState,
            &dyn CreationStrategy,
            SnappingMode,
            &CreationStrategyDrawState,
            &DrawConfig,
            Option<Arc<dyn TextMetricsService>>,
        ) -> Option<CreationUpdateResult>,
    {
        let Some(interaction) = state.current_creating_state().cloned() else {
            return state.clone();
        };

        let strategy = resolve_creation_strategy_for_type(
            context.element_registry(),
            interaction.element.type_id_value.as_str(),
        );
        let config = context.draw_config();
        let snapping_mode = resolve_snapping_mode(&config, snap_override);
        let strategy_state = state.creation_strategy_state();
        let update_result = resolver(
            &interaction,
            strategy.as_ref(),
            snapping_mode,
            &strategy_state,
            &config,
            context.text_metrics_service(),
        );
        let Some(update_result) = update_result else {
            return state.clone();
        };

        self.apply_creation_update(state, &interaction, update_result)
    }

    fn apply_creation_update<S>(
        &self,
        state: &S,
        interaction: &CreatingState,
        update_result: CreationUpdateResult,
    ) -> S
    where
        S: CreateElementReducerState,
    {
        if is_creation_state_unchanged(interaction, &update_result) {
            return state.clone();
        }

        let next_element = if creation_data_equals(&interaction.element.data, &update_result.data) {
            interaction.element.clone()
        } else {
            interaction
                .element
                .copy_with(None, None, None, None, None, Some(update_result.data))
        };

        let next_interaction = interaction.copy_with(
            Some(next_element),
            None,
            Some(update_result.rect),
            Some(update_result.snap_guides),
            Some(update_result.creation_mode),
        );

        state.with_creating_state(Some(next_interaction))
    }
}

fn reorder_creation_elements_by_id_order(
    elements: Vec<CreationElementState>,
    ordered_element_ids: Option<&[String]>,
) -> Vec<CreationElementState> {
    let Some(ordered_ids) = ordered_element_ids else {
        return elements;
    };
    if ordered_ids.is_empty() || elements.is_empty() || ordered_ids.len() != elements.len() {
        return elements;
    }

    let by_id = elements
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect::<HashMap<_, _>>();
    if by_id.len() != elements.len() {
        return elements;
    }

    let mut seen_ids = HashSet::with_capacity(ordered_ids.len());
    let mut reordered = Vec::with_capacity(elements.len());
    for id in ordered_ids {
        if !seen_ids.insert(id.as_str()) {
            return elements;
        }
        let Some(element) = by_id.get(id) else {
            return elements;
        };
        reordered.push(element.clone());
    }

    let base_z = reordered
        .iter()
        .map(|element| element.z_index)
        .min()
        .unwrap_or(0);
    reordered
        .into_iter()
        .enumerate()
        .map(|(index, element)| {
            element.copy_with(None, None, None, None, Some(base_z + index as i64), None)
        })
        .collect()
}

/// Convenience free function mirroring Dart-style reducer usage.
pub fn create_element_reducer<S, C>(
    state: &S,
    action: &CreateElementReducerAction,
    context: &C,
) -> Option<S>
where
    S: CreateElementReducerState,
    C: CreateElementReducerContext,
{
    CreateElementReducer::new().reduce(state, action, context)
}

fn resolve_style_defaults<S>(
    state: &S,
    config: &DrawConfig,
    type_id_value: &str,
) -> ElementStyleConfig
where
    S: CreateElementReducerState,
{
    match type_id_value {
        RectangleData::TYPE_ID_TOKEN => config.rectangle_style.clone(),
        ArrowData::TYPE_ID_TOKEN => config.arrow_style.clone(),
        LineData::TYPE_ID_TOKEN => config.line_style.clone(),
        FreeDrawData::TYPE_ID_TOKEN => config.free_draw_style.clone(),
        HighlightData::TYPE_ID_TOKEN => config.highlight_style.clone(),
        FilterData::TYPE_ID_TOKEN => config.filter_style.clone(),
        TextData::TYPE_ID_TOKEN => config.text_style.clone(),
        SerialNumberData::TYPE_ID_TOKEN => {
            resolve_serial_number_style_defaults(state, &config.serial_number_style)
        }
        _ => config.element_style.clone(),
    }
}

fn resolve_serial_number_style_defaults<S>(
    state: &S,
    defaults: &ElementStyleConfig,
) -> ElementStyleConfig
where
    S: CreateElementReducerState,
{
    let next_serial_from_document = resolve_next_serial_number(state.document_elements());
    let Some(next_serial_from_document) = next_serial_from_document else {
        return defaults.clone();
    };
    if defaults.serial_number >= next_serial_from_document {
        return defaults.clone();
    }

    defaults.copy_with(ElementStyleConfigPatch {
        serial_number: Some(next_serial_from_document),
        ..ElementStyleConfigPatch::default()
    })
}

fn resolve_initial_data(
    initial_data: Option<Arc<dyn StrategyElementData>>,
    definition: &dyn RuntimeElementDefinition,
    style_defaults: &ElementStyleConfig,
) -> Arc<dyn StrategyElementData> {
    if let Some(initial_data) = initial_data {
        return initial_data;
    }

    definition.create_default_data(style_defaults)
}

fn require_registered_definition<'a>(
    registry: &'a DefaultElementRegistry,
    type_id_value: &str,
) -> &'a Arc<dyn RuntimeElementDefinition> {
    registry
        .get_definition_by_value(type_id_value)
        .unwrap_or_else(|| panic!("Element type \"{type_id_value}\" is not registered"))
}

fn resolve_creation_strategy_for_definition(
    definition: &dyn RuntimeElementDefinition,
) -> Box<dyn CreationStrategy> {
    definition
        .creation_strategy()
        .unwrap_or_else(|| Box::new(RectCreationStrategy::new()))
}

fn resolve_creation_strategy_for_type(
    registry: &DefaultElementRegistry,
    type_id_value: &str,
) -> Box<dyn CreationStrategy> {
    let definition = require_registered_definition(registry, type_id_value);
    resolve_creation_strategy_for_definition(definition.as_ref())
}

fn resolve_snapping_mode(config: &DrawConfig, snap_override: bool) -> SnappingMode {
    resolve_effective_snapping_mode_for_config(config, snap_override)
}

fn resolve_next_z_index(elements: &[CreationElementState]) -> i64 {
    elements
        .iter()
        .map(|element| element.z_index)
        .max()
        .unwrap_or(-1)
        + 1
}

fn resolve_next_serial_number(elements: &[CreationElementState]) -> Option<i64> {
    let mut max_serial: Option<i64> = None;
    for element in elements {
        let Some(serial_data) = element
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<SerialNumberData>()
        else {
            continue;
        };

        if max_serial.is_none() || serial_data.number > max_serial.unwrap_or(i64::MIN) {
            max_serial = Some(serial_data.number);
        }
    }

    max_serial.map(|value| value + 1)
}

fn is_creation_state_unchanged(
    interaction: &CreatingState,
    update_result: &CreationUpdateResult,
) -> bool {
    creation_data_equals(&interaction.element.data, &update_result.data)
        && interaction.current_rect == update_result.rect
        && interaction.creation_mode == update_result.creation_mode
        && snap_guide_list_equals(&interaction.snap_guides, &update_result.snap_guides)
}

fn creation_data_equals(
    left: &Arc<dyn StrategyElementData>,
    right: &Arc<dyn StrategyElementData>,
) -> bool {
    if Arc::ptr_eq(left, right) {
        return true;
    }

    data_eq_as::<RectangleData>(left, right)
        || data_eq_as::<ArrowData>(left, right)
        || data_eq_as::<LineData>(left, right)
        || data_eq_as::<FreeDrawData>(left, right)
        || data_eq_as::<HighlightData>(left, right)
        || data_eq_as::<FilterData>(left, right)
        || data_eq_as::<TextData>(left, right)
        || data_eq_as::<SerialNumberData>(left, right)
}

fn data_eq_as<T>(left: &Arc<dyn StrategyElementData>, right: &Arc<dyn StrategyElementData>) -> bool
where
    T: PartialEq + 'static,
{
    let Some(left_value) = left.as_ref().as_any().downcast_ref::<T>() else {
        return false;
    };
    let Some(right_value) = right.as_ref().as_any().downcast_ref::<T>() else {
        return false;
    };
    left_value == right_value
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[derive(Clone, Debug, Default)]
    struct TestState {
        elements: Vec<CreationElementState>,
        creating: Option<CreatingState>,
    }

    impl CreateElementReducerState for TestState {
        fn document_elements(&self) -> &[CreationElementState] {
            self.elements.as_slice()
        }

        fn current_creating_state(&self) -> Option<&CreatingState> {
            self.creating.as_ref()
        }

        fn with_creating_state(&self, creating_state: Option<CreatingState>) -> Self {
            Self {
                elements: self.elements.clone(),
                creating: creating_state,
            }
        }

        fn with_document_elements(&self, elements: Vec<CreationElementState>) -> Self {
            Self {
                elements,
                creating: self.creating.clone(),
            }
        }

        fn clear_selection(&self) -> Self {
            self.clone()
        }
    }

    #[derive(Clone)]
    struct TestContext {
        config: DrawConfig,
        next_id: Arc<Mutex<i64>>,
        registry: DefaultElementRegistry,
    }

    impl TestContext {
        fn new(config: DrawConfig) -> Self {
            Self {
                config,
                next_id: Arc::new(Mutex::new(0)),
                registry: crate::draw::elements::registration::resolve_element_registry(None)
                    .expect("test context should resolve built-in element registry"),
            }
        }
    }

    impl CreateElementReducerContext for TestContext {
        fn draw_config(&self) -> DrawConfig {
            self.config.clone()
        }

        fn next_element_id(&self) -> String {
            let mut next = self.next_id.lock().expect("next id mutex poisoned");
            *next += 1;
            format!("e-{}", *next)
        }

        fn text_metrics_service(&self) -> Option<Arc<dyn TextMetricsService>> {
            None
        }

        fn element_registry(&self) -> &DefaultElementRegistry {
            &self.registry
        }
    }

    #[test]
    fn non_creation_action_returns_none() {
        let reducer = CreateElementReducer::new();
        let state = TestState::default();
        let context = TestContext::new(DrawConfig::default());

        let next = reducer.reduce(&state, &CreateElementReducerAction::Other, &context);

        assert!(next.is_none());
    }

    #[test]
    fn start_create_sets_creating_state() {
        let reducer = CreateElementReducer::new();
        let state = TestState::default();
        let context = TestContext::new(DrawConfig::default());
        let action = CreateElement::new(
            ElementTypeId::new(RectangleData::TYPE_ID_TOKEN),
            DrawPoint::new(10.0, 12.0),
            None,
            false,
            false,
            false,
        );

        let next = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::CreateElement(action),
                &context,
            )
            .expect("create action should be handled");

        assert!(next.current_creating_state().is_some());
        assert_eq!(next.document_elements().len(), 0);
    }

    #[test]
    fn finish_create_without_valid_size_cancels_creation() {
        let reducer = CreateElementReducer::new();
        let context = TestContext::new(DrawConfig::default());
        let start_action = CreateElement::new(
            ElementTypeId::new(RectangleData::TYPE_ID_TOKEN),
            DrawPoint::new(10.0, 12.0),
            None,
            false,
            false,
            false,
        );
        let state = reducer
            .reduce(
                &TestState::default(),
                &CreateElementReducerAction::CreateElement(start_action),
                &context,
            )
            .expect("create action should be handled");

        let finished = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::FinishCreateElement(FinishCreateElement),
                &context,
            )
            .expect("finish action should be handled");

        assert!(finished.current_creating_state().is_none());
        assert!(finished.document_elements().is_empty());
    }

    #[test]
    fn update_then_finish_commits_element() {
        let reducer = CreateElementReducer::new();
        let context = TestContext::new(DrawConfig::default());
        let create_action = CreateElement::new(
            ElementTypeId::new(RectangleData::TYPE_ID_TOKEN),
            DrawPoint::new(0.0, 0.0),
            None,
            false,
            false,
            false,
        );
        let state = reducer
            .reduce(
                &TestState::default(),
                &CreateElementReducerAction::CreateElement(create_action),
                &context,
            )
            .expect("create action should be handled");
        let update_action =
            UpdateCreatingElement::new(vec![DrawPoint::new(30.0, 30.0)], false, false, false);
        let updated = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::UpdateCreatingElement(update_action),
                &context,
            )
            .expect("update action should be handled");

        let finished = reducer
            .reduce(
                &updated,
                &CreateElementReducerAction::FinishCreateElement(FinishCreateElement),
                &context,
            )
            .expect("finish action should be handled");

        assert!(finished.current_creating_state().is_none());
        assert_eq!(finished.document_elements().len(), 1);
    }

    #[test]
    fn arrow_creation_uses_domain_arrow_data_type() {
        let reducer = CreateElementReducer::new();
        let context = TestContext::new(DrawConfig::default());
        let create_action = CreateElement::new(
            ElementTypeId::new(ArrowData::TYPE_ID_TOKEN),
            DrawPoint::new(0.0, 0.0),
            None,
            false,
            false,
            false,
        );
        let state = reducer
            .reduce(
                &TestState::default(),
                &CreateElementReducerAction::CreateElement(create_action),
                &context,
            )
            .expect("create action should be handled");
        let updated = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::UpdateCreatingElement(UpdateCreatingElement::new(
                    vec![DrawPoint::new(40.0, 20.0)],
                    false,
                    false,
                    false,
                )),
                &context,
            )
            .expect("update action should be handled");
        let finished = reducer
            .reduce(
                &updated,
                &CreateElementReducerAction::FinishCreateElement(FinishCreateElement),
                &context,
            )
            .expect("finish action should be handled");

        assert_eq!(finished.document_elements().len(), 1);
        let element = &finished.document_elements()[0];
        assert!(element.data.as_ref().as_any().is::<ArrowData>());
    }

    #[test]
    fn free_draw_creation_uses_domain_free_draw_data_type() {
        let reducer = CreateElementReducer::new();
        let context = TestContext::new(DrawConfig::default());
        let create_action = CreateElement::new(
            ElementTypeId::new(FreeDrawData::TYPE_ID_TOKEN),
            DrawPoint::new(0.0, 0.0),
            None,
            false,
            false,
            false,
        );
        let state = reducer
            .reduce(
                &TestState::default(),
                &CreateElementReducerAction::CreateElement(create_action),
                &context,
            )
            .expect("create action should be handled");
        let updated = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::UpdateCreatingElement(UpdateCreatingElement::new(
                    vec![
                        DrawPoint::new(12.0, 4.0),
                        DrawPoint::new(24.0, 8.0),
                        DrawPoint::new(36.0, 14.0),
                    ],
                    false,
                    false,
                    false,
                )),
                &context,
            )
            .expect("update action should be handled");
        let finished = reducer
            .reduce(
                &updated,
                &CreateElementReducerAction::FinishCreateElement(FinishCreateElement),
                &context,
            )
            .expect("finish action should be handled");

        assert_eq!(finished.document_elements().len(), 1);
        let element = &finished.document_elements()[0];
        assert!(element.data.as_ref().as_any().is::<FreeDrawData>());
    }

    #[test]
    fn serial_number_creation_uses_domain_serial_number_data_type() {
        let reducer = CreateElementReducer::new();
        let context = TestContext::new(DrawConfig::default());
        let create_action = CreateElement::new(
            ElementTypeId::new(SerialNumberData::TYPE_ID_TOKEN),
            DrawPoint::new(50.0, 50.0),
            None,
            false,
            false,
            false,
        );
        let state = reducer
            .reduce(
                &TestState::default(),
                &CreateElementReducerAction::CreateElement(create_action),
                &context,
            )
            .expect("create action should be handled");
        let updated = reducer
            .reduce(
                &state,
                &CreateElementReducerAction::UpdateCreatingElement(UpdateCreatingElement::new(
                    vec![DrawPoint::new(90.0, 90.0)],
                    false,
                    false,
                    false,
                )),
                &context,
            )
            .expect("update action should be handled");
        let finished = reducer
            .reduce(
                &updated,
                &CreateElementReducerAction::FinishCreateElement(FinishCreateElement),
                &context,
            )
            .expect("finish action should be handled");

        assert_eq!(finished.document_elements().len(), 1);
        let element = &finished.document_elements()[0];
        assert!(element.data.as_ref().as_any().is::<SerialNumberData>());
    }
}
