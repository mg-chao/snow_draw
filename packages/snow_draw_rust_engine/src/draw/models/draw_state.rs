#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::arrow_core_bridge::to_core_bindable_state;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::arrow::core::arrow_hit_test::is_point_near_bindable_for_binding_hit;
use crate::draw::elements::types::arrow::core::arrow_types::BindableState as CoreBindableState;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::models::application_state::{
    ApplicationState, IdleState, InteractionState, SelectionOverlayState, ViewState,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::selection_state::SelectionState;
use crate::draw::types::draw_point::DrawPoint;

pub type DomainElementState = ElementState;
pub type DomainSelectionState = SelectionState;

/// Persisted document data used by draw-domain state.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainDocumentState {
    pub elements: Vec<DomainElementState>,
    pub elements_version: i64,
    pub global_elements: GlobalElementsState,
}

impl DomainDocumentState {
    pub fn new(
        elements: Vec<DomainElementState>,
        elements_version: i64,
        global_elements: GlobalElementsState,
    ) -> Self {
        Self {
            elements,
            elements_version,
            global_elements,
        }
    }

    pub fn get_element_by_id(&self, id: &str) -> Option<&DomainElementState> {
        self.elements.iter().find(|element| element.id == id)
    }

    pub fn element_map(&self) -> HashMap<String, DomainElementState> {
        self.elements
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect()
    }

    pub fn order(&self) -> Vec<String> {
        self.elements
            .iter()
            .map(|element| element.id.clone())
            .collect()
    }

    pub fn ordered_element_ids(&self) -> Vec<String> {
        self.order()
    }

    pub fn copy_with(
        &self,
        elements: Option<Vec<DomainElementState>>,
        global_elements: Option<GlobalElementsState>,
        elements_version: Option<i64>,
    ) -> Self {
        let next_elements = elements.unwrap_or_else(|| self.elements.clone());
        let next_global_elements = global_elements.unwrap_or_else(|| self.global_elements.clone());
        let changed =
            next_elements != self.elements || next_global_elements != self.global_elements;
        let next_elements_version = elements_version.unwrap_or_else(|| {
            if changed {
                self.elements_version.saturating_add(1)
            } else {
                self.elements_version
            }
        });

        Self {
            elements: next_elements,
            elements_version: next_elements_version,
            global_elements: next_global_elements,
        }
    }

    pub fn highlight_elements(&self) -> Vec<DomainElementState> {
        self.elements
            .iter()
            .filter(|element| element.data.type_id().as_str() == HighlightData::TYPE_ID_TOKEN)
            .cloned()
            .collect()
    }

    pub fn bound_text_ids(&self) -> HashSet<String> {
        let mut bound_text_ids = HashSet::new();
        for element in &self.elements {
            if element.data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
                continue;
            }

            let Ok(data) = SerialNumberData::from_json_value(&element.data.to_json_value()) else {
                continue;
            };

            if let Some(text_element_id) = data.text_element_id {
                bound_text_ids.insert(text_element_id);
            }
        }
        bound_text_ids
    }

    pub fn bound_arrow_target_ids(&self) -> HashSet<String> {
        let mut target_ids = HashSet::new();
        for element in &self.elements {
            match element.data.type_id().as_str() {
                ArrowData::TYPE_ID_TOKEN => {
                    let Ok(data) = ArrowData::from_json_value(&element.data.to_json_value()) else {
                        continue;
                    };
                    if let Some(binding) = data.start_binding {
                        target_ids.insert(binding.element_id);
                    }
                    if let Some(binding) = data.end_binding {
                        target_ids.insert(binding.element_id);
                    }
                }
                LineData::TYPE_ID_TOKEN => {
                    let Ok(data) = LineData::from_json_value(&element.data.to_json_value()) else {
                        continue;
                    };
                    if let Some(binding) = data.start_binding {
                        target_ids.insert(binding.element_id);
                    }
                    if let Some(binding) = data.end_binding {
                        target_ids.insert(binding.element_id);
                    }
                }
                _ => {}
            }
        }
        target_ids
    }

    pub fn has_arrow_bindable_elements(&self) -> bool {
        self.elements
            .iter()
            .any(ArrowBindingUtils::is_bindable_target)
    }

    pub fn has_arrow_bindable_elements_except(&self, excluded_element_id: Option<&str>) -> bool {
        self.elements.iter().any(|element| {
            element.opacity > 0.0
                && excluded_element_id.is_none_or(|excluded| excluded != element.id.as_str())
                && ArrowBindingUtils::is_bindable_target(element)
        })
    }

    pub fn query_arrow_bindable_elements_at_point_top_down(
        &self,
        point: DrawPoint,
        tolerance: f64,
        excluded_element_id: Option<&str>,
        stop_at_opaque: bool,
    ) -> Vec<DomainElementState> {
        if !self.has_arrow_bindable_elements() {
            return Vec::new();
        }

        let mut result = Vec::new();
        for element in self.elements.iter().rev() {
            if element.opacity <= 0.0 {
                continue;
            }
            if excluded_element_id.is_some_and(|excluded| excluded == element.id.as_str()) {
                continue;
            }

            let Some(bindable) = to_core_bindable_state(
                element,
                Some(element.z_index as usize),
                true,
                true,
                Some(element.rect),
            ) else {
                continue;
            };

            if !is_point_near_bindable_for_binding_hit(
                point,
                &to_order_core_bindable_state(&bindable),
                tolerance,
            ) {
                continue;
            }

            let stop_here = stop_at_opaque && bindable.background_opaque.unwrap_or(true);
            result.push(element.clone());
            if stop_here {
                break;
            }
        }

        result
    }
}

fn to_order_core_bindable_state(
    bindable: &crate::draw::elements::types::arrow::arrow_core::BindableState,
) -> CoreBindableState {
    CoreBindableState {
        id: bindable.id.clone(),
        shape: bindable.shape.as_str().to_string(),
        x: bindable.x,
        y: bindable.y,
        width: bindable.width,
        height: bindable.height,
        angle: bindable.angle,
        stroke_width: bindable.stroke_width,
        roundness: None,
        z_index: bindable.z_index,
        background_opaque: bindable.background_opaque,
        binding_enabled: bindable.binding_enabled,
        interior_hit_enabled: bindable.interior_hit_enabled,
        visibility_bounds: bindable.visibility_bounds,
    }
}

impl Default for DomainDocumentState {
    fn default() -> Self {
        Self::new(Vec::new(), 0, GlobalElementsState::default())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::DomainDocumentState;
    use crate::draw::elements::types::arrow::arrow_data::{
        ArrowBinding, ArrowBindingMode, ArrowData,
    };
    use crate::draw::elements::types::rectangle::rectangle_data::{
        RectangleData, RectangleDataPatch,
    };
    use crate::draw::elements::types::serial_number::serial_number_data::{
        SerialNumberData, SerialNumberDataPatch,
    };
    use crate::draw::elements::types::text::text_data::{TextData, TextDataPatch};
    use crate::draw::models::element_state::ElementState;
    use crate::draw::models::global_elements_state::GlobalElementsState;
    use crate::draw::types::draw_color::DrawColor;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    fn rect_element(id: &str, z_index: i64, fill_color: DrawColor) -> ElementState {
        let data = RectangleData::default().copy_with(RectangleDataPatch {
            fill_color: Some(fill_color),
            ..RectangleDataPatch::default()
        });
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            z_index,
            Arc::new(data),
        )
    }

    fn text_element(id: &str, z_index: i64, fill_color: DrawColor) -> ElementState {
        let data = TextData::default().copy_with(TextDataPatch {
            fill_color: Some(fill_color),
            ..TextDataPatch::default()
        });
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            z_index,
            Arc::new(data),
        )
    }

    #[test]
    fn bound_text_and_arrow_target_caches_follow_document_elements() {
        let mut arrow = ArrowData::default();
        arrow.start_binding = Some(ArrowBinding::new(
            "target-a",
            DrawPoint::new(0.5, 0.5),
            ArrowBindingMode::Orbit,
        ));
        arrow.end_binding = Some(ArrowBinding::new(
            "target-b",
            DrawPoint::new(0.5, 0.5),
            ArrowBindingMode::Orbit,
        ));

        let state = DomainDocumentState::new(
            vec![
                ElementState::new(
                    "serial",
                    DrawRect::new(0.0, 0.0, 20.0, 20.0),
                    0.0,
                    1.0,
                    0,
                    Arc::new(
                        SerialNumberData::default().copy_with(SerialNumberDataPatch {
                            text_element_id: Some(Some("text-1".to_string())),
                            ..SerialNumberDataPatch::default()
                        }),
                    ),
                ),
                ElementState::new(
                    "arrow",
                    DrawRect::new(0.0, 0.0, 20.0, 20.0),
                    0.0,
                    1.0,
                    1,
                    Arc::new(arrow),
                ),
            ],
            0,
            GlobalElementsState::default(),
        );

        let bound_text_ids = state.bound_text_ids();
        let bound_arrow_target_ids = state.bound_arrow_target_ids();
        assert!(bound_text_ids.contains("text-1"));
        assert!(bound_arrow_target_ids.contains("target-a"));
        assert!(bound_arrow_target_ids.contains("target-b"));
    }

    #[test]
    fn query_arrow_bindables_returns_top_down_and_stops_on_opaque_targets() {
        let state = DomainDocumentState::new(
            vec![
                rect_element("bottom", 0, DrawColor::new(0xFF11_2233)),
                rect_element("top", 1, DrawColor::new(0xFF44_5566)),
            ],
            0,
            GlobalElementsState::default(),
        );

        let hits = state.query_arrow_bindable_elements_at_point_top_down(
            DrawPoint::new(1.0, 10.0),
            2.0,
            None,
            true,
        );

        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, "top");
    }

    #[test]
    fn query_arrow_bindables_keeps_searching_past_transparent_targets() {
        let state = DomainDocumentState::new(
            vec![
                rect_element("bottom", 0, DrawColor::new(0xFF11_2233)),
                text_element("top", 1, DrawColor::new(0x0011_2233)),
            ],
            0,
            GlobalElementsState::default(),
        );

        let hits = state.query_arrow_bindable_elements_at_point_top_down(
            DrawPoint::new(1.0, 10.0),
            2.0,
            None,
            true,
        );

        let ids = hits
            .into_iter()
            .map(|element| element.id)
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["top".to_string(), "bottom".to_string()]);
    }
}

/// Domain-layer state.
///
/// Includes all state that must be persisted and participates in undo/redo.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainState {
    pub document: DomainDocumentState,
    pub selection: DomainSelectionState,
}

impl DomainState {
    pub fn new(document: DomainDocumentState, selection: DomainSelectionState) -> Self {
        Self {
            document,
            selection,
        }
    }

    pub fn empty() -> Self {
        Self::default()
    }

    pub fn copy_with(
        &self,
        document: Option<DomainDocumentState>,
        selection: Option<DomainSelectionState>,
    ) -> Self {
        Self {
            document: document.unwrap_or_else(|| self.document.clone()),
            selection: selection.unwrap_or_else(|| self.selection.clone()),
        }
    }
}

impl Default for DomainState {
    fn default() -> Self {
        Self {
            document: DomainDocumentState::default(),
            selection: DomainSelectionState::default(),
        }
    }
}

/// Aggregate root for draw state.
///
/// Coordinates domain and application state with a unified access interface.
#[derive(Clone, Debug, PartialEq)]
pub struct DrawState {
    /// Domain state (participates in undo/redo and is persisted).
    pub domain: DomainState,
    /// Application state (temporary, not part of undo/redo).
    pub application: ApplicationState,
}

impl DrawState {
    /// Creates a draw state, defaulting missing sections to their initial values.
    pub fn new(domain: Option<DomainState>, application: Option<ApplicationState>) -> Self {
        Self {
            domain: domain.unwrap_or_else(DomainState::empty),
            application: application.unwrap_or_else(|| ApplicationState::initial(None)),
        }
    }

    /// Factory method: create initial state.
    pub fn initial(view: Option<ViewState>) -> Self {
        Self {
            domain: DomainState::empty(),
            application: ApplicationState::initial(view),
        }
    }

    /// Returns a copy with selectively replaced fields.
    pub fn copy_with(
        &self,
        domain: Option<DomainState>,
        application: Option<ApplicationState>,
    ) -> Self {
        Self {
            domain: domain.unwrap_or_else(|| self.domain.clone()),
            application: application.unwrap_or_else(|| self.application.clone()),
        }
    }

    /// Get the domain snapshot used for history.
    pub fn domain_snapshot(&self) -> DomainState {
        self.domain.clone()
    }

    /// Restore domain state from history.
    pub fn restore_from_snapshot(&self, snapshot: DomainState) -> Self {
        Self {
            domain: snapshot,
            application: self.application.copy_with(
                None,
                Some(InteractionState::Idle(IdleState)),
                Some(SelectionOverlayState::EMPTY),
            ),
        }
    }
}

impl Default for DrawState {
    fn default() -> Self {
        Self::new(None, None)
    }
}

impl fmt::Display for DrawState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DrawState(elements: {}, selection: {:?}, interaction: {:?})",
            self.domain.document.elements.len(),
            self.domain.selection.selected_ids,
            self.application.interaction
        )
    }
}
