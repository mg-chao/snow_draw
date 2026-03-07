#![allow(dead_code)]

use crate::draw::models::interaction_state::{DragPendingState, PendingIntent};
use crate::draw::types::draw_point::DrawPoint;

/// Action payload for entering drag-pending interaction state.
#[derive(Clone, Debug, PartialEq)]
pub struct SetDragPending {
    pub pointer_down_position: DrawPoint,
    pub intent: PendingIntent,
}

impl SetDragPending {
    pub fn new(pointer_down_position: DrawPoint, intent: PendingIntent) -> Self {
        Self {
            pointer_down_position,
            intent,
        }
    }
}

/// Action marker for clearing drag-pending interaction state.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ClearDragPending;

/// Action surface consumed by [`PendingStateReducer`].
///
/// The app-level action enum can be adapted into this shape by mapping only
/// pending-related variants and forwarding all others as `Other`.
#[derive(Clone, Debug, PartialEq)]
pub enum DrawAction {
    SetDragPending(SetDragPending),
    ClearDragPending(ClearDragPending),
    Other,
}

impl From<SetDragPending> for DrawAction {
    fn from(value: SetDragPending) -> Self {
        Self::SetDragPending(value)
    }
}

impl From<ClearDragPending> for DrawAction {
    fn from(value: ClearDragPending) -> Self {
        Self::ClearDragPending(value)
    }
}

/// Interaction adapter used by [`pending_state_reducer`].
pub trait PendingStateReducerInteraction: Clone {
    fn as_drag_pending(&self) -> Option<&DragPendingState>;
    fn from_drag_pending(pending: DragPendingState) -> Self;
}

/// Application adapter used by [`pending_state_reducer`].
pub trait PendingStateReducerApplication: Clone {
    type Interaction: PendingStateReducerInteraction;

    fn interaction(&self) -> &Self::Interaction;
    fn with_interaction(&self, interaction: Self::Interaction) -> Self;
    fn to_idle(&self) -> Self;
}

/// State adapter used by [`pending_state_reducer`].
pub trait PendingStateReducerState: Clone {
    type Application: PendingStateReducerApplication;

    fn application(&self) -> &Self::Application;
    fn with_application(&self, application: Self::Application) -> Self;
}

/// Reducer for pending select/move states.
///
/// Handles:
/// - [`DrawAction::SetDragPending`]
/// - [`DrawAction::ClearDragPending`]
#[derive(Clone, Copy, Debug, Default)]
pub struct PendingStateReducer;

impl PendingStateReducer {
    pub const fn new() -> Self {
        Self
    }

    /// Attempts to handle pending-state actions.
    ///
    /// Returns `None` when the action is not pending-related.
    pub fn reduce<S>(&self, state: &S, action: &DrawAction) -> Option<S>
    where
        S: PendingStateReducerState,
    {
        pending_state_reducer(state, action)
    }
}

/// Free-function variant of [`PendingStateReducer::reduce`].
pub fn pending_state_reducer<S>(state: &S, action: &DrawAction) -> Option<S>
where
    S: PendingStateReducerState,
{
    match action {
        DrawAction::SetDragPending(action) => Some(set_drag_pending(
            state,
            DragPendingState::new(action.pointer_down_position, action.intent.clone()),
        )),
        DrawAction::ClearDragPending(_) => Some(clear_drag_pending(state)),
        DrawAction::Other => None,
    }
}

fn set_drag_pending<S>(state: &S, pending: DragPendingState) -> S
where
    S: PendingStateReducerState,
{
    let interaction = state.application().interaction();
    if interaction
        .as_drag_pending()
        .is_some_and(|current| current == &pending)
    {
        return state.clone();
    }

    let next_interaction =
        <S::Application as PendingStateReducerApplication>::Interaction::from_drag_pending(pending);
    let next_application = state.application().with_interaction(next_interaction);
    state.with_application(next_application)
}

fn clear_drag_pending<S>(state: &S) -> S
where
    S: PendingStateReducerState,
{
    if state
        .application()
        .interaction()
        .as_drag_pending()
        .is_none()
    {
        return state.clone();
    }

    state.with_application(state.application().to_idle())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::models::interaction_state::{PendingMoveIntent, PendingSelectIntent};

    #[derive(Clone, Debug, PartialEq)]
    enum TestInteraction {
        Idle,
        DragPending(DragPendingState),
        Editing,
    }

    impl PendingStateReducerInteraction for TestInteraction {
        fn as_drag_pending(&self) -> Option<&DragPendingState> {
            let Self::DragPending(value) = self else {
                return None;
            };
            Some(value)
        }

        fn from_drag_pending(pending: DragPendingState) -> Self {
            Self::DragPending(pending)
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestApplication {
        interaction: TestInteraction,
    }

    impl PendingStateReducerApplication for TestApplication {
        type Interaction = TestInteraction;

        fn interaction(&self) -> &Self::Interaction {
            &self.interaction
        }

        fn with_interaction(&self, interaction: Self::Interaction) -> Self {
            Self { interaction }
        }

        fn to_idle(&self) -> Self {
            if matches!(self.interaction, TestInteraction::Idle) {
                return self.clone();
            }

            Self {
                interaction: TestInteraction::Idle,
            }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        application: TestApplication,
    }

    impl PendingStateReducerState for TestState {
        type Application = TestApplication;

        fn application(&self) -> &Self::Application {
            &self.application
        }

        fn with_application(&self, application: Self::Application) -> Self {
            Self { application }
        }
    }

    fn pending_state(position: DrawPoint) -> DragPendingState {
        DragPendingState::new(
            position,
            PendingIntent::Select(PendingSelectIntent::new("a", false)),
        )
    }

    #[test]
    fn set_drag_pending_updates_interaction() {
        let state = TestState {
            application: TestApplication {
                interaction: TestInteraction::Idle,
            },
        };
        let action = DrawAction::SetDragPending(SetDragPending::new(
            DrawPoint::new(10.0, 20.0),
            PendingIntent::Move(PendingMoveIntent),
        ));

        let next = pending_state_reducer(&state, &action).expect("action must be handled");
        let TestInteraction::DragPending(pending) = next.application.interaction else {
            panic!("expected drag-pending interaction");
        };

        assert_eq!(pending.pointer_down_position, DrawPoint::new(10.0, 20.0));
        assert!(matches!(pending.intent, PendingIntent::Move(_)));
    }

    #[test]
    fn set_drag_pending_noops_when_pending_is_unchanged() {
        let state = TestState {
            application: TestApplication {
                interaction: TestInteraction::DragPending(pending_state(DrawPoint::new(1.0, 2.0))),
            },
        };
        let action = DrawAction::SetDragPending(SetDragPending::new(
            DrawPoint::new(1.0, 2.0),
            PendingIntent::Select(PendingSelectIntent::new("a", false)),
        ));

        let next = pending_state_reducer(&state, &action).expect("action must be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn clear_drag_pending_resets_to_idle() {
        let state = TestState {
            application: TestApplication {
                interaction: TestInteraction::DragPending(pending_state(DrawPoint::new(3.0, 4.0))),
            },
        };

        let next = pending_state_reducer(&state, &DrawAction::ClearDragPending(ClearDragPending))
            .expect("action must be handled");

        assert!(matches!(
            next.application.interaction,
            TestInteraction::Idle
        ));
    }

    #[test]
    fn clear_drag_pending_keeps_non_pending_interactions() {
        let state = TestState {
            application: TestApplication {
                interaction: TestInteraction::Editing,
            },
        };

        let next = pending_state_reducer(&state, &DrawAction::ClearDragPending(ClearDragPending))
            .expect("action must be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn non_pending_action_returns_none() {
        let state = TestState {
            application: TestApplication {
                interaction: TestInteraction::Idle,
            },
        };

        let next = pending_state_reducer(&state, &DrawAction::Other);

        assert!(next.is_none());
    }
}
