#![allow(dead_code)]

use serde_json::Value;

use super::arrow_types::{ArrowPatch, ArrowState, FixedPointBinding, FixedSegment};
use crate::draw::types::draw_point::DrawPoint;

/// Applies an untyped arrow patch to a projected arrow state.
pub fn apply_arrow_patch(arrow: &ArrowState, patch: &ArrowPatch) -> ArrowState {
    let mut next = arrow.clone();

    if let Some(value) = patch.get("x").and_then(Value::as_f64) {
        next.x = value;
    }
    if let Some(value) = patch.get("y").and_then(Value::as_f64) {
        next.y = value;
    }
    if let Some(value) = patch.get("width").and_then(Value::as_f64) {
        next.width = value;
    }
    if let Some(value) = patch.get("height").and_then(Value::as_f64) {
        next.height = value;
    }
    if let Some(points) = patch.get("points").and_then(read_points) {
        next.points = points;
    }
    if patch.contains_key("startBinding") {
        next.start_binding = patch.get("startBinding").and_then(read_binding);
    }
    if patch.contains_key("endBinding") {
        next.end_binding = patch.get("endBinding").and_then(read_binding);
    }
    if patch.contains_key("fixedSegments") {
        next.fixed_segments = patch.get("fixedSegments").and_then(read_fixed_segments);
    }
    if patch.contains_key("startIsSpecial") {
        next.start_is_special = patch.get("startIsSpecial").and_then(Value::as_bool);
    }
    if patch.contains_key("endIsSpecial") {
        next.end_is_special = patch.get("endIsSpecial").and_then(Value::as_bool);
    }

    next
}

fn read_points(value: &Value) -> Option<Vec<DrawPoint>> {
    let points = value.as_array()?;
    Some(
        points
            .iter()
            .map(|point| {
                let Some(point) = point.as_array() else {
                    return DrawPoint::ZERO;
                };
                let x = point.first().and_then(Value::as_f64).unwrap_or(0.0);
                let y = point.get(1).and_then(Value::as_f64).unwrap_or(0.0);
                DrawPoint::new(x, y)
            })
            .collect(),
    )
}

fn read_binding(value: &Value) -> Option<FixedPointBinding> {
    let binding = value.as_object()?;
    let element_id = binding.get("elementId")?.as_str()?.to_string();
    let fixed_point = binding.get("fixedPoint")?.as_array()?;
    let x = fixed_point.first().and_then(Value::as_f64)?;
    let y = fixed_point.get(1).and_then(Value::as_f64)?;
    let mode = binding
        .get("mode")
        .and_then(Value::as_str)
        .unwrap_or("orbit")
        .to_string();
    Some(FixedPointBinding::new(
        element_id,
        DrawPoint::new(x, y),
        mode,
    ))
}

fn read_fixed_segments(value: &Value) -> Option<Vec<FixedSegment>> {
    let segments = value.as_array()?;
    Some(
        segments
            .iter()
            .filter_map(|segment| {
                let segment = segment.as_object()?;
                let start = segment.get("start")?.as_array()?;
                let end = segment.get("end")?.as_array()?;
                Some(FixedSegment {
                    index: segment.get("index")?.as_u64()? as usize,
                    start: DrawPoint::new(
                        start.first().and_then(Value::as_f64)?,
                        start.get(1).and_then(Value::as_f64)?,
                    ),
                    end: DrawPoint::new(
                        end.first().and_then(Value::as_f64)?,
                        end.get(1).and_then(Value::as_f64)?,
                    ),
                })
            })
            .collect(),
    )
}
