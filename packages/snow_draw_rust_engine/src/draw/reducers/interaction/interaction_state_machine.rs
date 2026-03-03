#![allow(dead_code)]

use std::collections::BTreeSet;
use std::fmt;
use std::sync::Arc;

use crate::draw::actions::draw_actions as actions;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::core::edit_session_id_generator::EditSessionIdGenerator;
use crate::draw::edit::core::edit_session_service::EditSessionService;
use crate::draw::elements::core::creation_strategy::{
    CreatingState as StrategyCreatingState, CreationMode as StrategyCreationMode,
    DrawState as CreationStrategyDrawState, ElementData as StrategyElementData,
    ElementState as StrategyElementState, PointCreationMode as StrategyPointCreationMode,
};
use crate::draw::elements::core::element_data::{
    DynElementData, ElementData as CoreElementData, ElementTypeId,
};
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::application_state::{
    ApplicationState, IdleState, InteractionState, ViewState,
};
use crate::draw::models::draw_state::{DomainDocumentState, DomainState, DrawState};
use crate::draw::models::interaction_state::{
    BoxSelectingState, CreatingState as ModelCreatingState, CreationMode as ModelCreationMode,
    DragPendingState, PointCreationMode as ModelPointCreationMode, RectCreationMode,
    TextEditingState,
};
use crate::draw::models::selection_state::SelectionState;
use crate::draw::reducers::camera::camera_reducer;
use crate::draw::reducers::core::reducer_utils::apply_selection_change;
use crate::draw::reducers::element::element_reducer;
use crate::draw::reducers::interaction::create::create_element_reducer;
use crate::draw::reducers::interaction::edit::edit_state_reducer;
use crate::draw::reducers::interaction::interaction_transition::InteractionTransition;
use crate::draw::reducers::interaction::selection::box_select_reducer;
use crate::draw::reducers::interaction::selection::pending_state_reducer;
use crate::draw::reducers::interaction::text::text_edit_reducer;
use crate::draw::reducers::selection::selection_reducer;
use crate::draw::store::middleware::middleware_context::DispatchAction;
use crate::draw::types::draw_rect::DrawRect;

/// Interaction state machine - coordinates sub-reducers.
///
/// Responsibilities:
/// 1. Dispatch actions to sub-reducers in priority order.
/// 2. Coordinate state transitions across subsystems.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct InteractionStateMachine;

impl InteractionStateMachine {
    pub const fn new() -> Self {
        Self
    }

    /// Single entry point for all interaction actions.
    pub fn reduce(
        &self,
        state: DrawState,
        action: &DispatchAction,
        context: &DrawContext,
        edit_session_service: &EditSessionService,
        session_id_generator: &EditSessionIdGenerator,
    ) -> InteractionTransition {
        let edit_action = map_edit_action(action);
        if let Some(edit_result) = edit_state_reducer::reduce_edit_state(
            &state,
            &edit_action,
            edit_session_service,
            session_id_generator,
        ) {
            return InteractionTransition::new(edit_result.next_state);
        }

        if let Some(reduced) = self.reduce_state(&state, action, context) {
            return InteractionTransition::new(reduced);
        }

        InteractionTransition::unchanged(state)
    }

    /// Handles non-edit actions (state only).
    ///
    /// Reducers are evaluated in order and the first non-`None` result wins.
    pub fn reduce_state(
        &self,
        state: &DrawState,
        action: &DispatchAction,
        context: &DrawContext,
    ) -> Option<DrawState> {
        let pending_action = map_pending_action(action);
        pending_state_reducer::pending_state_reducer(state, &pending_action)
            .or_else(|| {
                box_select_reducer::BoxSelectReducer::new()
                    .reduce(state, &map_box_select_action(action))
            })
            .or_else(|| {
                let adapter = CreateReducerStateAdapter::from_draw_state(state.clone());
                create_element_reducer::create_element_reducer(
                    &adapter,
                    &map_create_action(action),
                    context,
                )
                .map(CreateReducerStateAdapter::into_draw_state)
            })
            .or_else(|| {
                text_edit_reducer::TextEditReducer::new().reduce(
                    state,
                    &map_text_edit_action(action),
                    context,
                )
            })
            .or_else(|| {
                selection_reducer::selection_reducer(
                    state.clone(),
                    &map_selection_action(action),
                    context,
                )
            })
            .or_else(|| {
                element_reducer::element_reducer(
                    state.clone(),
                    &map_element_action(action),
                    context,
                )
            })
            .or_else(|| camera_reducer::camera_reducer(state, &map_camera_action(action)))
    }
}

/// Returns a machine equivalent to Dart's `interactionStateMachine` constant.
pub fn interaction_state_machine() -> InteractionStateMachine {
    InteractionStateMachine::new()
}

fn map_edit_action(action: &DispatchAction) -> edit_state_reducer::DrawAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::StartEdit>() {
        return edit_state_reducer::DrawAction::StartEdit(edit_state_reducer::StartEdit::new(
            action.operation_id,
            action.position,
            action.params.clone(),
        ));
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::UpdateEdit>() {
        return edit_state_reducer::DrawAction::UpdateEdit(edit_state_reducer::UpdateEdit::new(
            action.current_position,
            action.modifiers,
        ));
    }
    if action.as_any().is::<actions::FinishEdit>() {
        return edit_state_reducer::DrawAction::FinishEdit(edit_state_reducer::FinishEdit);
    }
    if action.as_any().is::<actions::CancelEdit>() {
        return edit_state_reducer::DrawAction::CancelEdit(edit_state_reducer::CancelEdit);
    }

    edit_state_reducer::DrawAction::Other
}

fn map_pending_action(action: &DispatchAction) -> pending_state_reducer::DrawAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::SetDragPending>() {
        return pending_state_reducer::DrawAction::SetDragPending(
            pending_state_reducer::SetDragPending::new(
                action.pointer_down_position,
                action.intent.clone(),
            ),
        );
    }
    if action.as_any().is::<actions::ClearDragPending>() {
        return pending_state_reducer::DrawAction::ClearDragPending(
            pending_state_reducer::ClearDragPending,
        );
    }

    pending_state_reducer::DrawAction::Other
}

fn map_box_select_action(action: &DispatchAction) -> box_select_reducer::DrawAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::StartBoxSelect>() {
        return box_select_reducer::DrawAction::StartBoxSelect(
            box_select_reducer::StartBoxSelect::new(action.start_position),
        );
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::UpdateBoxSelect>() {
        return box_select_reducer::DrawAction::UpdateBoxSelect(
            box_select_reducer::UpdateBoxSelect::new(action.current_position),
        );
    }
    if action.as_any().is::<actions::FinishBoxSelect>() {
        return box_select_reducer::DrawAction::FinishBoxSelect(
            box_select_reducer::FinishBoxSelect,
        );
    }
    if action.as_any().is::<actions::CancelBoxSelect>() {
        return box_select_reducer::DrawAction::CancelBoxSelect(
            box_select_reducer::CancelBoxSelect,
        );
    }

    box_select_reducer::DrawAction::Other
}

fn map_text_edit_action(action: &DispatchAction) -> text_edit_reducer::DrawAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::StartTextEdit>() {
        return text_edit_reducer::DrawAction::StartTextEdit(
            text_edit_reducer::StartTextEdit::new(action.element_id.clone(), action.position),
        );
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::UpdateTextEdit>() {
        return text_edit_reducer::DrawAction::UpdateTextEdit(
            text_edit_reducer::UpdateTextEdit::new(action.text.clone(), action.rect),
        );
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::FinishTextEdit>() {
        return text_edit_reducer::DrawAction::FinishTextEdit(
            text_edit_reducer::FinishTextEdit::new(action.text.clone()),
        );
    }
    if action.as_any().is::<actions::CancelTextEdit>() {
        return text_edit_reducer::DrawAction::CancelTextEdit(text_edit_reducer::CancelTextEdit);
    }

    text_edit_reducer::DrawAction::Other
}

fn map_selection_action(action: &DispatchAction) -> selection_reducer::SelectionReducerAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::SelectElement>() {
        return selection_reducer::SelectionReducerAction::SelectElement(
            selection_reducer::SelectElement::new(
                action.element_id.clone(),
                action.add_to_selection,
            ),
        );
    }
    if action.as_any().is::<actions::ClearSelection>() {
        return selection_reducer::SelectionReducerAction::ClearSelection(
            selection_reducer::ClearSelection,
        );
    }
    if action.as_any().is::<actions::SelectAll>() {
        return selection_reducer::SelectionReducerAction::SelectAll(selection_reducer::SelectAll);
    }

    selection_reducer::SelectionReducerAction::Other
}

fn map_create_action(
    action: &DispatchAction,
) -> create_element_reducer::CreateElementReducerAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::CreateElement>() {
        return create_element_reducer::CreateElementReducerAction::CreateElement(
            create_element_reducer::CreateElement::new(
                action.type_id.clone(),
                action.position,
                action
                    .initial_data
                    .as_ref()
                    .map(|data| core_data_to_strategy_data(data.as_ref())),
                action.maintain_aspect_ratio,
                action.create_from_center,
                action.snap_override,
            ),
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::UpdateCreatingElement>()
    {
        return create_element_reducer::CreateElementReducerAction::UpdateCreatingElement(
            create_element_reducer::UpdateCreatingElement::new(
                action.positions.clone(),
                action.maintain_aspect_ratio,
                action.create_from_center,
                action.snap_override,
            ),
        );
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::AddArrowPoint>() {
        return create_element_reducer::CreateElementReducerAction::AddArrowPoint(
            create_element_reducer::AddArrowPoint::new(action.position, action.snap_override),
        );
    }
    if action.as_any().is::<actions::FinishCreateElement>() {
        return create_element_reducer::CreateElementReducerAction::FinishCreateElement(
            create_element_reducer::FinishCreateElement,
        );
    }
    if action.as_any().is::<actions::CancelCreateElement>() {
        return create_element_reducer::CreateElementReducerAction::CancelCreateElement(
            create_element_reducer::CancelCreateElement,
        );
    }

    create_element_reducer::CreateElementReducerAction::Other
}

fn map_element_action(action: &DispatchAction) -> element_reducer::ElementReducerAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::DeleteElements>() {
        return element_reducer::ElementReducerAction::DeleteElements(
            element_reducer::DeleteElements::new(action.element_ids.clone()),
        );
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::DuplicateElements>() {
        return element_reducer::ElementReducerAction::DuplicateElements(
            element_reducer::DuplicateElements::new(
                action.element_ids.clone(),
                action.offset_x,
                action.offset_y,
            ),
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::ChangeElementZIndex>()
    {
        return element_reducer::ElementReducerAction::ChangeElementZIndex(
            element_reducer::ChangeElementZIndex::new(
                action.element_id.clone(),
                map_z_index_operation(action.operation),
            ),
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::ChangeElementsZIndex>()
    {
        return element_reducer::ElementReducerAction::ChangeElementsZIndex(
            element_reducer::ChangeElementsZIndex::new(
                action.element_ids.clone(),
                map_z_index_operation(action.operation),
            ),
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::UpdateElementsStyle>()
    {
        return element_reducer::ElementReducerAction::UpdateElementsStyle(
            element_reducer::UpdateElementsStyle {
                element_ids: action.element_ids.clone(),
                style_update: action.style_update(),
                opacity: action.opacity,
            },
        );
    }
    if action
        .as_any()
        .is::<actions::RefreshAutoResizeTextLayoutsAfterFontLoad>()
    {
        return element_reducer::ElementReducerAction::RefreshAutoResizeTextLayoutsAfterFontLoad(
            actions::RefreshAutoResizeTextLayoutsAfterFontLoad,
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::UpdateGlobalElements>()
    {
        return element_reducer::ElementReducerAction::UpdateGlobalElements(
            element_reducer::UpdateGlobalElements::new(
                action.highlight_mask.clone(),
                action.watermark.clone(),
            ),
        );
    }
    if let Some(action) = action
        .as_any()
        .downcast_ref::<actions::CreateSerialNumberTextElements>()
    {
        return element_reducer::ElementReducerAction::CreateSerialNumberTextElements(
            element_reducer::CreateSerialNumberTextElements::new(action.element_ids.clone()),
        );
    }

    element_reducer::ElementReducerAction::Other
}

fn map_z_index_operation(
    operation: actions::ZIndexOperation,
) -> crate::draw::reducers::element::zindex_handler::ZIndexOperation {
    use crate::draw::reducers::element::zindex_handler::ZIndexOperation;

    match operation {
        actions::ZIndexOperation::BringToFront => ZIndexOperation::BringToFront,
        actions::ZIndexOperation::SendToBack => ZIndexOperation::SendToBack,
        actions::ZIndexOperation::BringForward => ZIndexOperation::BringForward,
        actions::ZIndexOperation::SendBackward => ZIndexOperation::SendBackward,
    }
}

fn map_camera_action(action: &DispatchAction) -> camera_reducer::DrawAction {
    if let Some(action) = action.as_any().downcast_ref::<actions::MoveCamera>() {
        return camera_reducer::DrawAction::MoveCamera(camera_reducer::MoveCamera::new(
            action.dx, action.dy,
        ));
    }
    if let Some(action) = action.as_any().downcast_ref::<actions::ZoomCamera>() {
        return camera_reducer::DrawAction::ZoomCamera(camera_reducer::ZoomCamera::new(
            action.scale,
            action.center,
        ));
    }

    camera_reducer::DrawAction::Other
}

impl pending_state_reducer::PendingStateReducerInteraction for InteractionState {
    fn as_drag_pending(&self) -> Option<&DragPendingState> {
        let InteractionState::DragPending(value) = self else {
            return None;
        };
        Some(value)
    }

    fn from_drag_pending(pending: DragPendingState) -> Self {
        InteractionState::DragPending(pending)
    }
}

impl pending_state_reducer::PendingStateReducerApplication for ApplicationState {
    type Interaction = InteractionState;

    fn interaction(&self) -> &Self::Interaction {
        &self.interaction
    }

    fn with_interaction(&self, interaction: Self::Interaction) -> Self {
        self.copy_with(None, Some(interaction), None)
    }

    fn to_idle(&self) -> Self {
        ApplicationState::to_idle(self)
    }
}

impl pending_state_reducer::PendingStateReducerState for DrawState {
    type Application = ApplicationState;

    fn application(&self) -> &Self::Application {
        &self.application
    }

    fn with_application(&self, application: Self::Application) -> Self {
        self.copy_with(None, Some(application))
    }
}

impl box_select_reducer::BoxSelectingStateLike for BoxSelectingState {
    fn start_position(&self) -> crate::draw::types::draw_point::DrawPoint {
        self.start_position
    }

    fn current_position(&self) -> crate::draw::types::draw_point::DrawPoint {
        self.current_position
    }

    fn from_positions(
        start_position: crate::draw::types::draw_point::DrawPoint,
        current_position: crate::draw::types::draw_point::DrawPoint,
    ) -> Self {
        Self::new(start_position, current_position)
    }
}

impl box_select_reducer::BoxSelectInteractionState for InteractionState {
    type BoxSelecting = BoxSelectingState;

    fn as_box_selecting(
        &self,
    ) -> Option<&<Self as box_select_reducer::BoxSelectInteractionState>::BoxSelecting> {
        let InteractionState::BoxSelecting(value) = self else {
            return None;
        };
        Some(value)
    }

    fn from_box_selecting(
        value: <Self as box_select_reducer::BoxSelectInteractionState>::BoxSelecting,
    ) -> Self {
        InteractionState::BoxSelecting(value)
    }
}

impl box_select_reducer::BoxSelectReducerState for DrawState {
    type Interaction = InteractionState;

    fn interaction(&self) -> &Self::Interaction {
        &self.application.interaction
    }

    fn with_interaction(&self, interaction: Self::Interaction) -> Self {
        let application = self.application.copy_with(None, Some(interaction), None);
        self.copy_with(None, Some(application))
    }

    fn idle_interaction(&self) -> Self::Interaction {
        InteractionState::Idle(IdleState)
    }

    fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self {
        apply_selection_change(self, selected_ids, false)
    }

    fn visit_elements_in_rect<F>(&self, rect: DrawRect, mut visitor: F)
    where
        F: FnMut(&str) -> bool,
    {
        for element in &self.domain.document.elements {
            if !rects_intersect(rect, element.rect) {
                continue;
            }
            if !visitor(element.id.as_str()) {
                return;
            }
        }
    }
}

impl text_edit_reducer::TextEditReducerState for DrawState {
    fn document_elements(&self) -> &[crate::draw::models::element_state::ElementState] {
        &self.domain.document.elements
    }

    fn with_document_elements(
        &self,
        elements: Vec<crate::draw::models::element_state::ElementState>,
    ) -> Self {
        let document = self.domain.document.copy_with(Some(elements), None, None);
        let domain = self.domain.copy_with(Some(document), None);
        self.copy_with(Some(domain), None)
    }

    fn apply_selection_change(
        &self,
        selected_ids: BTreeSet<String>,
        force_refresh_overlay: bool,
    ) -> Self {
        apply_selection_change(self, selected_ids, force_refresh_overlay)
    }

    fn text_editing(&self) -> Option<&TextEditingState> {
        let InteractionState::TextEditing(value) = &self.application.interaction else {
            return None;
        };
        Some(value)
    }

    fn with_text_editing(&self, text_editing: Option<TextEditingState>) -> Self {
        let interaction = match text_editing {
            Some(text_editing) => InteractionState::TextEditing(text_editing),
            None => InteractionState::Idle(IdleState),
        };

        let application = self.application.copy_with(None, Some(interaction), None);
        self.copy_with(None, Some(application))
    }
}

impl camera_reducer::CameraReducerState for DrawState {
    fn camera_state(&self) -> crate::draw::models::camera_state::CameraState {
        self.application.view.camera
    }

    fn with_camera_state(&self, camera: crate::draw::models::camera_state::CameraState) -> Self {
        let view = self.application.view.copy_with(Some(camera));
        let application = self.application.copy_with(Some(view), None, None);
        self.copy_with(None, Some(application))
    }
}

#[derive(Clone, Debug, PartialEq)]
struct RawCoreElementData {
    type_id: ElementTypeId<DynElementData>,
    json: serde_json::Map<String, serde_json::Value>,
}

impl RawCoreElementData {
    fn from_data(data: &dyn CoreElementData) -> Self {
        Self {
            type_id: data.type_id(),
            json: data.to_json(),
        }
    }
}

impl CoreElementData for RawCoreElementData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        self.type_id.clone()
    }

    fn to_json(&self) -> serde_json::Map<String, serde_json::Value> {
        self.json.clone()
    }
}

#[derive(Clone, PartialEq)]
struct RawStrategyElementData {
    type_id: ElementTypeId<DynElementData>,
    json: serde_json::Map<String, serde_json::Value>,
}

impl fmt::Debug for RawStrategyElementData {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RawStrategyElementData")
            .field("type_id", &self.type_id.as_str())
            .finish()
    }
}

impl RawStrategyElementData {
    fn from_data(data: &dyn CoreElementData) -> Self {
        Self {
            type_id: data.type_id(),
            json: data.to_json(),
        }
    }
}

#[derive(Clone, Debug)]
struct CreateReducerStateAdapter {
    draw_state: DrawState,
    document_elements: Vec<StrategyElementState>,
    creating_state: Option<StrategyCreatingState>,
}

impl CreateReducerStateAdapter {
    fn from_draw_state(draw_state: DrawState) -> Self {
        let document_elements = draw_state
            .domain
            .document
            .elements
            .iter()
            .map(model_element_to_strategy_element)
            .collect();
        let creating_state = match &draw_state.application.interaction {
            InteractionState::Creating(value) => Some(model_creating_to_strategy(value)),
            _ => None,
        };

        Self {
            draw_state,
            document_elements,
            creating_state,
        }
    }

    fn into_draw_state(self) -> DrawState {
        self.draw_state
    }
}

impl create_element_reducer::CreateElementReducerState for CreateReducerStateAdapter {
    fn document_elements(&self) -> &[StrategyElementState] {
        &self.document_elements
    }

    fn current_creating_state(&self) -> Option<&StrategyCreatingState> {
        self.creating_state.as_ref()
    }

    fn with_creating_state(&self, creating_state: Option<StrategyCreatingState>) -> Self {
        let mut next = self.clone();
        next.creating_state = creating_state.clone();

        let interaction = match creating_state {
            Some(creating) => InteractionState::Creating(strategy_creating_to_model(&creating)),
            None => InteractionState::Idle(IdleState),
        };
        let application = next
            .draw_state
            .application
            .copy_with(None, Some(interaction), None);
        next.draw_state = next.draw_state.copy_with(None, Some(application));
        next
    }

    fn with_document_elements(&self, elements: Vec<StrategyElementState>) -> Self {
        let mut next = self.clone();
        next.document_elements = elements.clone();

        let model_elements = elements
            .iter()
            .map(strategy_element_to_model_element)
            .collect::<Vec<_>>();
        let document = next
            .draw_state
            .domain
            .document
            .copy_with(Some(model_elements), None, None);
        let domain = next.draw_state.domain.copy_with(Some(document), None);
        next.draw_state = next.draw_state.copy_with(Some(domain), None);
        next
    }

    fn clear_selection(&self) -> Self {
        let mut next = self.clone();
        next.draw_state = apply_selection_change(&next.draw_state, BTreeSet::new(), false);
        next
    }

    fn creation_strategy_state(&self) -> CreationStrategyDrawState {
        self.draw_state.clone()
    }
}

fn model_element_to_strategy_element(
    element: &crate::draw::models::element_state::ElementState,
) -> StrategyElementState {
    StrategyElementState {
        id: element.id.clone(),
        type_id_value: element.type_id().as_str().to_owned(),
        rect: element.rect,
        rotation: element.rotation,
        opacity: element.opacity,
        z_index: element.z_index,
        data: core_data_to_strategy_data(element.data.as_ref()),
    }
}

fn strategy_element_to_model_element(
    element: &StrategyElementState,
) -> crate::draw::models::element_state::ElementState {
    crate::draw::models::element_state::ElementState::new(
        element.id.clone(),
        element.rect,
        element.rotation,
        element.opacity,
        element.z_index,
        strategy_data_to_core_data(element.data.as_ref()),
    )
}

fn model_creating_to_strategy(creating: &ModelCreatingState) -> StrategyCreatingState {
    StrategyCreatingState {
        element: model_element_to_strategy_element(&creating.element),
        start_position: creating.start_position,
        current_rect: creating.current_rect,
        snap_guides: creating.snap_guides.clone(),
        creation_mode: model_creation_mode_to_strategy(&creating.creation_mode),
    }
}

fn strategy_creating_to_model(creating: &StrategyCreatingState) -> ModelCreatingState {
    ModelCreatingState::new(
        strategy_element_to_model_element(&creating.element),
        creating.start_position,
        creating.current_rect,
        creating.snap_guides.clone(),
        strategy_creation_mode_to_model(&creating.creation_mode),
    )
}

fn model_creation_mode_to_strategy(mode: &ModelCreationMode) -> StrategyCreationMode {
    match mode {
        ModelCreationMode::Rect(_) => StrategyCreationMode::Rect,
        ModelCreationMode::Point(point_mode) => {
            StrategyCreationMode::Point(StrategyPointCreationMode {
                fixed_points: point_mode.fixed_points.clone(),
                current_point: point_mode.current_point,
                session_data: point_mode.session_data.clone(),
            })
        }
    }
}

fn strategy_creation_mode_to_model(mode: &StrategyCreationMode) -> ModelCreationMode {
    match mode {
        StrategyCreationMode::Rect => ModelCreationMode::Rect(RectCreationMode),
        StrategyCreationMode::Point(point_mode) => {
            ModelCreationMode::Point(ModelPointCreationMode::new(
                point_mode.fixed_points.clone(),
                point_mode.current_point,
                point_mode.session_data.clone(),
            ))
        }
    }
}

fn core_data_to_strategy_data(data: &dyn CoreElementData) -> Arc<dyn StrategyElementData> {
    if let Some(decoded) = decode_rectangle_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_arrow_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_line_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_free_draw_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_highlight_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_filter_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_text_data(data) {
        return Arc::new(decoded);
    }
    if let Some(decoded) = decode_serial_number_data(data) {
        return Arc::new(decoded);
    }

    Arc::new(RawStrategyElementData::from_data(data))
}

fn strategy_data_to_core_data(data: &dyn StrategyElementData) -> Arc<dyn CoreElementData> {
    if let Some(value) = data.as_any().downcast_ref::<RectangleData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<ArrowData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<LineData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<FreeDrawData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<HighlightData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<FilterData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<TextData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<SerialNumberData>() {
        return Arc::new(value.clone());
    }
    if let Some(value) = data.as_any().downcast_ref::<RawStrategyElementData>() {
        return Arc::new(RawCoreElementData {
            type_id: value.type_id.clone(),
            json: value.json.clone(),
        });
    }

    Arc::new(RawCoreElementData {
        type_id: ElementTypeId::new("unknown"),
        json: serde_json::Map::new(),
    })
}

fn decode_rectangle_data(data: &dyn CoreElementData) -> Option<RectangleData> {
    if data.type_id().as_str() != RectangleData::TYPE_ID_TOKEN {
        return None;
    }
    RectangleData::from_json(&data.to_json()).ok()
}

fn decode_arrow_data(data: &dyn CoreElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}

fn decode_line_data(data: &dyn CoreElementData) -> Option<LineData> {
    if data.type_id().as_str() != LineData::TYPE_ID_TOKEN {
        return None;
    }
    LineData::from_json(&data.to_json()).ok()
}

fn decode_free_draw_data(data: &dyn CoreElementData) -> Option<FreeDrawData> {
    if data.type_id().as_str() != FreeDrawData::TYPE_ID_TOKEN {
        return None;
    }
    FreeDrawData::from_json(&data.to_json()).ok()
}

fn decode_highlight_data(data: &dyn CoreElementData) -> Option<HighlightData> {
    if data.type_id().as_str() != HighlightData::TYPE_ID_TOKEN {
        return None;
    }
    HighlightData::from_json(&data.to_json()).ok()
}

fn decode_filter_data(data: &dyn CoreElementData) -> Option<FilterData> {
    if data.type_id().as_str() != FilterData::TYPE_ID_TOKEN {
        return None;
    }
    FilterData::from_json(&data.to_json()).ok()
}

fn decode_text_data(data: &dyn CoreElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn CoreElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

fn rects_intersect(left: DrawRect, right: DrawRect) -> bool {
    !(left.max_x < right.min_x
        || left.min_x > right.max_x
        || left.max_y < right.min_y
        || left.min_y > right.max_y)
}
