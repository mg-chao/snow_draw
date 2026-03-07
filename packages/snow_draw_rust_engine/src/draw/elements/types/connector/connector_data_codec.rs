#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField;
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
use crate::draw::elements::types::arrow::elbow::elbow_routing_data::ElbowRoutingData;
use crate::draw::elements::types::shared::element_data_codec::{
    ElementDataCodec, ElementDataCodecError,
};
use crate::draw::types::draw_point::DrawPoint;
use serde_json::{Map, Value};

pub type ConnectorDataCodecError = ElementDataCodecError;

/// Decodes connector points from JSON.
pub fn decode_points(raw_points: &Value) -> Result<Vec<DrawPoint>, ConnectorDataCodecError> {
    let entries = raw_points
        .as_array()
        .ok_or_else(|| ElementDataCodecError::new("Connector points must be a JSON array"))?;

    let mut points = Vec::with_capacity(entries.len());
    for entry in entries {
        points.push(ElementDataCodec::decode_point(
            entry,
            "points entry",
            true,
            Some("pressure"),
        )?);
    }

    if points.len() < 2 {
        return Err(ElementDataCodecError::new(
            "Connector payload must include at least two points",
        ));
    }

    Ok(points)
}

/// Decodes an optional connector binding from JSON.
pub fn decode_binding(
    raw: Option<&Value>,
) -> Result<Option<ArrowBinding>, ConnectorDataCodecError> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    if raw.is_null() {
        return Ok(None);
    }

    ArrowBinding::from_json(raw)
        .map(Some)
        .map_err(ElementDataCodecError::new)
}

/// Decodes optional elbow fixed segments from JSON.
pub fn decode_fixed_segments(
    raw: Option<&Value>,
) -> Result<Option<Vec<ElbowFixedSegment>>, ConnectorDataCodecError> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    if raw.is_null() {
        return Ok(None);
    }

    let entries = raw
        .as_array()
        .ok_or_else(|| ElementDataCodecError::new("fixedSegments must be a JSON array"))?;

    let mut segments = Vec::with_capacity(entries.len());
    for entry in entries {
        let map = ElementDataCodec::as_json_map(entry, Some("fixedSegments entry"))?;
        segments.push(
            ElbowFixedSegment::from_json(map)
                .map_err(|error| ElementDataCodecError::new(error.to_string()))?,
        );
    }

    Ok(normalize_fixed_segments(Some(segments)))
}

/// Normalizes optional fixed segments by clearing empty collections.
pub fn normalize_fixed_segments(
    segments: Option<Vec<ElbowFixedSegment>>,
) -> Option<Vec<ElbowFixedSegment>> {
    match segments {
        Some(segments) if !segments.is_empty() => Some(segments),
        _ => None,
    }
}

/// Encodes connector points using the shared JSON point shape.
pub fn encode_points(points: &[DrawPoint]) -> Value {
    Value::Array(
        points
            .iter()
            .map(|point| {
                serde_json::json!({
                    "x": point.x,
                    "y": point.y,
                })
            })
            .collect(),
    )
}

/// Encodes optional fixed segments using the shared connector JSON shape.
pub fn encode_fixed_segments(
    segments: Option<&[ElbowFixedSegment]>,
) -> Option<Vec<Map<String, Value>>> {
    let segments = segments.filter(|value| !value.is_empty())?;
    Some(
        segments
            .iter()
            .cloned()
            .map(ElbowFixedSegment::to_json)
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn decode_points_requires_two_entries() {
        let error = decode_points(&json!([{ "x": 0.0, "y": 0.0 }]))
            .expect_err("single-point connector should fail");

        assert!(error.to_string().contains("at least two points"));
    }

    #[test]
    fn decode_and_encode_fixed_segments_round_trip() {
        let raw = json!([
            {
                "index": 2,
                "start": { "x": 10.0, "y": 20.0 },
                "end": { "x": 30.0, "y": 20.0 }
            }
        ]);

        let decoded = decode_fixed_segments(Some(&raw))
            .expect("fixed segments should decode")
            .expect("segments should exist");
        let encoded = encode_fixed_segments(Some(&decoded)).expect("segments should encode");

        assert_eq!(encoded.len(), 1);
        assert_eq!(encoded[0].get("index").and_then(Value::as_u64), Some(2));
    }

    #[test]
    fn encode_points_omits_pressure_field() {
        let encoded = encode_points(&[
            DrawPoint::with_pressure_and_timestamp(1.0, 2.0, 0.8, 42),
            DrawPoint::new(3.0, 4.0),
        ]);

        let points = encoded.as_array().expect("points array");
        assert_eq!(points.len(), 2);
        assert_eq!(points[0].get("x").and_then(Value::as_f64), Some(1.0));
        assert_eq!(points[0].get("y").and_then(Value::as_f64), Some(2.0));
        assert!(points[0].get("pressure").is_none());
        assert!(points[1].get("pressure").is_none());
    }
}
