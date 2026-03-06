#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField;
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
use crate::draw::elements::types::arrow::elbow::elbow_routing_data::ElbowRoutingData;
use crate::draw::types::draw_point::DrawPoint;
use serde_json::Value;

/// Encodes connector points using the shared JSON point shape.
pub fn encode_points(points: &[DrawPoint]) -> Value {
    Value::Array(
        points
            .iter()
            .map(|point| {
                serde_json::json!({
                    "x": point.x,
                    "y": point.y,
                    "pressure": point.pressure,
                })
            })
            .collect(),
    )
}

/// Resolves a nullable binding update using connector semantics.
pub fn resolve_binding_update(
    raw_binding: NullableField<ArrowBinding>,
    current_binding: Option<ArrowBinding>,
) -> Option<ArrowBinding> {
    match raw_binding {
        NullableField::Unset => current_binding,
        NullableField::Null => None,
        NullableField::Value(binding) => Some(binding),
    }
}

/// Resolves a nullable fixed-segment update using connector semantics.
pub fn resolve_fixed_segments_update(
    raw_fixed_segments: NullableField<Vec<ElbowFixedSegment>>,
    current_fixed_segments: Option<Vec<ElbowFixedSegment>>,
) -> Option<Vec<ElbowFixedSegment>> {
    match raw_fixed_segments {
        NullableField::Unset => current_fixed_segments,
        NullableField::Null => None,
        NullableField::Value(segments) => {
            if segments.is_empty() {
                None
            } else {
                Some(segments)
            }
        }
    }
}

/// Resolves a nullable bool update using connector semantics.
pub fn resolve_bool_update(
    raw_value: NullableField<bool>,
    current_value: Option<bool>,
) -> Option<bool> {
    match raw_value {
        NullableField::Unset => current_value,
        NullableField::Null => None,
        NullableField::Value(value) => Some(value),
    }
}

/// Builds elbow-only routing metadata from decoded connector fields.
pub fn decode_elbow_routing_data(
    fixed_segments: Option<Vec<ElbowFixedSegment>>,
    start_is_special: Option<bool>,
    end_is_special: Option<bool>,
) -> Option<ElbowRoutingData> {
    let routing = ElbowRoutingData::new(fixed_segments, start_is_special, end_is_special);
    if routing.is_empty() {
        None
    } else {
        Some(routing)
    }
}

/// Resolves an elbow-routing update using connector semantics.
pub fn resolve_elbow_routing_update(
    raw_fixed_segments: NullableField<Vec<ElbowFixedSegment>>,
    raw_start_is_special: NullableField<bool>,
    raw_end_is_special: NullableField<bool>,
    current_routing_data: Option<ElbowRoutingData>,
) -> Option<ElbowRoutingData> {
    if matches!(raw_fixed_segments, NullableField::Unset)
        && matches!(raw_start_is_special, NullableField::Unset)
        && matches!(raw_end_is_special, NullableField::Unset)
    {
        return current_routing_data;
    }

    let current_fixed_segments = current_routing_data
        .as_ref()
        .and_then(|routing| routing.fixed_segments.clone());
    let current_start_is_special = current_routing_data
        .as_ref()
        .and_then(|routing| routing.start_is_special);
    let current_end_is_special = current_routing_data
        .as_ref()
        .and_then(|routing| routing.end_is_special);

    decode_elbow_routing_data(
        resolve_fixed_segments_update(raw_fixed_segments, current_fixed_segments),
        resolve_bool_update(raw_start_is_special, current_start_is_special),
        resolve_bool_update(raw_end_is_special, current_end_is_special),
    )
}
