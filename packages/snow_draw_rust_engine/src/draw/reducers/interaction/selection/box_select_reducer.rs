#![allow(dead_code)]

use std::collections::BTreeSet;

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Action payload for starting box selection.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StartBoxSelect {
    pub start_position: DrawPoint,
}

impl StartBoxSelect {
    pub const fn new(start_position: DrawPoint) -> Self {
        Self { start_position }
    }
}

/// Action payload for updating an in-progress box selection.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct UpdateBoxSelect {
    pub current_position: DrawPoint,
}

impl UpdateBoxSelect {
    pub const fn new(current_position: DrawPoint) -> Self {
        Self { current_position }
    }
}

/// Action marker for finishing box selection.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FinishBoxSelect;

/// Action marker for cancelling box selection.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CancelBoxSelect;

/// Box-select reducer action surface.
///
/// The aggregate app action type can be adapted into this enum by mapping
/// box-selection variants and forwarding all others as `Other`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum DrawAction {
    StartBoxSelect(StartBoxSelect),
    UpdateBoxSelect(UpdateBoxSelect),
    FinishBoxSelect(FinishBoxSelect),
    CancelBoxSelect(CancelBoxSelect),
    Other,
}

impl From<StartBoxSelect> for DrawAction {
    fn from(value: StartBoxSelect) -> Self {
        Self::StartBoxSelect(value)
    }
}

impl From<UpdateBoxSelect> for DrawAction {
    fn from(value: UpdateBoxSelect) -> Self {
        Self::UpdateBoxSelect(value)
    }
}

impl From<FinishBoxSelect> for DrawAction {
    fn from(value: FinishBoxSelect) -> Self {
        Self::FinishBoxSelect(value)
    }
}

impl From<CancelBoxSelect> for DrawAction {
    fn from(value: CancelBoxSelect) -> Self {
        Self::CancelBoxSelect(value)
    }
}

/// Adapter for box-selecting interaction payload.
pub trait BoxSelectingStateLike: Clone {
    fn start_position(&self) -> DrawPoint;

    fn current_position(&self) -> DrawPoint;

    fn from_positions(start_position: DrawPoint, current_position: DrawPoint) -> Self;

    fn with_current_position(&self, current_position: DrawPoint) -> Self {
        Self::from_positions(self.start_position(), current_position)
    }

    fn bounds(&self) -> DrawRect {
        DrawRect::from_points(self.start_position(), self.current_position())
    }
}

/// Adapter for interaction state that may contain box-selecting payload.
pub trait BoxSelectInteractionState: Clone {
    type BoxSelecting: BoxSelectingStateLike;

    fn as_box_selecting(&self) -> Option<&Self::BoxSelecting>;

    fn from_box_selecting(value: Self::BoxSelecting) -> Self;
}

/// Adapter for aggregate draw state consumed by [`BoxSelectReducer`].
pub trait BoxSelectReducerState: Clone {
    type Interaction: BoxSelectInteractionState;

    fn interaction(&self) -> &Self::Interaction;

    fn with_interaction(&self, interaction: Self::Interaction) -> Self;

    fn idle_interaction(&self) -> Self::Interaction;

    fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self;

    fn visit_elements_in_rect<F>(&self, rect: DrawRect, visitor: F)
    where
        F: FnMut(&str) -> bool;
}

/// Reducer for box selection operations.
///
/// Handles: `StartBoxSelect`, `UpdateBoxSelect`, `FinishBoxSelect`,
/// `CancelBoxSelect`.
#[derive(Clone, Copy, Debug, Default)]
pub struct BoxSelectReducer;

impl BoxSelectReducer {
    pub const fn new() -> Self {
        Self
    }

    /// Tries to handle box-selection actions.
    ///
    /// Returns `None` if the action is not a box-selection operation.
    pub fn reduce<S>(&self, state: &S, action: &DrawAction) -> Option<S>
    where
        S: BoxSelectReducerState,
    {
        match action {
            DrawAction::StartBoxSelect(action) => Some(self.start_box_select(state, *action)),
            DrawAction::UpdateBoxSelect(action) => Some(self.update_box_select(state, *action)),
            DrawAction::FinishBoxSelect(_) => Some(self.finish_box_select(state)),
            DrawAction::CancelBoxSelect(_) => Some(self.cancel_box_select(state)),
            DrawAction::Other => None,
        }
    }

    fn start_box_select<S>(&self, state: &S, action: StartBoxSelect) -> S
    where
        S: BoxSelectReducerState,
    {
        let next_state = state.apply_selection_change(BTreeSet::new());
        let interaction = <<S as BoxSelectReducerState>::Interaction as BoxSelectInteractionState>::from_box_selecting(
            <<<S as BoxSelectReducerState>::Interaction as BoxSelectInteractionState>::BoxSelecting as BoxSelectingStateLike>::from_positions(
                action.start_position,
                action.start_position,
            ),
        );

        next_state.with_interaction(interaction)
    }

    fn update_box_select<S>(&self, state: &S, action: UpdateBoxSelect) -> S
    where
        S: BoxSelectReducerState,
    {
        let Some(interaction) = state.interaction().as_box_selecting() else {
            return state.clone();
        };

        if interaction.current_position() == action.current_position {
            return state.clone();
        }

        let next_interaction = <S::Interaction as BoxSelectInteractionState>::from_box_selecting(
            interaction.with_current_position(action.current_position),
        );

        state.with_interaction(next_interaction)
    }

    fn finish_box_select<S>(&self, state: &S) -> S
    where
        S: BoxSelectReducerState,
    {
        let Some(interaction) = state.interaction().as_box_selecting() else {
            return state.clone();
        };

        let mut selected_ids = BTreeSet::new();
        state.visit_elements_in_rect(interaction.bounds(), |element_id| {
            selected_ids.insert(element_id.to_owned());
            true
        });

        let next_state = state.with_interaction(state.idle_interaction());
        next_state.apply_selection_change(selected_ids)
    }

    fn cancel_box_select<S>(&self, state: &S) -> S
    where
        S: BoxSelectReducerState,
    {
        if state.interaction().as_box_selecting().is_none() {
            return state.clone();
        }

        state.with_interaction(state.idle_interaction())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        BoxSelectInteractionState, BoxSelectReducer, BoxSelectReducerState, BoxSelectingStateLike,
        CancelBoxSelect, DrawAction, FinishBoxSelect, StartBoxSelect, UpdateBoxSelect,
    };
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;
    use std::collections::BTreeSet;

    #[derive(Clone, Copy, Debug, PartialEq)]
    struct TestBoxSelectingState {
        start_position: DrawPoint,
        current_position: DrawPoint,
    }

    impl BoxSelectingStateLike for TestBoxSelectingState {
        fn start_position(&self) -> DrawPoint {
            self.start_position
        }

        fn current_position(&self) -> DrawPoint {
            self.current_position
        }

        fn from_positions(start_position: DrawPoint, current_position: DrawPoint) -> Self {
            Self {
                start_position,
                current_position,
            }
        }
    }

    #[derive(Clone, Copy, Debug, PartialEq)]
    enum TestInteraction {
        Idle,
        BoxSelecting(TestBoxSelectingState),
        Editing,
    }

    impl BoxSelectInteractionState for TestInteraction {
        type BoxSelecting = TestBoxSelectingState;

        fn as_box_selecting(&self) -> Option<&<Self as BoxSelectInteractionState>::BoxSelecting> {
            match self {
                Self::BoxSelecting(value) => Some(value),
                Self::Idle | Self::Editing => None,
            }
        }

        fn from_box_selecting(value: <Self as BoxSelectInteractionState>::BoxSelecting) -> Self {
            Self::BoxSelecting(value)
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestElement {
        id: String,
        rect: DrawRect,
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        elements: Vec<TestElement>,
        selected_ids: BTreeSet<String>,
        interaction: TestInteraction,
    }

    impl TestState {
        fn new(elements: Vec<TestElement>, interaction: TestInteraction) -> Self {
            Self {
                elements,
                selected_ids: BTreeSet::new(),
                interaction,
            }
        }
    }

    impl BoxSelectReducerState for TestState {
        type Interaction = TestInteraction;

        fn interaction(&self) -> &Self::Interaction {
            &self.interaction
        }

        fn with_interaction(&self, interaction: Self::Interaction) -> Self {
            Self {
                elements: self.elements.clone(),
                selected_ids: self.selected_ids.clone(),
                interaction,
            }
        }

        fn idle_interaction(&self) -> Self::Interaction {
            TestInteraction::Idle
        }

        fn apply_selection_change(&self, selected_ids: BTreeSet<String>) -> Self {
            Self {
                elements: self.elements.clone(),
                selected_ids,
                interaction: self.interaction,
            }
        }

        fn visit_elements_in_rect<F>(&self, rect: DrawRect, mut visitor: F)
        where
            F: FnMut(&str) -> bool,
        {
            for element in &self.elements {
                if !rects_intersect(rect, element.rect) {
                    continue;
                }

                if !visitor(&element.id) {
                    return;
                }
            }
        }
    }

    fn rect(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> DrawRect {
        DrawRect::new(min_x, min_y, max_x, max_y)
    }

    fn ids(values: &[&str]) -> BTreeSet<String> {
        values.iter().map(|value| (*value).to_owned()).collect()
    }

    fn rects_intersect(a: DrawRect, b: DrawRect) -> bool {
        !(a.max_x < b.min_x || a.min_x > b.max_x || a.max_y < b.min_y || a.min_y > b.max_y)
    }

    #[test]
    fn start_box_select_clears_selection_and_enters_box_selecting() {
        let mut state = TestState::new(Vec::new(), TestInteraction::Idle);
        state.selected_ids = ids(&["a", "b"]);

        let reducer = BoxSelectReducer::new();
        let action = DrawAction::StartBoxSelect(StartBoxSelect::new(DrawPoint::new(10.0, 20.0)));

        let next = reducer
            .reduce(&state, &action)
            .expect("box-select action should be handled");

        assert!(next.selected_ids.is_empty());
        match next.interaction {
            TestInteraction::BoxSelecting(interaction) => {
                assert_eq!(interaction.start_position, DrawPoint::new(10.0, 20.0));
                assert_eq!(interaction.current_position, DrawPoint::new(10.0, 20.0));
            }
            other => panic!("expected box-selecting interaction, got {other:?}"),
        }
    }

    #[test]
    fn update_box_select_noops_when_position_is_unchanged() {
        let state = TestState::new(
            Vec::new(),
            TestInteraction::BoxSelecting(TestBoxSelectingState::from_positions(
                DrawPoint::new(1.0, 2.0),
                DrawPoint::new(3.0, 4.0),
            )),
        );

        let reducer = BoxSelectReducer::new();
        let action = DrawAction::UpdateBoxSelect(UpdateBoxSelect::new(DrawPoint::new(3.0, 4.0)));

        let next = reducer
            .reduce(&state, &action)
            .expect("box-select action should be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn update_box_select_updates_current_position() {
        let state = TestState::new(
            Vec::new(),
            TestInteraction::BoxSelecting(TestBoxSelectingState::from_positions(
                DrawPoint::new(1.0, 2.0),
                DrawPoint::new(3.0, 4.0),
            )),
        );

        let reducer = BoxSelectReducer::new();
        let action = DrawAction::UpdateBoxSelect(UpdateBoxSelect::new(DrawPoint::new(7.0, 9.0)));

        let next = reducer
            .reduce(&state, &action)
            .expect("box-select action should be handled");

        match next.interaction {
            TestInteraction::BoxSelecting(interaction) => {
                assert_eq!(interaction.start_position, DrawPoint::new(1.0, 2.0));
                assert_eq!(interaction.current_position, DrawPoint::new(7.0, 9.0));
            }
            other => panic!("expected box-selecting interaction, got {other:?}"),
        }
    }

    #[test]
    fn finish_box_select_selects_elements_in_bounds_and_returns_to_idle() {
        let state = TestState::new(
            vec![
                TestElement {
                    id: "inside".to_owned(),
                    rect: rect(1.0, 1.0, 3.0, 3.0),
                },
                TestElement {
                    id: "outside".to_owned(),
                    rect: rect(20.0, 20.0, 22.0, 22.0),
                },
                TestElement {
                    id: "overlap".to_owned(),
                    rect: rect(4.0, 4.0, 12.0, 12.0),
                },
            ],
            TestInteraction::BoxSelecting(TestBoxSelectingState::from_positions(
                DrawPoint::new(0.0, 0.0),
                DrawPoint::new(10.0, 10.0),
            )),
        );

        let reducer = BoxSelectReducer::new();
        let action = DrawAction::FinishBoxSelect(FinishBoxSelect);

        let next = reducer
            .reduce(&state, &action)
            .expect("box-select action should be handled");

        assert_eq!(next.selected_ids, ids(&["inside", "overlap"]));
        assert_eq!(next.interaction, TestInteraction::Idle);
    }

    #[test]
    fn finish_box_select_noops_when_not_box_selecting() {
        let state = TestState::new(Vec::new(), TestInteraction::Editing);
        let reducer = BoxSelectReducer::new();

        let next = reducer
            .reduce(&state, &DrawAction::FinishBoxSelect(FinishBoxSelect))
            .expect("box-select action should be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn cancel_box_select_returns_to_idle() {
        let state = TestState::new(
            Vec::new(),
            TestInteraction::BoxSelecting(TestBoxSelectingState::from_positions(
                DrawPoint::new(0.0, 0.0),
                DrawPoint::new(1.0, 1.0),
            )),
        );
        let reducer = BoxSelectReducer::new();

        let next = reducer
            .reduce(&state, &DrawAction::CancelBoxSelect(CancelBoxSelect))
            .expect("box-select action should be handled");

        assert_eq!(next.interaction, TestInteraction::Idle);
    }

    #[test]
    fn cancel_box_select_noops_when_not_box_selecting() {
        let state = TestState::new(Vec::new(), TestInteraction::Idle);
        let reducer = BoxSelectReducer::new();

        let next = reducer
            .reduce(&state, &DrawAction::CancelBoxSelect(CancelBoxSelect))
            .expect("box-select action should be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn non_box_select_action_is_not_handled() {
        let state = TestState::new(Vec::new(), TestInteraction::Idle);
        let reducer = BoxSelectReducer::new();

        let next = reducer.reduce(&state, &DrawAction::Other);

        assert!(next.is_none());
    }
}
