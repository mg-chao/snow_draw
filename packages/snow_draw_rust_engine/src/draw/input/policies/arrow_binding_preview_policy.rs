#![allow(dead_code)]

use crate::draw::config::draw_config::SnapConfig;
use crate::draw::elements::types::arrow::arrow_binding_snapper::ArrowBindingSnapper;
use crate::draw::models::document_state::{DocumentState, ElementData, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::utils::snapping_mode::SnappingMode;

/// Returns whether arrow binding preview should be evaluated.
pub fn should_preview_arrow_binding(snap_config: &SnapConfig, snapping_mode: SnappingMode) -> bool {
    ArrowBindingSnapper::should_attempt_binding(snap_config, snapping_mode)
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
    let mut targets = Vec::<S::Element>::new();
    state.visit_elements_at_point_top_down(position, distance, |element| {
        if element.opacity() <= 0.0 || !element.is_bindable_target() {
            return true;
        }

        targets.push(element.clone());
        true
    });
    targets
}

/// Convenience wrapper for the translated `DocumentState`.
pub fn resolve_arrow_binding_targets_in_document(
    document: &DocumentState,
    position: DrawPoint,
    distance: f64,
) -> Vec<ElementState> {
    resolve_arrow_binding_targets(document, position, distance)
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
    use super::{resolve_arrow_binding_targets, should_preview_arrow_binding};
    use crate::draw::config::draw_config::SnapConfig;
    use crate::draw::models::document_state::{
        DocumentState, ElementData, ElementState, HighlightData, SerialNumberData,
    };
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;
    use crate::draw::utils::snapping_mode::SnappingMode;

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
        snap.enabled = false;
        assert!(should_preview_arrow_binding(&snap, SnappingMode::Object));

        assert!(!should_preview_arrow_binding(&snap, SnappingMode::Grid));

        snap.enabled = true;
        assert!(!should_preview_arrow_binding(&snap, SnappingMode::None));
    }

    #[test]
    fn resolves_only_visible_bindable_targets_in_top_down_order() {
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

        let targets = resolve_arrow_binding_targets(&state, DrawPoint::new(5.0, 5.0), 0.0);
        let target_ids = targets
            .into_iter()
            .map(|element| element.id)
            .collect::<Vec<_>>();

        assert_eq!(target_ids, vec!["serial".to_owned(), "rect".to_owned()]);
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
