#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use serde_json::{Map, Value};

use super::arrow_binding::ArrowBinding;

/// Encodes a core point payload.
pub fn encode_core_point(point: DrawPoint) -> Value {
    serde_json::json!({"x": point.x, "y": point.y, "pressure": point.pressure})
}

/// Decodes a core point payload.
pub fn decode_core_point(value: &Value) -> Option<DrawPoint> {
    let json = value.as_object()?;
    Some(DrawPoint::new(
        json.get("x")?.as_f64()?,
        json.get("y")?.as_f64()?,
    ))
}

/// Encodes a core binding payload.
pub fn encode_core_binding(binding: &ArrowBinding) -> Value {
    binding.to_json()
}

/// Decodes a core binding payload.
pub fn decode_core_binding(value: &Value) -> Option<ArrowBinding> {
    ArrowBinding::from_json(value).ok()
}

/// Copies an object map while preserving insertion-order semantics from serde.
pub fn clone_object_map(map: &Map<String, Value>) -> Map<String, Value> {
    map.clone()
}
