#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowData, ArrowDataPatch, NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::elbow::elbow_editing::{
    compute_elbow_edit, transform_fixed_segments, BindingOverride,
};
use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::element_style::ArrowType;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

/// Clears bindings for transformed arrow-like elements.
///
/// Use this after applying geometry transforms (move/resize/rotate) so arrows
/// no longer stay attached to old targets.
pub fn unbind_arrow_like_elements(
    transformed_elements: &HashMap<String, ElementState>,
    base_elements: &HashMap<String, ElementState>,
) -> HashMap<String, ElementState> {
    let lookup = CombinedElementLookup::new(base_elements, transformed_elements);
    let mut updates = HashMap::new();

    for element in transformed_elements.values() {
        let Some(data) = decode_arrow_like_payload(element) else {
            continue;
        };
        if !data.has_binding_state() {
            continue;
        }

        let updated = unbind_arrow_element(element, data, &lookup);
        updates.insert(updated.id.clone(), updated);
    }

    updates
}

enum ArrowLikePayload {
    Arrow(ArrowData),
    Line(LineData),
}

impl ArrowLikePayload {
    fn has_binding_state(&self) -> bool {
        match self {
            Self::Arrow(data) => {
                data.start_binding.is_some()
                    || data.end_binding.is_some()
                    || data.start_is_special.is_some()
                    || data.end_is_special.is_some()
            }
            Self::Line(data) => {
                data.start_binding.is_some()
                    || data.end_binding.is_some()
                    || data.start_is_special.is_some()
                    || data.end_is_special.is_some()
            }
        }
    }
}

fn decode_arrow_like_payload(element: &ElementState) -> Option<ArrowLikePayload> {
    let json = element.data.to_json();
    match element.type_id().as_str() {
        ArrowData::TYPE_ID_TOKEN => ArrowData::from_json(&json)
            .ok()
            .map(ArrowLikePayload::Arrow),
        LineData::TYPE_ID_TOKEN => LineData::from_json(&json).ok().map(ArrowLikePayload::Line),
        _ => None,
    }
}

fn unbind_arrow_element(
    element: &ElementState,
    data: ArrowLikePayload,
    lookup: &CombinedElementLookup<'_, ElementState>,
) -> ElementState {
    match data {
        ArrowLikePayload::Arrow(data) => unbind_arrow_data_element(element, &data, lookup),
        ArrowLikePayload::Line(data) => {
            let updated_data = clear_line_bindings(&data);
            element.copy_with(
                None,
                None,
                None,
                None,
                None,
                Some(arc_element_data(updated_data)),
            )
        }
    }
}

fn unbind_arrow_data_element(
    element: &ElementState,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, ElementState>,
) -> ElementState {
    if data.arrow_type == ArrowType::Elbow {
        let unbound_elbow = compute_elbow_edit(
            element,
            data,
            lookup,
            None,
            None,
            BindingOverride::Clear,
            BindingOverride::Clear,
            true,
        );

        let geometry = resolve_arrow_geometry_update(
            &unbound_elbow.local_points,
            element.rect,
            element.rotation,
            data.arrow_type,
        );

        let transformed_fixed_segments = transform_fixed_segments(
            unbound_elbow.fixed_segments.as_deref(),
            element.rect,
            geometry.rect,
            element.rotation,
        );

        let updated_data = data.copy_with(ArrowDataPatch {
            points: Some(geometry.normalized_points),
            start_binding: ArrowNullableField::Null,
            end_binding: ArrowNullableField::Null,
            fixed_segments: transformed_fixed_segments
                .map(ArrowNullableField::Value)
                .unwrap_or(ArrowNullableField::Null),
            start_is_special: ArrowNullableField::Null,
            end_is_special: ArrowNullableField::Null,
            ..ArrowDataPatch::default()
        });

        return element.copy_with(
            None,
            Some(geometry.rect),
            None,
            None,
            None,
            Some(arc_element_data(updated_data)),
        );
    }

    let updated_data = clear_arrow_bindings(data);
    element.copy_with(
        None,
        None,
        None,
        None,
        None,
        Some(arc_element_data(updated_data)),
    )
}

fn clear_arrow_bindings(data: &ArrowData) -> ArrowData {
    data.copy_with(ArrowDataPatch {
        start_binding: ArrowNullableField::Null,
        end_binding: ArrowNullableField::Null,
        fixed_segments: ArrowNullableField::Null,
        start_is_special: ArrowNullableField::Null,
        end_is_special: ArrowNullableField::Null,
        ..ArrowDataPatch::default()
    })
}

fn clear_line_bindings(data: &LineData) -> LineData {
    data.copy_with(LineDataPatch {
        start_binding: ArrowLikeNullableField::Null,
        end_binding: ArrowLikeNullableField::Null,
        fixed_segments: ArrowLikeNullableField::Null,
        start_is_special: ArrowLikeNullableField::Null,
        end_is_special: ArrowLikeNullableField::Null,
        ..LineDataPatch::default()
    })
}

fn arc_element_data<T>(data: T) -> Arc<dyn ElementData>
where
    T: ElementData + 'static,
{
    Arc::new(data)
}
