#![allow(dead_code)]

use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation::EditOperationParams;
use crate::draw::edit::core::edit_session_id_generator::EditSessionIdGenerator;
use crate::draw::edit::core::edit_session_service::EditSessionService;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::edit_session_id::EditSessionId;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_operation_id::EditOperationId;

/// Transition produced by interaction reducers.
#[derive(Clone, Debug, PartialEq)]
pub struct InteractionTransition {
    pub next_state: DrawState,
}

impl InteractionTransition {
    pub fn new(next_state: DrawState) -> Self {
        Self { next_state }
    }
}

/// Action payload for starting an edit interaction.
#[derive(Clone, Debug, PartialEq)]
pub struct StartEdit {
    pub operation_id: EditOperationId,
    pub position: DrawPoint,
    pub params: EditOperationParams,
}

impl StartEdit {
    pub fn new(
        operation_id: EditOperationId,
        position: DrawPoint,
        params: EditOperationParams,
    ) -> Self {
        Self {
            operation_id,
            position,
            params,
        }
    }
}

/// Action payload for updating an in-progress edit interaction.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct UpdateEdit {
    pub current_position: DrawPoint,
    pub modifiers: EditModifiers,
}

impl UpdateEdit {
    pub const fn new(current_position: DrawPoint, modifiers: EditModifiers) -> Self {
        Self {
            current_position,
            modifiers,
        }
    }
}

/// Action marker for finishing an edit interaction.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FinishEdit;

/// Action marker for cancelling an edit interaction.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CancelEdit;

/// Edit reducer action surface.
///
/// The aggregate app action type can be adapted into this enum by mapping only
/// edit-related variants and forwarding all others as `Other`.
#[derive(Clone, Debug, PartialEq)]
pub enum DrawAction {
    StartEdit(StartEdit),
    UpdateEdit(UpdateEdit),
    FinishEdit(FinishEdit),
    CancelEdit(CancelEdit),
    Other,
}

impl From<StartEdit> for DrawAction {
    fn from(value: StartEdit) -> Self {
        Self::StartEdit(value)
    }
}

impl From<UpdateEdit> for DrawAction {
    fn from(value: UpdateEdit) -> Self {
        Self::UpdateEdit(value)
    }
}

impl From<FinishEdit> for DrawAction {
    fn from(value: FinishEdit) -> Self {
        Self::FinishEdit(value)
    }
}

impl From<CancelEdit> for DrawAction {
    fn from(value: CancelEdit) -> Self {
        Self::CancelEdit(value)
    }
}

/// Service adapter used by [`reduce_edit_state`].
///
/// This keeps the reducer independent from the concrete session-service type,
/// while still providing an implementation for [`EditSessionService`].
pub trait EditStateReducerService {
    fn start(
        &self,
        state: &DrawState,
        operation_id: EditOperationId,
        position: DrawPoint,
        params: &EditOperationParams,
        session_id: EditSessionId,
    ) -> DrawState;

    fn update(
        &self,
        state: &DrawState,
        current_position: DrawPoint,
        modifiers: EditModifiers,
    ) -> DrawState;

    fn finish(&self, state: &DrawState) -> DrawState;

    fn cancel(&self, state: &DrawState) -> DrawState;
}

impl EditStateReducerService for EditSessionService {
    fn start(
        &self,
        state: &DrawState,
        operation_id: EditOperationId,
        position: DrawPoint,
        params: &EditOperationParams,
        session_id: EditSessionId,
    ) -> DrawState {
        EditSessionService::start(self, state, operation_id, position, params, session_id).state
    }

    fn update(
        &self,
        state: &DrawState,
        current_position: DrawPoint,
        modifiers: EditModifiers,
    ) -> DrawState {
        EditSessionService::update(self, state, current_position, modifiers).state
    }

    fn finish(&self, state: &DrawState) -> DrawState {
        EditSessionService::finish(self, state).state
    }

    fn cancel(&self, state: &DrawState) -> DrawState {
        EditSessionService::cancel(self, state).state
    }
}

/// Reducer dedicated to edit operations.
///
/// Mirrors Dart `reduceEditState` handling for start/update/finish/cancel.
pub fn reduce_edit_state<S>(
    state: &DrawState,
    action: &DrawAction,
    edit_session_service: &S,
    session_id_generator: &EditSessionIdGenerator,
) -> Option<InteractionTransition>
where
    S: EditStateReducerService,
{
    match action {
        DrawAction::StartEdit(action) => {
            Some(InteractionTransition::new(edit_session_service.start(
                state,
                action.operation_id,
                action.position,
                &action.params,
                (session_id_generator.as_ref())(),
            )))
        }
        DrawAction::UpdateEdit(action) => Some(InteractionTransition::new(
            edit_session_service.update(state, action.current_position, action.modifiers),
        )),
        DrawAction::FinishEdit(_) => Some(InteractionTransition::new(
            edit_session_service.finish(state),
        )),
        DrawAction::CancelEdit(_) => Some(InteractionTransition::new(
            edit_session_service.cancel(state),
        )),
        DrawAction::Other => None,
    }
}
