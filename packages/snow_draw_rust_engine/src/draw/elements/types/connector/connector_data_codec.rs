#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField;
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
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
