#![allow(dead_code)]

use std::collections::HashSet;

use crate::draw::models::element_state::ElementState;

/// Filters `elements` to visible elements, optionally excluding ids.
///
/// Mirrors Dart behavior:
/// `element.opacity > 0 && !excludedIds.contains(element.id)`.
pub fn resolve_visible_elements(
    elements: impl IntoIterator<Item = ElementState>,
    excluded_ids: Option<&HashSet<String>>,
) -> Vec<ElementState> {
    elements
        .into_iter()
        .filter(|element| {
            let is_excluded = excluded_ids
                .map(|ids| ids.contains(&element.id))
                .unwrap_or(false);
            element.opacity > 0.0 && !is_excluded
        })
        .collect()
}

/// Convenience wrapper that resolves visible elements with no exclusions.
pub fn resolve_visible_elements_without_exclusions(
    elements: impl IntoIterator<Item = ElementState>,
) -> Vec<ElementState> {
    resolve_visible_elements(elements, None)
}

#[cfg(test)]
mod tests {
    use super::{resolve_visible_elements, ElementState, HashSet};
    use crate::draw::types::draw_rect::DrawRect;
    use std::sync::Arc;

    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;

    fn element(id: &str, opacity: f64) -> ElementState {
        ElementState::new(
            id.to_owned(),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            opacity,
            0,
            Arc::new(RectangleData::default()),
        )
    }

    #[test]
    fn filters_out_non_positive_opacity() {
        let elements = vec![
            element("a", 1.0),
            element("b", 0.0),
            element("c", -0.5),
            element("d", 0.01),
        ];

        let visible = resolve_visible_elements(elements, None);
        let visible_ids: Vec<&str> = visible.iter().map(|element| element.id.as_str()).collect();
        assert_eq!(visible_ids, vec!["a", "d"]);
    }

    #[test]
    fn excludes_elements_by_id_when_requested() {
        let elements = vec![element("a", 1.0), element("b", 1.0), element("c", 1.0)];

        let excluded = HashSet::from([String::from("b"), String::from("c")]);
        let visible = resolve_visible_elements(elements, Some(&excluded));
        let visible_ids: Vec<&str> = visible.iter().map(|element| element.id.as_str()).collect();
        assert_eq!(visible_ids, vec!["a"]);
    }
}
