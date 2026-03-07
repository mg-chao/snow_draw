#![allow(dead_code)]

use std::collections::{HashMap, HashSet, VecDeque};

/// Options controlling which dependency kinds are considered.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DependencyFilter {
    pub include_serial_bindings: bool,
    pub include_arrow_bindings: bool,
}

impl DependencyFilter {
    pub const fn all() -> Self {
        Self {
            include_serial_bindings: true,
            include_arrow_bindings: true,
        }
    }
}

impl Default for DependencyFilter {
    fn default() -> Self {
        Self::all()
    }
}

/// Adapter trait used by dependency helpers in this module.
///
/// Implement this trait for the concrete element model so dependency flows can
/// stay shared and deterministic across delete/duplicate/history operations.
pub trait SerialNumberDependencyElement: Clone {
    /// Stable element identifier.
    fn id(&self) -> &str;

    /// Returns true when this element stores `SerialNumberData`.
    fn is_serial_number_element(&self) -> bool {
        false
    }

    /// Returns the serial-number companion text element id.
    fn serial_number_text_element_id(&self) -> Option<String> {
        None
    }

    /// Returns an updated element with the serial-number companion text id
    /// set to `text_element_id`.
    fn with_serial_number_text_element_id(&self, text_element_id: Option<String>) -> Self;

    /// Returns true when this element stores arrow-like endpoint bindings.
    fn is_arrow_like_element(&self) -> bool {
        false
    }

    /// Start endpoint binding target element id.
    fn arrow_start_binding_element_id(&self) -> Option<String> {
        None
    }

    /// End endpoint binding target element id.
    fn arrow_end_binding_element_id(&self) -> Option<String> {
        None
    }

    /// Returns an updated element with cleared arrow dependencies.
    ///
    /// Implementations should clear `start_is_special` / `end_is_special` for
    /// endpoints that are cleared, matching Dart `copyWith` behavior.
    fn with_cleared_arrow_bindings(&self, clear_start: bool, clear_end: bool) -> Self;
}

/// Expands `seed_ids` with transitive serial-number bound text dependencies.
pub fn expand_serial_number_bound_text_ids<'a, E, I, S>(elements: I, seed_ids: S) -> HashSet<String>
where
    E: SerialNumberDependencyElement + 'a,
    I: IntoIterator<Item = &'a E>,
    S: IntoIterator,
    S::Item: AsRef<str>,
{
    let mut serial_bindings = HashMap::<String, String>::new();
    for element in elements {
        if element.is_serial_number_element() {
            if let Some(text_element_id) = element.serial_number_text_element_id() {
                serial_bindings.insert(element.id().to_owned(), text_element_id.to_owned());
            }
        }
    }

    let mut expanded_ids = seed_ids
        .into_iter()
        .map(|id| id.as_ref().to_owned())
        .collect::<HashSet<_>>();
    let mut pending = VecDeque::from_iter(expanded_ids.iter().cloned());

    while let Some(id) = pending.pop_front() {
        let Some(bound_id) = serial_bindings.get(&id) else {
            continue;
        };

        if expanded_ids.insert(bound_id.clone()) {
            pending.push_back(bound_id.clone());
        }
    }

    expanded_ids
}

/// Returns whether `element` references any id in `target_ids`.
pub fn is_element_dependent_on_ids<E>(
    element: &E,
    target_ids: &HashSet<String>,
    filter: DependencyFilter,
) -> bool
where
    E: SerialNumberDependencyElement,
{
    if target_ids.is_empty() {
        return false;
    }

    if filter.include_serial_bindings && element.is_serial_number_element() {
        if let Some(bound_id) = element.serial_number_text_element_id() {
            if target_ids.contains(bound_id.as_str()) {
                return true;
            }
        }
    }

    if !filter.include_arrow_bindings || !element.is_arrow_like_element() {
        return false;
    }

    is_bound_to_any_targets(
        element.arrow_start_binding_element_id(),
        element.arrow_end_binding_element_id(),
        target_ids,
    )
}

/// Collects ids of elements that reference `target_ids`.
pub fn collect_dependent_element_ids<'a, E, I>(
    elements: I,
    target_ids: &HashSet<String>,
    excluded_ids: &HashSet<String>,
    filter: DependencyFilter,
) -> HashSet<String>
where
    E: SerialNumberDependencyElement + 'a,
    I: IntoIterator<Item = &'a E>,
{
    if target_ids.is_empty() {
        return HashSet::new();
    }

    let mut dependent_ids = HashSet::new();
    for element in elements {
        if excluded_ids.contains(element.id()) {
            continue;
        }
        if !is_element_dependent_on_ids(element, target_ids, filter) {
            continue;
        }
        dependent_ids.insert(element.id().to_owned());
    }

    dependent_ids
}

/// Clears references from `element` that target any id in `target_ids`.
///
/// When no dependency points to `target_ids`, the original element is returned
/// unchanged.
pub fn clear_element_dependencies_for_ids<E>(
    element: &E,
    target_ids: &HashSet<String>,
    filter: DependencyFilter,
) -> E
where
    E: SerialNumberDependencyElement,
{
    if target_ids.is_empty() {
        return element.clone();
    }

    if filter.include_serial_bindings && element.is_serial_number_element() {
        if let Some(bound_id) = element.serial_number_text_element_id() {
            if target_ids.contains(bound_id.as_str()) {
                return element.with_serial_number_text_element_id(None);
            }
        }
        return element.clone();
    }

    if !filter.include_arrow_bindings || !element.is_arrow_like_element() {
        return element.clone();
    }

    let clear_start = element
        .arrow_start_binding_element_id()
        .is_some_and(|id| target_ids.contains(id.as_str()));
    let clear_end = element
        .arrow_end_binding_element_id()
        .is_some_and(|id| target_ids.contains(id.as_str()));

    if !clear_start && !clear_end {
        return element.clone();
    }

    element.with_cleared_arrow_bindings(clear_start, clear_end)
}

fn is_bound_to_any_targets(
    start_binding_target_id: Option<String>,
    end_binding_target_id: Option<String>,
    target_ids: &HashSet<String>,
) -> bool {
    if target_ids.is_empty() {
        return false;
    }

    if start_binding_target_id
        .as_deref()
        .is_some_and(|id| target_ids.contains(id))
    {
        return true;
    }

    end_binding_target_id
        .as_deref()
        .is_some_and(|id| target_ids.contains(id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct FakeElement {
        id: String,
        serial_text_id: Option<String>,
        is_serial: bool,
        start_binding_id: Option<String>,
        end_binding_id: Option<String>,
        is_arrow: bool,
        start_is_special: Option<bool>,
        end_is_special: Option<bool>,
    }

    impl FakeElement {
        fn serial(id: &str, text_id: Option<&str>) -> Self {
            Self {
                id: id.to_owned(),
                serial_text_id: text_id.map(str::to_owned),
                is_serial: true,
                start_binding_id: None,
                end_binding_id: None,
                is_arrow: false,
                start_is_special: None,
                end_is_special: None,
            }
        }

        fn arrow(id: &str, start: Option<&str>, end: Option<&str>) -> Self {
            Self {
                id: id.to_owned(),
                serial_text_id: None,
                is_serial: false,
                start_binding_id: start.map(str::to_owned),
                end_binding_id: end.map(str::to_owned),
                is_arrow: true,
                start_is_special: Some(true),
                end_is_special: Some(false),
            }
        }
    }

    impl SerialNumberDependencyElement for FakeElement {
        fn id(&self) -> &str {
            &self.id
        }

        fn is_serial_number_element(&self) -> bool {
            self.is_serial
        }

        fn serial_number_text_element_id(&self) -> Option<String> {
            self.serial_text_id.clone()
        }

        fn with_serial_number_text_element_id(&self, text_element_id: Option<String>) -> Self {
            let mut next = self.clone();
            next.serial_text_id = text_element_id;
            next
        }

        fn is_arrow_like_element(&self) -> bool {
            self.is_arrow
        }

        fn arrow_start_binding_element_id(&self) -> Option<String> {
            self.start_binding_id.clone()
        }

        fn arrow_end_binding_element_id(&self) -> Option<String> {
            self.end_binding_id.clone()
        }

        fn with_cleared_arrow_bindings(&self, clear_start: bool, clear_end: bool) -> Self {
            let mut next = self.clone();
            if clear_start {
                next.start_binding_id = None;
                next.start_is_special = None;
            }
            if clear_end {
                next.end_binding_id = None;
                next.end_is_special = None;
            }
            next
        }
    }

    #[test]
    fn expands_transitive_serial_bindings() {
        let elements = vec![
            FakeElement::serial("serial-1", Some("text-1")),
            FakeElement::serial("text-1", Some("text-2")),
            FakeElement::serial("other", None),
        ];

        let expanded = expand_serial_number_bound_text_ids(&elements, ["serial-1"]);
        assert!(expanded.contains("serial-1"));
        assert!(expanded.contains("text-1"));
        assert!(expanded.contains("text-2"));
    }

    #[test]
    fn clears_arrow_binding_and_endpoint_flags() {
        let element = FakeElement::arrow("arrow-1", Some("target-start"), Some("target-end"));
        let targets = HashSet::from([String::from("target-start")]);

        let cleared =
            clear_element_dependencies_for_ids(&element, &targets, DependencyFilter::default());
        assert_eq!(cleared.start_binding_id, None);
        assert_eq!(cleared.start_is_special, None);
        assert_eq!(cleared.end_binding_id.as_deref(), Some("target-end"));
        assert_eq!(cleared.end_is_special, Some(false));
    }
}
