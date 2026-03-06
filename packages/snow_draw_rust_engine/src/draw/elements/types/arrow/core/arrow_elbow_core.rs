#![allow(dead_code)]

use serde_json::Value;

pub use crate::draw::elements::types::arrow::elbow::elbow_editing::*;
pub use crate::draw::elements::types::arrow::elbow::elbow_router::*;

use super::arrow_types::{ArrowPatch, ArrowState, FixedPointBinding, FixedSegment};
use crate::draw::types::draw_point::DrawPoint;

const DEDUP_THRESHOLD: f64 = 1.0;

pub fn validate_elbow_points(points: &[DrawPoint], tolerance: f64) -> bool {
    points.windows(2).all(|segment| {
        let previous = segment[0];
        let current = segment[1];
        (current.x - previous.x).abs() < tolerance || (current.y - previous.y).abs() < tolerance
    })
}

pub fn validate_elbow_invariant(arrow: &ArrowState) -> Vec<String> {
    let mut issues = Vec::new();
    if !arrow.elbowed {
        return issues;
    }
    if arrow.points.len() < 2 {
        issues.push("elbow arrow must contain at least two points".to_string());
    }
    if !validate_elbow_points(&arrow.points, DEDUP_THRESHOLD) {
        issues.push("elbow arrow path must be orthogonal".to_string());
    }
    if let Some(fixed_segments) = arrow.fixed_segments.as_ref() {
        for fixed in fixed_segments {
            if fixed.index == 0 || fixed.index >= arrow.points.len() {
                issues.push(format!(
                    "fixed segment index {} is outside points range",
                    fixed.index
                ));
            }
        }
    }
    issues
}

pub fn compute_elbow_resize_patch(
    start_binding: Option<&FixedPointBinding>,
    end_binding: Option<&FixedPointBinding>,
    fixed_segments: Option<&[FixedSegment]>,
    points: Option<&[DrawPoint]>,
    flip_x: bool,
    flip_y: bool,
) -> ArrowPatch {
    let mut patch = ArrowPatch::new();

    if let Some(binding) = start_binding {
        patch.insert(
            "startBinding".to_string(),
            binding_to_value(&FixedPointBinding::new(
                binding.element_id.clone(),
                mirror_fixed_point(binding.fixed_point, flip_x, flip_y),
                binding.mode.clone(),
            )),
        );
    }
    if let Some(binding) = end_binding {
        patch.insert(
            "endBinding".to_string(),
            binding_to_value(&FixedPointBinding::new(
                binding.element_id.clone(),
                mirror_fixed_point(binding.fixed_point, flip_x, flip_y),
                binding.mode.clone(),
            )),
        );
    }

    if let (Some(fixed_segments), Some(points)) = (fixed_segments, points) {
        let remapped = fixed_segments
            .iter()
            .map(|segment| {
                let start_index = segment.index.saturating_sub(1);
                let end_index = segment.index;
                let start = points.get(start_index).copied().unwrap_or(segment.start);
                let end = points.get(end_index).copied().unwrap_or(segment.end);
                fixed_segment_to_value(&FixedSegment {
                    index: segment.index,
                    start,
                    end,
                })
            })
            .collect::<Vec<_>>();
        patch.insert("fixedSegments".to_string(), Value::Array(remapped));
    }

    patch
}

pub fn update_elbow_arrow_points(patch: ArrowPatch) -> ArrowPatch {
    patch
}

fn mirror_fixed_point(fixed_point: DrawPoint, flip_x: bool, flip_y: bool) -> DrawPoint {
    DrawPoint::new(
        if flip_x {
            -fixed_point.x + 1.0
        } else {
            fixed_point.x
        },
        if flip_y {
            -fixed_point.y + 1.0
        } else {
            fixed_point.y
        },
    )
}

fn binding_to_value(binding: &FixedPointBinding) -> Value {
    let mut object = serde_json::Map::new();
    object.insert(
        "elementId".to_string(),
        Value::String(binding.element_id.clone()),
    );
    object.insert(
        "fixedPoint".to_string(),
        Value::Array(vec![
            Value::from(binding.fixed_point.x),
            Value::from(binding.fixed_point.y),
        ]),
    );
    object.insert("mode".to_string(), Value::String(binding.mode.clone()));
    Value::Object(object)
}

fn fixed_segment_to_value(segment: &FixedSegment) -> Value {
    let mut object = serde_json::Map::new();
    object.insert("index".to_string(), Value::from(segment.index as u64));
    object.insert(
        "start".to_string(),
        Value::Array(vec![
            Value::from(segment.start.x),
            Value::from(segment.start.y),
        ]),
    );
    object.insert(
        "end".to_string(),
        Value::Array(vec![Value::from(segment.end.x), Value::from(segment.end.y)]),
    );
    Value::Object(object)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_elbow_points_requires_orthogonal_segments() {
        assert!(validate_elbow_points(
            &[
                DrawPoint::new(0.0, 0.0),
                DrawPoint::new(10.0, 0.0),
                DrawPoint::new(10.0, 20.0),
            ],
            DEDUP_THRESHOLD,
        ));
        assert!(!validate_elbow_points(
            &[DrawPoint::new(0.0, 0.0), DrawPoint::new(10.0, 5.0)],
            DEDUP_THRESHOLD,
        ));
    }

    #[test]
    fn compute_elbow_resize_patch_mirrors_binding_points() {
        let patch = compute_elbow_resize_patch(
            Some(&FixedPointBinding::new(
                "rect-1",
                DrawPoint::new(0.25, 0.5),
                "orbit",
            )),
            None,
            None,
            None,
            true,
            false,
        );

        let fixed_point = patch
            .get("startBinding")
            .and_then(Value::as_object)
            .and_then(|binding| binding.get("fixedPoint"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap();
        assert_eq!(fixed_point[0].as_f64(), Some(0.75));
        assert_eq!(fixed_point[1].as_f64(), Some(0.5));
    }
}
