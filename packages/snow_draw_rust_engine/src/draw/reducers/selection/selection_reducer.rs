#![allow(dead_code)]

use std::collections::BTreeSet;

use crate::draw::core::draw_context::DrawContext;
use crate::draw::events::error_events::ValidationFailedEvent;
use crate::draw::models::draw_state::DrawState;
use crate::draw::reducers::core::reducer_utils::apply_selection_change;
use crate::draw::services::log::log_service::LogData;
use serde_json::Value;

/// Action payload for selecting one element.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SelectElement {
    pub element_id: String,
    pub add_to_selection: bool,
}

impl SelectElement {
    pub fn new(element_id: impl Into<String>, add_to_selection: bool) -> Self {
        Self {
            element_id: element_id.into(),
            add_to_selection,
        }
    }
}

/// Action payload for clearing current selection.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ClearSelection;

/// Action payload for selecting all elements.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SelectAll;

/// Selection-scoped reducer action surface.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SelectionReducerAction {
    SelectElement(SelectElement),
    ClearSelection(ClearSelection),
    SelectAll(SelectAll),
    Other,
}

impl Default for SelectionReducerAction {
    fn default() -> Self {
        Self::Other
    }
}

/// State adapter required by [`selection_reducer_with`].
///
/// This trait keeps the reducer reusable across state containers.
pub trait SelectionReducerState: Clone {
    /// Returns true when `element_id` can be selected.
    fn contains_element_id(&self, element_id: &str) -> bool;

    /// Returns selected ids.
    fn selected_ids(&self) -> BTreeSet<String>;

    /// Returns ids for every selectable element.
    fn all_element_ids(&self) -> BTreeSet<String>;

    /// Returns copied state with `selected_ids` applied.
    fn apply_selection_ids(&self, selected_ids: BTreeSet<String>) -> Self;
}

impl SelectionReducerState for DrawState {
    fn contains_element_id(&self, element_id: &str) -> bool {
        self.domain
            .document
            .elements
            .iter()
            .any(|element| element.id == element_id)
    }

    fn selected_ids(&self) -> BTreeSet<String> {
        self.domain.selection.selected_ids.clone()
    }

    fn all_element_ids(&self) -> BTreeSet<String> {
        self.domain
            .document
            .elements
            .iter()
            .map(|element| element.id.clone())
            .collect()
    }

    fn apply_selection_ids(&self, selected_ids: BTreeSet<String>) -> Self {
        apply_selection_change(self, selected_ids, false)
    }
}

/// Context hook used for validation side-effects.
///
/// In Dart, missing-element selection logs a warning and emits
/// `ValidationFailedEvent`.
pub trait SelectionReducerContext {
    fn on_selection_validation_failed(&self, action: &str, element_id: &str);
}

impl SelectionReducerContext for DrawContext {
    fn on_selection_validation_failed(&self, action: &str, element_id: &str) {
        let mut log_data = LogData::new();
        log_data.insert("action".to_owned(), action.to_owned());
        log_data.insert("elementId".to_owned(), element_id.to_owned());

        self.log
            .store()
            .warning("Selection failed: element not found", Some(&log_data));

        let Some(event_bus) = self.event_bus.as_ref() else {
            return;
        };

        let action = action.to_owned();
        let element_id = element_id.to_owned();
        let _ = event_bus.emit_lazy::<ValidationFailedEvent, _>(move || {
            let mut details = indexmap::IndexMap::new();
            details.insert("elementId".to_owned(), Value::String(element_id));
            ValidationFailedEvent::new(action, "Element not found", details)
        });
    }
}

/// Selection reducer translated from Dart `selectionReducer`.
///
/// Returns `Some(next_state)` for handled actions, otherwise `None`.
pub fn selection_reducer(
    state: DrawState,
    action: &SelectionReducerAction,
    context: &DrawContext,
) -> Option<DrawState> {
    selection_reducer_with(&state, action, context)
}

/// Generic selection reducer variant using state/context adapters.
pub fn selection_reducer_with<S, C>(
    state: &S,
    action: &SelectionReducerAction,
    context: &C,
) -> Option<S>
where
    S: SelectionReducerState,
    C: SelectionReducerContext,
{
    match action {
        SelectionReducerAction::SelectElement(select) => {
            Some(handle_select_element(state, select, context))
        }
        SelectionReducerAction::ClearSelection(_) => {
            Some(state.apply_selection_ids(BTreeSet::new()))
        }
        SelectionReducerAction::SelectAll(_) => {
            Some(state.apply_selection_ids(state.all_element_ids()))
        }
        SelectionReducerAction::Other => None,
    }
}

fn handle_select_element<S, C>(state: &S, action: &SelectElement, context: &C) -> S
where
    S: SelectionReducerState,
    C: SelectionReducerContext,
{
    if !state.contains_element_id(&action.element_id) {
        context.on_selection_validation_failed("SelectElement", &action.element_id);
        return state.clone();
    }

    if !action.add_to_selection {
        let mut selected_ids = BTreeSet::new();
        selected_ids.insert(action.element_id.clone());
        return state.apply_selection_ids(selected_ids);
    }

    let mut next_selected_ids = state.selected_ids();
    if !next_selected_ids.insert(action.element_id.clone()) {
        next_selected_ids.remove(action.element_id.as_str());
    }

    state.apply_selection_ids(next_selected_ids)
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestState {
        all_ids: BTreeSet<String>,
        selected_ids: BTreeSet<String>,
    }

    impl SelectionReducerState for TestState {
        fn contains_element_id(&self, element_id: &str) -> bool {
            self.all_ids.contains(element_id)
        }

        fn selected_ids(&self) -> BTreeSet<String> {
            self.selected_ids.clone()
        }

        fn all_element_ids(&self) -> BTreeSet<String> {
            self.all_ids.clone()
        }

        fn apply_selection_ids(&self, selected_ids: BTreeSet<String>) -> Self {
            Self {
                all_ids: self.all_ids.clone(),
                selected_ids,
            }
        }
    }

    #[derive(Default)]
    struct TestContext {
        failures: Mutex<Vec<(String, String)>>,
    }

    impl SelectionReducerContext for TestContext {
        fn on_selection_validation_failed(&self, action: &str, element_id: &str) {
            let mut failures = self
                .failures
                .lock()
                .expect("TestContext.failures lock poisoned");
            failures.push((action.to_string(), element_id.to_string()));
        }
    }

    fn set(ids: &[&str]) -> BTreeSet<String> {
        ids.iter().map(|id| (*id).to_string()).collect()
    }

    #[test]
    fn select_element_replaces_selection_when_not_adding() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["b"]),
        };
        let action = SelectionReducerAction::SelectElement(SelectElement::new("a", false));
        let context = TestContext::default();

        let next = selection_reducer_with(&state, &action, &context)
            .expect("selection actions must be handled");

        assert_eq!(next.selected_ids, set(&["a"]));
    }

    #[test]
    fn select_element_toggles_membership_when_adding() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["a", "b"]),
        };
        let add_action = SelectionReducerAction::SelectElement(SelectElement::new("c", true));
        let remove_action = SelectionReducerAction::SelectElement(SelectElement::new("a", true));
        let context = TestContext::default();

        let added = selection_reducer_with(&state, &add_action, &context)
            .expect("selection actions must be handled");
        let removed = selection_reducer_with(&added, &remove_action, &context)
            .expect("selection actions must be handled");

        assert_eq!(added.selected_ids, set(&["a", "b", "c"]));
        assert_eq!(removed.selected_ids, set(&["b", "c"]));
    }

    #[test]
    fn clear_selection_sets_empty_set() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["a", "b"]),
        };
        let action = SelectionReducerAction::ClearSelection(ClearSelection);
        let context = TestContext::default();

        let next = selection_reducer_with(&state, &action, &context)
            .expect("selection actions must be handled");

        assert!(next.selected_ids.is_empty());
    }

    #[test]
    fn select_all_uses_all_element_ids() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["a"]),
        };
        let action = SelectionReducerAction::SelectAll(SelectAll);
        let context = TestContext::default();

        let next = selection_reducer_with(&state, &action, &context)
            .expect("selection actions must be handled");

        assert_eq!(next.selected_ids, set(&["a", "b", "c"]));
    }

    #[test]
    fn missing_element_keeps_state_and_reports_validation_failure() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["a"]),
        };
        let action = SelectionReducerAction::SelectElement(SelectElement::new("missing", false));
        let context = TestContext::default();

        let next = selection_reducer_with(&state, &action, &context)
            .expect("selection actions must be handled");

        assert_eq!(next, state);

        let failures = context
            .failures
            .lock()
            .expect("TestContext.failures lock poisoned");
        assert_eq!(failures.len(), 1);
        assert_eq!(
            failures[0],
            ("SelectElement".to_string(), "missing".to_string())
        );
    }

    #[test]
    fn unknown_action_is_not_handled() {
        let state = TestState {
            all_ids: set(&["a", "b", "c"]),
            selected_ids: set(&["a"]),
        };
        let context = TestContext::default();

        assert!(selection_reducer_with(&state, &SelectionReducerAction::Other, &context).is_none());
    }
}
