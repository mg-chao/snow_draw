#![allow(dead_code)]

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::types::serial_number::serial_number_dependencies::{
    clear_element_dependencies_for_ids, expand_serial_number_bound_text_ids,
    is_element_dependent_on_ids, DependencyFilter, SerialNumberDependencyElement,
};
use crate::draw::models::document_state::{
    ArrowBinding, ArrowLikeData, ElementData, ElementState as DocumentElementState,
};
use crate::draw::types::draw_point::DrawPoint;

/// Delete-elements action payload.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DeleteElements {
    pub element_ids: Vec<String>,
}

impl DeleteElements {
    pub fn new<I, S>(element_ids: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        Self {
            element_ids: element_ids.into_iter().map(Into::into).collect(),
        }
    }
}

/// Duplicate-elements action payload.
#[derive(Clone, Debug, PartialEq)]
pub struct DuplicateElements {
    pub element_ids: Vec<String>,
    pub offset_x: f64,
    pub offset_y: f64,
}

impl DuplicateElements {
    pub fn new<I, S>(element_ids: I, offset_x: f64, offset_y: f64) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        Self {
            element_ids: element_ids.into_iter().map(Into::into).collect(),
            offset_x,
            offset_y,
        }
    }
}

/// State adapter required by delete/duplicate reducers.
///
/// This keeps the reducer compile-friendly while aggregate draw-state
/// translation is still in progress.
pub trait ElementReducerState: Clone {
    type Element: ElementReducerElement;

    fn elements(&self) -> &[Self::Element];
    fn selected_ids(&self) -> &BTreeSet<String>;

    fn with_elements_and_selection(
        &self,
        elements: Vec<Self::Element>,
        selected_ids: BTreeSet<String>,
    ) -> Self;
}

/// Element adapter required by delete/duplicate reducers.
pub trait ElementReducerElement: SerialNumberDependencyElement + Clone {
    fn z_index(&self) -> i64;

    fn duplicate_with_remapped_references(
        &self,
        new_id: String,
        offset_x: f64,
        offset_y: f64,
        z_index: i64,
        id_map: &HashMap<String, String>,
    ) -> Self;
}

/// Context adapter required by duplicate reducer.
pub trait ElementReducerContext {
    fn next_id(&self) -> String;

    fn report_duplicate_validation_failure(&self, _failure: DuplicateValidationFailure) {}
}

impl ElementReducerContext for DrawContext {
    fn next_id(&self) -> String {
        DrawContext::next_id(self)
    }
}

/// Structured duplicate-validation diagnostics payload.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DuplicateValidationFailure {
    pub action: &'static str,
    pub log_message: String,
    pub reason: String,
    pub details: BTreeMap<String, String>,
    pub log_details: BTreeMap<String, String>,
}

/// Deletes elements and clears references from remaining dependent elements.
pub fn handle_delete_elements<S, C>(state: &S, action: &DeleteElements, _context: &C) -> S
where
    S: ElementReducerState,
{
    let delete_ids = resolve_delete_ids(
        state.elements(),
        action.element_ids.iter().map(String::as_str),
    );
    if delete_ids.is_empty() {
        return state.clone();
    }

    let next_elements = build_elements_after_deletion(state.elements(), &delete_ids);
    let next_selected_ids = next_selection_after_deletion(state.selected_ids(), &delete_ids);

    state.with_elements_and_selection(next_elements, next_selected_ids)
}

/// Duplicates selected elements with deterministic z-index assignment and ID remapping.
pub fn handle_duplicate_elements<S, C>(state: &S, action: &DuplicateElements, context: &C) -> S
where
    S: ElementReducerState,
    C: ElementReducerContext,
{
    if action.element_ids.is_empty() {
        return report_duplicate_validation_failure(
            state,
            context,
            "Duplicate failed: empty selection",
            "No element ids provided",
            None,
            None,
        );
    }

    let selected_ids = action.element_ids.iter().cloned().collect::<BTreeSet<_>>();
    let ids_to_duplicate =
        resolve_delete_ids(state.elements(), selected_ids.iter().map(String::as_str));

    let source_elements = elements_by_ids(state.elements(), &ids_to_duplicate);
    if source_elements.is_empty() {
        let mut details = BTreeMap::new();
        details.insert("elementIds".to_owned(), action.element_ids.join(","));

        let mut log_details = BTreeMap::new();
        log_details.insert("elementIds".to_owned(), action.element_ids.join(","));

        return report_duplicate_validation_failure(
            state,
            context,
            "Duplicate failed: no elements found",
            "No valid elements to duplicate",
            Some(details),
            Some(log_details),
        );
    }

    let id_map = source_elements
        .iter()
        .map(|element| (element.id().to_owned(), context.next_id()))
        .collect::<HashMap<_, _>>();

    let duplicated = build_duplicated_elements(
        &source_elements,
        &selected_ids,
        &id_map,
        action.offset_x,
        action.offset_y,
        resolve_next_z_index(state.elements()),
    );

    let mut merged_elements = state.elements().to_vec();
    merged_elements.extend(duplicated.elements);

    state.with_elements_and_selection(merged_elements, duplicated.selected_ids)
}

fn resolve_delete_ids<'a, E, I, S>(elements: I, requested_ids: S) -> HashSet<String>
where
    E: ElementReducerElement + 'a,
    I: IntoIterator<Item = &'a E>,
    S: IntoIterator,
    S::Item: AsRef<str>,
{
    let elements = elements.into_iter().collect::<Vec<_>>();
    let existing_ids = elements
        .iter()
        .map(|element| element.id().to_owned())
        .collect::<HashSet<_>>();

    let valid_requested_ids = requested_ids
        .into_iter()
        .map(|id| id.as_ref().to_owned())
        .filter(|id| existing_ids.contains(id.as_str()))
        .collect::<Vec<_>>();

    expand_serial_number_bound_text_ids(
        elements.iter().copied(),
        valid_requested_ids.iter().map(String::as_str),
    )
}

fn build_elements_after_deletion<E>(elements: &[E], delete_ids: &HashSet<String>) -> Vec<E>
where
    E: ElementReducerElement,
{
    elements
        .iter()
        .filter(|element| !delete_ids.contains(element.id()))
        .map(|element| apply_delete_element_updates(element, delete_ids))
        .collect()
}

fn apply_delete_element_updates<E>(element: &E, delete_ids: &HashSet<String>) -> E
where
    E: ElementReducerElement,
{
    if !is_element_dependent_on_ids(element, delete_ids, DependencyFilter::default()) {
        return element.clone();
    }

    clear_element_dependencies_for_ids(element, delete_ids, DependencyFilter::default())
}

fn next_selection_after_deletion(
    selected_ids: &BTreeSet<String>,
    deleted_ids: &HashSet<String>,
) -> BTreeSet<String> {
    if !selected_ids
        .iter()
        .any(|selected_id| deleted_ids.contains(selected_id.as_str()))
    {
        return selected_ids.clone();
    }

    selected_ids
        .iter()
        .filter(|selected_id| !deleted_ids.contains(selected_id.as_str()))
        .cloned()
        .collect()
}

fn elements_by_ids<E>(elements: &[E], ids: &HashSet<String>) -> Vec<E>
where
    E: ElementReducerElement,
{
    elements
        .iter()
        .filter(|element| ids.contains(element.id()))
        .cloned()
        .collect()
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct DuplicatedElements<E> {
    elements: Vec<E>,
    selected_ids: BTreeSet<String>,
}

fn build_duplicated_elements<E>(
    source_elements: &[E],
    selected_ids: &BTreeSet<String>,
    id_map: &HashMap<String, String>,
    offset_x: f64,
    offset_y: f64,
    start_z_index: i64,
) -> DuplicatedElements<E>
where
    E: ElementReducerElement,
{
    let mut duplicated_elements = Vec::<E>::with_capacity(source_elements.len());
    let mut duplicated_selected_ids = BTreeSet::<String>::new();
    let mut next_z_index = start_z_index;

    for element in source_elements {
        let Some(new_id) = id_map.get(element.id()) else {
            continue;
        };

        duplicated_elements.push(element.duplicate_with_remapped_references(
            new_id.clone(),
            offset_x,
            offset_y,
            next_z_index,
            id_map,
        ));
        next_z_index += 1;

        if selected_ids.contains(element.id()) {
            duplicated_selected_ids.insert(new_id.clone());
        }
    }

    DuplicatedElements {
        elements: duplicated_elements,
        selected_ids: duplicated_selected_ids,
    }
}

fn resolve_next_z_index<E>(elements: &[E]) -> i64
where
    E: ElementReducerElement,
{
    let mut max_z_index = -1_i64;
    for element in elements {
        if element.z_index() > max_z_index {
            max_z_index = element.z_index();
        }
    }
    max_z_index + 1
}

fn report_duplicate_validation_failure<S, C>(
    state: &S,
    context: &C,
    log_message: &str,
    reason: &str,
    details: Option<BTreeMap<String, String>>,
    log_details: Option<BTreeMap<String, String>>,
) -> S
where
    S: Clone,
    C: ElementReducerContext,
{
    context.report_duplicate_validation_failure(DuplicateValidationFailure {
        action: "DuplicateElements",
        log_message: log_message.to_owned(),
        reason: reason.to_owned(),
        details: details.unwrap_or_default(),
        log_details: log_details.unwrap_or_default(),
    });

    state.clone()
}

impl SerialNumberDependencyElement for DocumentElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn is_serial_number_element(&self) -> bool {
        matches!(self.data, ElementData::SerialNumber(_))
    }

    fn serial_number_text_element_id(&self) -> Option<String> {
        match &self.data {
            ElementData::SerialNumber(data) => data.text_element_id.clone(),
            _ => None,
        }
    }

    fn with_serial_number_text_element_id(&self, text_element_id: Option<String>) -> Self {
        let mut next = self.clone();
        if let ElementData::SerialNumber(data) = &self.data {
            let mut next_data = data.clone();
            next_data.text_element_id = text_element_id;
            next.data = ElementData::SerialNumber(next_data);
        }
        next
    }

    fn is_arrow_like_element(&self) -> bool {
        matches!(self.data, ElementData::ArrowLike(_))
    }

    fn arrow_start_binding_element_id(&self) -> Option<String> {
        match &self.data {
            ElementData::ArrowLike(data) => data
                .start_binding
                .as_ref()
                .map(|binding| binding.element_id.clone()),
            _ => None,
        }
    }

    fn arrow_end_binding_element_id(&self) -> Option<String> {
        match &self.data {
            ElementData::ArrowLike(data) => data
                .end_binding
                .as_ref()
                .map(|binding| binding.element_id.clone()),
            _ => None,
        }
    }

    fn with_cleared_arrow_bindings(&self, clear_start: bool, clear_end: bool) -> Self {
        let mut next = self.clone();

        if let ElementData::ArrowLike(data) = &self.data {
            let next_arrow = data.copy_with(
                if clear_start { Some(None) } else { None },
                if clear_end { Some(None) } else { None },
            );
            next.data = ElementData::ArrowLike(next_arrow);
        }

        next
    }
}

impl ElementReducerElement for DocumentElementState {
    fn z_index(&self) -> i64 {
        self.z_index
    }

    fn duplicate_with_remapped_references(
        &self,
        new_id: String,
        offset_x: f64,
        offset_y: f64,
        z_index: i64,
        id_map: &HashMap<String, String>,
    ) -> Self {
        let mut duplicated = self.clone();
        duplicated.id = new_id;
        duplicated.rect = self.rect.translate(DrawPoint::new(offset_x, offset_y));
        duplicated.z_index = z_index;
        duplicated.data = duplicate_data_with_remapped_references(&self.data, id_map);
        duplicated
    }
}

fn duplicate_data_with_remapped_references(
    data: &ElementData,
    id_map: &HashMap<String, String>,
) -> ElementData {
    match data {
        ElementData::SerialNumber(serial_data) => {
            let mut duplicated = serial_data.clone();
            duplicated.text_element_id = serial_data
                .text_element_id
                .as_ref()
                .and_then(|text_element_id| id_map.get(text_element_id).cloned());
            ElementData::SerialNumber(duplicated)
        }
        ElementData::ArrowLike(data) => ElementData::ArrowLike(remap_arrow_bindings(data, id_map)),
        _ => data.clone(),
    }
}

fn remap_arrow_bindings(data: &ArrowLikeData, id_map: &HashMap<String, String>) -> ArrowLikeData {
    if data.start_binding.is_none() && data.end_binding.is_none() {
        return data.clone();
    }

    let mapped_start = remap_binding(data.start_binding.as_ref(), id_map);
    let mapped_end = remap_binding(data.end_binding.as_ref(), id_map);

    data.copy_with(Some(mapped_start), Some(mapped_end))
}

fn remap_binding(
    binding: Option<&ArrowBinding>,
    id_map: &HashMap<String, String>,
) -> Option<ArrowBinding> {
    let binding = binding?;
    let target_id = id_map.get(binding.element_id.as_str())?;
    Some(ArrowBinding::new(target_id.clone()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::VecDeque;

    use crate::draw::models::document_state::{ArrowLikeData, ElementState, SerialNumberData};
    use crate::draw::types::draw_rect::DrawRect;

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        elements: Vec<ElementState>,
        selected_ids: BTreeSet<String>,
    }

    impl ElementReducerState for TestState {
        type Element = ElementState;

        fn elements(&self) -> &[Self::Element] {
            &self.elements
        }

        fn selected_ids(&self) -> &BTreeSet<String> {
            &self.selected_ids
        }

        fn with_elements_and_selection(
            &self,
            elements: Vec<Self::Element>,
            selected_ids: BTreeSet<String>,
        ) -> Self {
            Self {
                elements,
                selected_ids,
            }
        }
    }

    #[derive(Default)]
    struct TestContext {
        generated_ids: RefCell<VecDeque<String>>,
        failures: RefCell<Vec<DuplicateValidationFailure>>,
    }

    impl TestContext {
        fn with_generated_ids(ids: &[&str]) -> Self {
            Self {
                generated_ids: RefCell::new(ids.iter().map(|id| (*id).to_owned()).collect()),
                failures: RefCell::new(Vec::new()),
            }
        }
    }

    impl ElementReducerContext for TestContext {
        fn next_id(&self) -> String {
            self.generated_ids
                .borrow_mut()
                .pop_front()
                .unwrap_or_else(|| "generated-id".to_owned())
        }

        fn report_duplicate_validation_failure(&self, failure: DuplicateValidationFailure) {
            self.failures.borrow_mut().push(failure);
        }
    }

    fn rect() -> DrawRect {
        DrawRect::new(0.0, 0.0, 10.0, 10.0)
    }

    fn ids(values: &[&str]) -> BTreeSet<String> {
        values.iter().map(|value| (*value).to_owned()).collect()
    }

    fn element(id: &str, z_index: i64, data: ElementData) -> ElementState {
        ElementState::new(id.to_owned(), rect(), 0.0, 1.0, z_index, data)
    }

    #[test]
    fn delete_removes_requested_element_and_serial_bound_text() {
        let state = TestState {
            elements: vec![
                element(
                    "serial-1",
                    1,
                    ElementData::SerialNumber(SerialNumberData {
                        text_element_id: Some("text-1".to_owned()),
                    }),
                ),
                element("text-1", 2, ElementData::Text),
                element("keep", 3, ElementData::Rectangle),
            ],
            selected_ids: ids(&["serial-1", "text-1", "keep"]),
        };

        let next = handle_delete_elements(&state, &DeleteElements::new(["serial-1"]), &());

        assert_eq!(next.elements.len(), 1);
        assert_eq!(next.elements[0].id, "keep");
        assert_eq!(next.selected_ids, ids(&["keep"]));
    }

    #[test]
    fn duplicate_remaps_serial_and_arrow_references() {
        let state = TestState {
            elements: vec![
                element(
                    "serial-1",
                    2,
                    ElementData::SerialNumber(SerialNumberData {
                        text_element_id: Some("text-1".to_owned()),
                    }),
                ),
                element("text-1", 4, ElementData::Text),
                element(
                    "arrow-1",
                    6,
                    ElementData::ArrowLike(ArrowLikeData {
                        start_binding: Some(ArrowBinding::new("serial-1")),
                        end_binding: Some(ArrowBinding::new("external-target")),
                    }),
                ),
            ],
            selected_ids: ids(&["serial-1", "arrow-1"]),
        };

        let context = TestContext::with_generated_ids(&["dup-serial", "dup-text", "dup-arrow"]);
        let action = DuplicateElements::new(["serial-1", "arrow-1"], 12.0, -3.0);

        let next = handle_duplicate_elements(&state, &action, &context);

        assert_eq!(next.elements.len(), 6);

        let duplicated_serial = next
            .elements
            .iter()
            .find(|element| element.id == "dup-serial")
            .expect("duplicated serial must exist");

        let duplicated_text = next
            .elements
            .iter()
            .find(|element| element.id == "dup-text")
            .expect("duplicated text must exist");

        let duplicated_arrow = next
            .elements
            .iter()
            .find(|element| element.id == "dup-arrow")
            .expect("duplicated arrow must exist");

        assert_eq!(duplicated_serial.rect.min_x, 12.0);
        assert_eq!(duplicated_serial.rect.min_y, -3.0);
        assert_eq!(duplicated_serial.z_index, 7);
        assert_eq!(duplicated_text.z_index, 8);
        assert_eq!(duplicated_arrow.z_index, 9);

        match &duplicated_serial.data {
            ElementData::SerialNumber(data) => {
                assert_eq!(data.text_element_id.as_deref(), Some("dup-text"));
            }
            _ => panic!("duplicated serial data must stay serial-number"),
        }

        match &duplicated_arrow.data {
            ElementData::ArrowLike(data) => {
                assert_eq!(
                    data.start_binding
                        .as_ref()
                        .map(|value| value.element_id.as_str()),
                    Some("dup-serial")
                );
                assert!(data.end_binding.is_none());
            }
            _ => panic!("duplicated arrow data must stay arrow-like"),
        }

        assert_eq!(next.selected_ids, ids(&["dup-arrow", "dup-serial"]));
        assert!(context.failures.borrow().is_empty());
    }

    #[test]
    fn duplicate_with_empty_selection_reports_validation_failure() {
        let state = TestState {
            elements: vec![element("only", 0, ElementData::Rectangle)],
            selected_ids: BTreeSet::new(),
        };
        let context = TestContext::default();

        let next = handle_duplicate_elements(
            &state,
            &DuplicateElements::new(Vec::<String>::new(), 0.0, 0.0),
            &context,
        );

        assert_eq!(next, state);

        let failures = context.failures.borrow();
        assert_eq!(failures.len(), 1);
        assert_eq!(failures[0].action, "DuplicateElements");
        assert_eq!(failures[0].reason, "No element ids provided");
    }
}
