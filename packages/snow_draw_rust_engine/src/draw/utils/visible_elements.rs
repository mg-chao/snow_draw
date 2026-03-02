#![allow(dead_code)]

use std::collections::HashSet;

/// Minimal element model required by [`resolve_visible_elements`].
///
/// This keeps the utility compile-friendly while the full `models::ElementState`
/// translation is still in progress.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementState {
    pub id: String,
    pub opacity: f64,
}

impl ElementState {
    pub fn new(id: impl Into<String>, opacity: f64) -> Self {
        Self {
            id: id.into(),
            opacity,
        }
    }
}

/// Visibility contract for elements filtered by [`resolve_visible_elements`].
pub trait VisibleElement {
    fn id(&self) -> &str;
    fn opacity(&self) -> f64;
}

impl VisibleElement for ElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn opacity(&self) -> f64 {
        self.opacity
    }
}

/// Filters `elements` to visible elements, optionally excluding ids.
///
/// Mirrors Dart behavior:
/// `element.opacity > 0 && !excludedIds.contains(element.id)`.
pub fn resolve_visible_elements<T>(
    elements: impl IntoIterator<Item = T>,
    excluded_ids: Option<&HashSet<String>>,
) -> Vec<T>
where
    T: VisibleElement,
{
    elements
        .into_iter()
        .filter(|element| {
            let is_excluded = excluded_ids
                .map(|ids| ids.contains(element.id()))
                .unwrap_or(false);
            element.opacity() > 0.0 && !is_excluded
        })
        .collect()
}

/// Convenience wrapper that resolves visible elements with no exclusions.
pub fn resolve_visible_elements_without_exclusions<T>(
    elements: impl IntoIterator<Item = T>,
) -> Vec<T>
where
    T: VisibleElement,
{
    resolve_visible_elements(elements, None)
}

#[cfg(test)]
mod tests {
    use super::{resolve_visible_elements, ElementState};
    use std::collections::HashSet;

    #[test]
    fn filters_out_non_positive_opacity() {
        let elements = vec![
            ElementState::new("a", 1.0),
            ElementState::new("b", 0.0),
            ElementState::new("c", -0.5),
            ElementState::new("d", 0.01),
        ];

        let visible = resolve_visible_elements(elements, None);
        let visible_ids: Vec<&str> = visible.iter().map(|element| element.id.as_str()).collect();
        assert_eq!(visible_ids, vec!["a", "d"]);
    }

    #[test]
    fn excludes_elements_by_id_when_requested() {
        let elements = vec![
            ElementState::new("a", 1.0),
            ElementState::new("b", 1.0),
            ElementState::new("c", 1.0),
        ];

        let excluded = HashSet::from([String::from("b"), String::from("c")]);
        let visible = resolve_visible_elements(elements, Some(&excluded));
        let visible_ids: Vec<&str> = visible.iter().map(|element| element.id.as_str()).collect();
        assert_eq!(visible_ids, vec!["a"]);
    }
}
