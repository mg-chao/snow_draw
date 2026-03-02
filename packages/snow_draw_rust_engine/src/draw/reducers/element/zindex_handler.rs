#![allow(dead_code)]

use std::collections::HashSet;

use crate::draw::core::draw_context::DrawContext;
use crate::draw::models::document_state::{
    DocumentState, DocumentStatePatch, ElementState as DocumentElementState,
};
use crate::draw::models::domain_state::DomainState;
use crate::draw::models::element_state::ElementState as EngineElementState;

/// Z-order mutation operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ZIndexOperation {
    BringToFront,
    SendToBack,
    BringForward,
    SendBackward,
}

impl ZIndexOperation {
    /// Returns a stable operation name used by diagnostics.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::BringToFront => "bringToFront",
            Self::SendToBack => "sendToBack",
            Self::BringForward => "bringForward",
            Self::SendBackward => "sendBackward",
        }
    }
}

/// Action payload for changing a single element z-index.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChangeElementZIndex {
    pub element_id: String,
    pub operation: ZIndexOperation,
}

impl ChangeElementZIndex {
    pub fn new(element_id: impl Into<String>, operation: ZIndexOperation) -> Self {
        Self {
            element_id: element_id.into(),
            operation,
        }
    }
}

/// Action payload for changing multiple elements z-index in one step.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChangeElementsZIndex {
    pub element_ids: Vec<String>,
    pub operation: ZIndexOperation,
}

impl ChangeElementsZIndex {
    pub fn new<I, T>(element_ids: I, operation: ZIndexOperation) -> Self
    where
        I: IntoIterator<Item = T>,
        T: Into<String>,
    {
        Self {
            element_ids: element_ids.into_iter().map(Into::into).collect(),
            operation,
        }
    }
}

/// Element shape required by z-index reducers.
pub trait ZIndexElement: Clone {
    fn id(&self) -> &str;
    fn z_index(&self) -> i64;
    fn with_z_index(&self, z_index: i64) -> Self;
}

impl ZIndexElement for DocumentElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn z_index(&self) -> i64 {
        self.z_index
    }

    fn with_z_index(&self, z_index: i64) -> Self {
        let mut next = self.clone();
        next.z_index = z_index;
        next
    }
}

impl ZIndexElement for EngineElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn z_index(&self) -> i64 {
        self.z_index
    }

    fn with_z_index(&self, z_index: i64) -> Self {
        self.copy_with(None, None, None, None, Some(z_index), None)
    }
}

/// Document adapter required by z-index reducers.
pub trait ZIndexReducerDocument: Clone {
    type Element: ZIndexElement;

    fn elements(&self) -> &[Self::Element];
    fn with_elements(&self, elements: Vec<Self::Element>) -> Self;
}

impl ZIndexReducerDocument for DocumentState {
    type Element = DocumentElementState;

    fn elements(&self) -> &[Self::Element] {
        &self.elements
    }

    fn with_elements(&self, elements: Vec<Self::Element>) -> Self {
        self.copy_with(DocumentStatePatch {
            elements: Some(elements),
            ..DocumentStatePatch::default()
        })
    }
}

/// Domain adapter required by z-index reducers.
pub trait ZIndexReducerDomain: Clone {
    type Document: ZIndexReducerDocument;

    fn document(&self) -> &Self::Document;
    fn with_document(&self, document: Self::Document) -> Self;
}

impl<D, S> ZIndexReducerDomain for DomainState<D, S>
where
    D: ZIndexReducerDocument,
    S: Clone + PartialEq,
{
    type Document = D;

    fn document(&self) -> &Self::Document {
        &self.document
    }

    fn with_document(&self, document: Self::Document) -> Self {
        self.copy_with(Some(document), None)
    }
}

/// State adapter required by z-index reducers.
pub trait ZIndexReducerState: Clone {
    type Domain: ZIndexReducerDomain;

    fn domain(&self) -> &Self::Domain;
    fn with_domain(&self, domain: Self::Domain) -> Self;
}

impl<D, S> ZIndexReducerState for DomainState<D, S>
where
    DomainState<D, S>: ZIndexReducerDomain + Clone,
{
    type Domain = Self;

    fn domain(&self) -> &Self::Domain {
        self
    }

    fn with_domain(&self, domain: Self::Domain) -> Self {
        domain
    }
}

/// Optional diagnostics hook for validation failures.
///
/// The default implementation is a no-op, but callers can supply a context
/// that forwards events to logging and event bus infrastructure.
pub trait ZIndexReducerContext {
    fn on_single_element_not_found(&self, _action: &ChangeElementZIndex) {}
    fn on_batch_elements_not_found(&self, _action: &ChangeElementsZIndex) {}
}

impl ZIndexReducerContext for DrawContext {}

type ReducerElement<S> = <<<S as ZIndexReducerState>::Domain as ZIndexReducerDomain>::Document as ZIndexReducerDocument>::Element;

/// Handles `ChangeElementZIndex`.
pub fn handle_change_z_index<S, C>(state: &S, action: &ChangeElementZIndex, context: &C) -> S
where
    S: ZIndexReducerState,
    C: ZIndexReducerContext + ?Sized,
{
    let elements = state.domain().document().elements();
    let Some(current_index) = elements
        .iter()
        .position(|element| element.id() == action.element_id)
    else {
        context.on_single_element_not_found(action);
        return state.clone();
    };

    let destination_index =
        resolve_single_destination_index(action.operation, current_index, elements.len());
    if destination_index == current_index {
        return reindex_document_if_needed(state, elements);
    }

    let mut reordered = elements.to_vec();
    let moved = reordered.remove(current_index);
    reordered.insert(destination_index, moved);
    reindex_and_apply(state, elements, reordered)
}

/// Handles `ChangeElementsZIndex`.
pub fn handle_change_z_index_batch<S, C>(state: &S, action: &ChangeElementsZIndex, context: &C) -> S
where
    S: ZIndexReducerState,
    C: ZIndexReducerContext + ?Sized,
{
    if action.element_ids.is_empty() {
        return state.clone();
    }

    let id_set = action
        .element_ids
        .iter()
        .map(String::as_str)
        .collect::<HashSet<_>>();

    let elements = state.domain().document().elements();
    let has_selected = elements.iter().any(|element| id_set.contains(element.id()));
    if !has_selected {
        context.on_batch_elements_not_found(action);
        return state.clone();
    }

    let reordered = match action.operation {
        ZIndexOperation::BringToFront => reorder_by_selection_partition(elements, &id_set, false),
        ZIndexOperation::SendToBack => reorder_by_selection_partition(elements, &id_set, true),
        ZIndexOperation::BringForward => move_selection_forward(elements, &id_set),
        ZIndexOperation::SendBackward => move_selection_backward(elements, &id_set),
    };

    if has_same_order(elements, &reordered) {
        return reindex_document_if_needed(state, elements);
    }

    reindex_and_apply(state, elements, reordered)
}

#[derive(Debug)]
struct SelectionPartition<E> {
    selected: Vec<E>,
    unselected: Vec<E>,
}

fn partition_elements_by_selection<E>(
    elements: &[E],
    id_set: &HashSet<&str>,
) -> SelectionPartition<E>
where
    E: ZIndexElement,
{
    let mut selected = Vec::new();
    let mut unselected = Vec::new();

    for element in elements {
        if id_set.contains(element.id()) {
            selected.push(element.clone());
        } else {
            unselected.push(element.clone());
        }
    }

    SelectionPartition {
        selected,
        unselected,
    }
}

fn reorder_by_selection_partition<E>(
    elements: &[E],
    id_set: &HashSet<&str>,
    selected_first: bool,
) -> Vec<E>
where
    E: ZIndexElement,
{
    let partition = partition_elements_by_selection(elements, id_set);
    if selected_first {
        partition
            .selected
            .into_iter()
            .chain(partition.unselected)
            .collect()
    } else {
        partition
            .unselected
            .into_iter()
            .chain(partition.selected)
            .collect()
    }
}

fn move_selection_forward<E>(elements: &[E], id_set: &HashSet<&str>) -> Vec<E>
where
    E: ZIndexElement,
{
    let mut reordered = elements.to_vec();
    if reordered.len() < 2 {
        return reordered;
    }

    for i in (0..(reordered.len() - 1)).rev() {
        let current_selected = id_set.contains(reordered[i].id());
        let next_selected = id_set.contains(reordered[i + 1].id());
        if current_selected && !next_selected {
            reordered.swap(i, i + 1);
        }
    }
    reordered
}

fn move_selection_backward<E>(elements: &[E], id_set: &HashSet<&str>) -> Vec<E>
where
    E: ZIndexElement,
{
    let mut reordered = elements.to_vec();
    for i in 1..reordered.len() {
        let current_selected = id_set.contains(reordered[i].id());
        let previous_selected = id_set.contains(reordered[i - 1].id());
        if current_selected && !previous_selected {
            reordered.swap(i - 1, i);
        }
    }
    reordered
}

fn resolve_single_destination_index(
    operation: ZIndexOperation,
    current_index: usize,
    length: usize,
) -> usize {
    let last_index = length.saturating_sub(1);
    match operation {
        ZIndexOperation::BringToFront => last_index,
        ZIndexOperation::SendToBack => 0,
        ZIndexOperation::BringForward => (current_index + 1).min(last_index),
        ZIndexOperation::SendBackward => current_index.saturating_sub(1),
    }
}

fn has_same_order<E>(before: &[E], after: &[E]) -> bool
where
    E: ZIndexElement,
{
    before.len() == after.len()
        && before
            .iter()
            .zip(after.iter())
            .all(|(left, right)| left.id() == right.id())
}

fn reindex_document_if_needed<S>(state: &S, elements: &[ReducerElement<S>]) -> S
where
    S: ZIndexReducerState,
{
    reindex_and_apply(state, elements, elements.to_vec())
}

fn reindex_and_apply<S>(
    state: &S,
    source: &[ReducerElement<S>],
    reordered: Vec<ReducerElement<S>>,
) -> S
where
    S: ZIndexReducerState,
{
    let same_order = has_same_order(source, &reordered);
    let reindexed = reindex_elements(&reordered);
    if same_order && reindexed.is_none() {
        return state.clone();
    }

    let next_elements = reindexed.unwrap_or(reordered);
    let next_document = state.domain().document().with_elements(next_elements);
    let next_domain = state.domain().with_document(next_document);
    state.with_domain(next_domain)
}

fn reindex_elements<E>(elements: &[E]) -> Option<Vec<E>>
where
    E: ZIndexElement,
{
    let mut has_any_z_index_change = false;
    let mut reindexed = Vec::with_capacity(elements.len());
    for (index, element) in elements.iter().enumerate() {
        let expected_z_index = index as i64;
        if element.z_index() == expected_z_index {
            reindexed.push(element.clone());
            continue;
        }

        has_any_z_index_change = true;
        reindexed.push(element.with_z_index(expected_z_index));
    }

    if has_any_z_index_change {
        Some(reindexed)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestElement {
        id: String,
        z_index: i64,
    }

    impl TestElement {
        fn new(id: &str, z_index: i64) -> Self {
            Self {
                id: id.to_string(),
                z_index,
            }
        }
    }

    impl ZIndexElement for TestElement {
        fn id(&self) -> &str {
            &self.id
        }

        fn z_index(&self) -> i64 {
            self.z_index
        }

        fn with_z_index(&self, z_index: i64) -> Self {
            Self {
                id: self.id.clone(),
                z_index,
            }
        }
    }

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestDocument {
        elements: Vec<TestElement>,
    }

    impl ZIndexReducerDocument for TestDocument {
        type Element = TestElement;

        fn elements(&self) -> &[Self::Element] {
            &self.elements
        }

        fn with_elements(&self, elements: Vec<Self::Element>) -> Self {
            Self { elements }
        }
    }

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestDomain {
        document: TestDocument,
    }

    impl ZIndexReducerDomain for TestDomain {
        type Document = TestDocument;

        fn document(&self) -> &Self::Document {
            &self.document
        }

        fn with_document(&self, document: Self::Document) -> Self {
            Self { document }
        }
    }

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestState {
        domain: TestDomain,
    }

    impl ZIndexReducerState for TestState {
        type Domain = TestDomain;

        fn domain(&self) -> &Self::Domain {
            &self.domain
        }

        fn with_domain(&self, domain: Self::Domain) -> Self {
            Self { domain }
        }
    }

    #[derive(Default)]
    struct TestContext {
        single_failures: Cell<usize>,
        batch_failures: Cell<usize>,
    }

    impl ZIndexReducerContext for TestContext {
        fn on_single_element_not_found(&self, _action: &ChangeElementZIndex) {
            self.single_failures.set(self.single_failures.get() + 1);
        }

        fn on_batch_elements_not_found(&self, _action: &ChangeElementsZIndex) {
            self.batch_failures.set(self.batch_failures.get() + 1);
        }
    }

    fn state_with_elements(ids: &[&str]) -> TestState {
        let elements = ids
            .iter()
            .enumerate()
            .map(|(index, id)| TestElement::new(id, index as i64))
            .collect::<Vec<_>>();
        TestState {
            domain: TestDomain {
                document: TestDocument { elements },
            },
        }
    }

    fn ids(state: &TestState) -> Vec<&str> {
        state
            .domain
            .document
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect()
    }

    fn z_indexes(state: &TestState) -> Vec<i64> {
        state
            .domain
            .document
            .elements
            .iter()
            .map(|element| element.z_index)
            .collect()
    }

    #[test]
    fn single_bring_to_front_reorders_and_reindexes() {
        let state = state_with_elements(&["a", "b", "c"]);
        let action = ChangeElementZIndex::new("b", ZIndexOperation::BringToFront);

        let next = handle_change_z_index(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["a", "c", "b"]);
        assert_eq!(z_indexes(&next), vec![0, 1, 2]);
    }

    #[test]
    fn single_not_found_returns_same_state_and_reports() {
        let state = state_with_elements(&["a", "b"]);
        let context = TestContext::default();
        let action = ChangeElementZIndex::new("missing", ZIndexOperation::BringForward);

        let next = handle_change_z_index(&state, &action, &context);

        assert_eq!(next, state);
        assert_eq!(context.single_failures.get(), 1);
    }

    #[test]
    fn single_no_order_change_still_reindexes_when_needed() {
        let mut state = state_with_elements(&["a", "b"]);
        state.domain.document.elements[0].z_index = 40;
        state.domain.document.elements[1].z_index = 41;
        let action = ChangeElementZIndex::new("b", ZIndexOperation::BringToFront);

        let next = handle_change_z_index(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["a", "b"]);
        assert_eq!(z_indexes(&next), vec![0, 1]);
    }

    #[test]
    fn batch_bring_to_front_moves_selected_to_end_preserving_relative_order() {
        let state = state_with_elements(&["a", "b", "c", "d"]);
        let action = ChangeElementsZIndex::new(["a", "c"], ZIndexOperation::BringToFront);

        let next = handle_change_z_index_batch(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["b", "d", "a", "c"]);
        assert_eq!(z_indexes(&next), vec![0, 1, 2, 3]);
    }

    #[test]
    fn batch_send_to_back_moves_selected_to_start_preserving_relative_order() {
        let state = state_with_elements(&["a", "b", "c", "d"]);
        let action = ChangeElementsZIndex::new(["b", "d"], ZIndexOperation::SendToBack);

        let next = handle_change_z_index_batch(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["b", "d", "a", "c"]);
        assert_eq!(z_indexes(&next), vec![0, 1, 2, 3]);
    }

    #[test]
    fn batch_bring_forward_moves_selection_one_step_up() {
        let state = state_with_elements(&["a", "b", "c", "d"]);
        let action = ChangeElementsZIndex::new(["a", "c"], ZIndexOperation::BringForward);

        let next = handle_change_z_index_batch(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["b", "a", "d", "c"]);
        assert_eq!(z_indexes(&next), vec![0, 1, 2, 3]);
    }

    #[test]
    fn batch_send_backward_moves_selection_one_step_down() {
        let state = state_with_elements(&["a", "b", "c", "d"]);
        let action = ChangeElementsZIndex::new(["b", "d"], ZIndexOperation::SendBackward);

        let next = handle_change_z_index_batch(&state, &action, &TestContext::default());

        assert_eq!(ids(&next), vec!["b", "a", "d", "c"]);
        assert_eq!(z_indexes(&next), vec![0, 1, 2, 3]);
    }

    #[test]
    fn batch_empty_selection_returns_same_state() {
        let state = state_with_elements(&["a", "b"]);
        let action = ChangeElementsZIndex::new(Vec::<String>::new(), ZIndexOperation::BringToFront);

        let next = handle_change_z_index_batch(&state, &action, &TestContext::default());

        assert_eq!(next, state);
    }

    #[test]
    fn batch_not_found_returns_same_state_and_reports() {
        let state = state_with_elements(&["a", "b"]);
        let context = TestContext::default();
        let action =
            ChangeElementsZIndex::new(["missing-a", "missing-b"], ZIndexOperation::SendToBack);

        let next = handle_change_z_index_batch(&state, &action, &context);

        assert_eq!(next, state);
        assert_eq!(context.batch_failures.get(), 1);
    }
}
