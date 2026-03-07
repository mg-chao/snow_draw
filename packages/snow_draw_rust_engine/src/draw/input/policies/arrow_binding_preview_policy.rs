#![allow(dead_code)]

use crate::draw::config::draw_config::SnapConfig;
use crate::draw::elements::types::arrow::arrow_binding_snapper::ArrowBindingSnapper;
use crate::draw::models::document_state::{DocumentState, ElementData, ElementState};
use crate::draw::types::draw_point::DrawPoint;

/// Returns whether arrow binding preview should be evaluated.
pub fn should_preview_arrow_binding(snap_config: &SnapConfig, snap_override_active: bool) -> bool {
    ArrowBindingSnapper::should_attempt_binding(snap_config, snap_override_active)
}

/// Minimal element capabilities required by arrow-binding preview.
pub trait ArrowBindingPreviewElement {
    fn opacity(&self) -> f64;
    fn is_bindable_target(&self) -> bool;
}

/// Minimal state/document capabilities required by arrow-binding preview.
pub trait ArrowBindingPreviewState {
    type Element: ArrowBindingPreviewElement + Clone;

    fn visit_elements_at_point_top_down<F>(&self, position: DrawPoint, distance: f64, visitor: F)
    where
        F: FnMut(&Self::Element) -> bool;
}

/// Resolves bindable targets near `position`.
pub fn resolve_arrow_binding_targets<S>(
    state: &S,
    position: DrawPoint,
    distance: f64,
) -> Vec<S::Element>
where
    S: ArrowBindingPreviewState,
{
    if distance <= 0.0 {
        return Vec::new();
    }

    let mut targets = Vec::<S::Element>::new();
    state.visit_elements_at_point_top_down(position, distance, |element| {
        if element.opacity() <= 0.0 || !element.is_bindable_target() {
            return true;
        }

        targets.push(element.clone());
        false
    });
    targets
}

/// Convenience wrapper for the translated `DocumentState`.
pub fn resolve_arrow_binding_targets_in_document(
    document: &DocumentState,
    position: DrawPoint,
    distance: f64,
) -> Vec<ElementState> {
    if distance <= 0.0 || !document.has_arrow_bindable_elements {
        return Vec::new();
    }

    document
        .query_arrow_bindable_elements_at_point_top_down(position, distance, None, true)
        .into_iter()
        .filter(|element| element.opacity > 0.0)
        .collect()
}

impl ArrowBindingPreviewElement for ElementState {
    fn opacity(&self) -> f64 {
        self.opacity
    }

    fn is_bindable_target(&self) -> bool {
        matches!(
            &self.data,
            ElementData::Rectangle | ElementData::Text | ElementData::SerialNumber(_)
        )
    }
}

impl ArrowBindingPreviewState for DocumentState {
    type Element = ElementState;

    fn visit_elements_at_point_top_down<F>(
        &self,
        position: DrawPoint,
        distance: f64,
        mut visitor: F,
    ) where
        F: FnMut(&Self::Element) -> bool,
    {
        DocumentState::visit_elements_at_point_top_down(self, position, distance, |element| {
            visitor(element)
        });
    }
}

#[cfg(test)]
mod tests {
    use super::{
        resolve_arrow_binding_targets, resolve_arrow_binding_targets_in_document,
        should_preview_arrow_binding,
    };
    use crate::draw::config::draw_config::SnapConfig;
    use crate::draw::models::document_state::{
        DocumentState, ElementData, ElementState, HighlightData, SerialNumberData,
    };
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    fn element(id: &str, z_index: i64, opacity: f64, data: ElementData) -> ElementState {
        ElementState::new(
            id.to_owned(),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            opacity,
            z_index,
            data,
        )
    }

    #[test]
    fn should_preview_arrow_binding_matches_snapper_rules() {
        let mut snap = SnapConfig::default();
        snap.enable_arrow_binding = true;
        assert!(should_preview_arrow_binding(&snap, false));
        assert!(!should_preview_arrow_binding(&snap, true));

        snap.enable_arrow_binding = false;
        assert!(!should_preview_arrow_binding(&snap, false));
    }

    #[test]
    fn resolves_first_visible_bindable_target_in_top_down_order() {
        let state = DocumentState::new(
            vec![
                element("rect", 1, 1.0, ElementData::Rectangle),
                element(
                    "serial",
                    2,
                    1.0,
                    ElementData::SerialNumber(SerialNumberData::default()),
                ),
                element("highlight", 3, 1.0, ElementData::Highlight(HighlightData)),
                element("hidden", 4, 0.0, ElementData::Text),
            ],
            0,
            Default::default(),
        );

        let targets = resolve_arrow_binding_targets(&state, DrawPoint::new(5.0, 5.0), 8.0);
        let target_ids = targets
            .into_iter()
            .map(|element| element.id)
            .collect::<Vec<_>>();

        assert_eq!(target_ids, vec!["serial".to_owned()]);
    }

    #[test]
    fn document_preview_resolution_returns_empty_for_non_positive_distance() {
        let state = DocumentState::new(
            vec![element("rect", 1, 1.0, ElementData::Rectangle)],
            0,
            Default::default(),
        );

        assert!(
            resolve_arrow_binding_targets_in_document(&state, DrawPoint::new(5.0, 5.0), 0.0,)
                .is_empty()
        );
        assert!(resolve_arrow_binding_targets(&state, DrawPoint::new(5.0, 5.0), 0.0).is_empty());
    }

    #[test]
    fn document_preview_resolution_stops_at_first_opaque_bindable() {
        let state = DocumentState::new(
            vec![
                element("bottom", 1, 1.0, ElementData::Rectangle),
                element("top", 2, 1.0, ElementData::Rectangle),
            ],
            0,
            Default::default(),
        );

        let targets =
            resolve_arrow_binding_targets_in_document(&state, DrawPoint::new(5.0, 5.0), 8.0);
        let target_ids = targets
            .into_iter()
            .map(|element| element.id)
            .collect::<Vec<_>>();

        assert_eq!(target_ids, vec!["top".to_owned()]);
    }

    #[test]
    fn preview_state_trait_visits_document_top_down() {
        let state = DocumentState::new(
            vec![
                element("low", 1, 1.0, ElementData::Rectangle),
                element("high", 2, 1.0, ElementData::Rectangle),
            ],
            0,
            Default::default(),
        );

        let mut seen = Vec::<String>::new();
        state.visit_elements_at_point_top_down(DrawPoint::new(5.0, 5.0), 0.0, |element| {
            seen.push(element.id.clone());
            true
        });

        assert_eq!(seen, vec!["high".to_owned(), "low".to_owned()]);
    }
}
