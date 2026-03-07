#![allow(dead_code)]

use std::collections::BTreeSet;

use serde_json::Value;

use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::element_style::ArrowType;

/// Read-only arrow profile extracted from an element payload.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct BasicArrowLikeData {
    pub points_len: usize,
    pub arrow_type: ArrowType,
}

/// Effective single-selection classification used by render/hit-test layers.
#[derive(Clone, Debug, PartialEq)]
pub struct SingleSelectionProfile {
    pub element: Option<ElementState>,
    pub arrow_data: Option<BasicArrowLikeData>,
    pub is_text: bool,
}

impl SingleSelectionProfile {
    pub fn none() -> Self {
        Self {
            element: None,
            arrow_data: None,
            is_text: false,
        }
    }

    pub fn is_arrow(&self) -> bool {
        self.arrow_data.is_some()
    }

    pub fn is_two_point_arrow(&self) -> bool {
        self.arrow_data
            .as_ref()
            .is_some_and(|arrow| arrow.points_len == 2)
    }

    pub fn is_elbow_arrow(&self) -> bool {
        self.arrow_data
            .as_ref()
            .is_some_and(|arrow| arrow.arrow_type == ArrowType::Elbow)
    }

    pub fn corner_handle_offset(&self) -> f64 {
        if self.is_arrow() {
            8.0
        } else {
            0.0
        }
    }

    pub fn from_element(element: Option<ElementState>) -> Self {
        let Some(element) = element else {
            return Self::none();
        };

        let arrow_data = resolve_arrow_like_data(&element);
        let is_text = arrow_data.is_none() && is_text_element(&element);

        Self {
            element: Some(element),
            arrow_data,
            is_text,
        }
    }
}

/// Resolves normalized single-selection profile for the currently selected ids.
pub fn resolve_single_selection_profile<F>(
    selected_ids: &BTreeSet<String>,
    mut resolve_element_by_id: F,
) -> SingleSelectionProfile
where
    F: FnMut(&str) -> Option<ElementState>,
{
    if selected_ids.len() != 1 {
        return SingleSelectionProfile::none();
    }

    let Some(selected_id) = selected_ids.iter().next() else {
        return SingleSelectionProfile::none();
    };

    SingleSelectionProfile::from_element(resolve_element_by_id(selected_id))
}

fn resolve_arrow_like_data(element: &ElementState) -> Option<BasicArrowLikeData> {
    let type_id = element.data.type_id();
    let type_id = type_id.as_str();
    if type_id != ArrowData::TYPE_ID_TOKEN && type_id != LineData::TYPE_ID_TOKEN {
        return None;
    }

    let payload = element.data.to_json_value();
    let json = payload.as_object()?;
    let points_len = json.get("points").and_then(Value::as_array)?.len();

    let arrow_type = if type_id == LineData::TYPE_ID_TOKEN {
        ArrowType::Curved
    } else {
        json.get("arrowType")
            .and_then(Value::as_str)
            .and_then(parse_arrow_type)
            .unwrap_or(ArrowType::Straight)
    };

    Some(BasicArrowLikeData {
        points_len,
        arrow_type,
    })
}

fn is_text_element(element: &ElementState) -> bool {
    element.data.type_id().as_str() == TextData::TYPE_ID_TOKEN
}

fn parse_arrow_type(raw: &str) -> Option<ArrowType> {
    match raw {
        "straight" => Some(ArrowType::Straight),
        "curved" => Some(ArrowType::Curved),
        "elbow" => Some(ArrowType::Elbow),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::collections::BTreeSet;
    use std::sync::Arc;

    use crate::draw::elements::types::arrow::arrow_data::{ArrowData, ArrowDataPatch};
    use crate::draw::models::element_state::ElementState;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    #[test]
    fn degenerate_connector_selection_still_counts_as_arrow_selection() {
        let element = ElementState::new(
            "arrow-1",
            DrawRect::new(0.0, 0.0, 100.0, 100.0),
            0.0,
            1.0,
            0,
            Arc::new(ArrowData::default().copy_with(ArrowDataPatch {
                points: Some(vec![DrawPoint::new(0.5, 0.5)]),
                ..ArrowDataPatch::default()
            })),
        );

        let profile =
            resolve_single_selection_profile(&BTreeSet::from([String::from("arrow-1")]), |id| {
                (id == "arrow-1").then(|| element.clone())
            });

        assert!(profile.is_arrow());
        assert!(!profile.is_two_point_arrow());
        assert_eq!(profile.corner_handle_offset(), 8.0);
    }
}
