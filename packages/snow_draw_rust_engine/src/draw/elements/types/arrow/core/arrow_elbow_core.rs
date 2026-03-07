#![allow(dead_code)]

use std::collections::HashMap;

use serde_json::{Map, Value};

pub use crate::draw::elements::types::arrow::elbow::elbow_editing::*;
pub use crate::draw::elements::types::arrow::elbow::elbow_router::*;

use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowBindingMode, ArrowData, ElbowFixedSegment,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::elbow::elbow_edit_pipeline::ElbowPipelineElement;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle, StrokeStyle};
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

use super::arrow_geom::normalize_arrow_from_global_points;
use super::arrow_types::{ArrowPatch, ArrowState, EngineContext, FixedPointBinding, FixedSegment};

const DEDUP_THRESHOLD: f64 = 1.0;

#[derive(Clone, Debug, Default, PartialEq)]
enum FixedSegmentsUpdate {
    #[default]
    Unset,
    Null,
    Value(Vec<ElbowFixedSegment>),
}

#[derive(Clone, Debug, PartialEq)]
struct CoreElbowElement {
    rect: DrawRect,
    rotation: f64,
    previous_data: Option<ArrowData>,
}

impl ElbowPipelineElement for CoreElbowElement {
    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn rotation(&self) -> f64 {
        self.rotation
    }

    fn previous_arrow_data(&self) -> Option<&ArrowData> {
        self.previous_data.as_ref()
    }
}

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

/// Updates elbow-arrow geometry from the JSON-like core input map.
///
/// This mirrors the Dart entrypoint shape:
/// - when `updates` are present, it applies those edits through the Rust elbow
///   edit pipeline and echoes explicit binding updates;
/// - otherwise it recomputes the elbow patch from the current arrow state.
pub fn update_elbow_arrow_points(input: ArrowPatch) -> ArrowPatch {
    if input.contains_key("updates") {
        update_elbow_arrow_patch(&input)
    } else {
        recompute_elbow_patch(&input)
    }
}

fn update_elbow_arrow_patch(input: &ArrowPatch) -> ArrowPatch {
    let updates = input
        .get("updates")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();

    let mut patch = compute_elbow_patch(input, Some(&updates));
    if updates.is_empty() {
        return patch;
    }

    if !patch.contains_key("fixedSegments") && updates.contains_key("fixedSegments") {
        patch.insert(
            "fixedSegments".to_string(),
            updates.get("fixedSegments").cloned().unwrap_or(Value::Null),
        );
    }
    if let Some(value) = updates.get("startBinding") {
        patch.insert("startBinding".to_string(), value.clone());
    }
    if let Some(value) = updates.get("endBinding") {
        patch.insert("endBinding".to_string(), value.clone());
    }

    patch
}

fn recompute_elbow_patch(input: &ArrowPatch) -> ArrowPatch {
    compute_elbow_patch(input, None)
}

fn compute_elbow_patch(input: &ArrowPatch, updates: Option<&Map<String, Value>>) -> ArrowPatch {
    let Some(arrow) = input.get("arrow").and_then(read_arrow_state) else {
        return ArrowPatch::new();
    };

    if arrow.points.len() < 2 {
        let mut patch = ArrowPatch::new();
        let points = updates
            .and_then(|value| value.get("points"))
            .and_then(read_points)
            .unwrap_or_else(|| arrow.points.clone());
        patch.insert("points".to_string(), points_to_value(&points));
        return patch;
    }

    let context = input
        .get("context")
        .and_then(read_engine_context)
        .unwrap_or_default();
    let is_dragging = input
        .get("options")
        .and_then(Value::as_object)
        .and_then(|options| options.get("isDragging"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let validate_invariants = input
        .get("options")
        .and_then(Value::as_object)
        .and_then(|options| options.get("validateInvariants"))
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let update_points = match updates.and_then(|value| value.get("points")) {
        Some(value) => Some(apply_point_update(&arrow.points, read_points(value))),
        None => None,
    };
    if validate_invariants {
        validate_point_update(&arrow.points, update_points.as_deref());
    }

    let fixed_segments_update = updates
        .and_then(|value| value.get("fixedSegments"))
        .map(read_fixed_segments_update)
        .unwrap_or_default();
    let start_binding_update = updates
        .and_then(|value| value.get("startBinding"))
        .map(read_binding_update)
        .unwrap_or_default();
    let end_binding_update = updates
        .and_then(|value| value.get("endBinding"))
        .map(read_binding_update)
        .unwrap_or_default();

    let old_rect = arrow.rect();
    let arrow_data = to_domain_arrow_data(&arrow);
    let arrow_element = CoreElbowElement {
        rect: old_rect,
        rotation: 0.0,
        previous_data: Some(arrow_data.clone()),
    };

    let bindable_elements = input
        .get("bindables")
        .map(read_bindable_elements)
        .unwrap_or_default();
    let overlay = HashMap::<String, CoreElbowElement>::new();
    let lookup = CombinedElementLookup::new(&bindable_elements, &overlay);

    let result = compute_elbow_edit(
        &arrow_element,
        &arrow_data,
        &lookup,
        update_points,
        fixed_segments_override_to_option(&fixed_segments_update),
        start_binding_update.clone(),
        end_binding_update.clone(),
        !is_dragging,
    );

    build_patch_from_result(
        &arrow,
        old_rect,
        &result,
        context.max_coordinate,
        &fixed_segments_update,
    )
}

fn build_patch_from_result(
    arrow: &ArrowState,
    old_rect: DrawRect,
    result: &ElbowEditResult,
    max_coordinate: f64,
    fixed_segments_update: &FixedSegmentsUpdate,
) -> ArrowPatch {
    let world_points = result
        .local_points
        .iter()
        .copied()
        .map(|point| DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
        .collect::<Vec<_>>();
    let normalized = normalize_arrow_from_global_points(&world_points, max_coordinate);
    let new_rect = DrawRect::new(
        normalized.x,
        normalized.y,
        normalized.x + normalized.width,
        normalized.y + normalized.height,
    );
    let normalized_fixed_segments =
        transform_fixed_segments(result.fixed_segments.as_deref(), old_rect, new_rect, 0.0);

    let mut patch = ArrowPatch::new();
    patch.insert("x".to_string(), Value::from(normalized.x));
    patch.insert("y".to_string(), Value::from(normalized.y));
    patch.insert("width".to_string(), Value::from(normalized.width));
    patch.insert("height".to_string(), Value::from(normalized.height));
    patch.insert("points".to_string(), points_to_value(&normalized.points));

    match normalized_fixed_segments {
        Some(segments) => {
            patch.insert(
                "fixedSegments".to_string(),
                Value::Array(
                    segments
                        .iter()
                        .map(model_fixed_segment_to_value)
                        .collect::<Vec<_>>(),
                ),
            );
        }
        None => {
            if matches!(fixed_segments_update, FixedSegmentsUpdate::Null) {
                patch.insert("fixedSegments".to_string(), Value::Null);
            }
        }
    }

    if let Some(value) = result.start_is_special {
        patch.insert("startIsSpecial".to_string(), Value::Bool(value));
    }
    if let Some(value) = result.end_is_special {
        patch.insert("endIsSpecial".to_string(), Value::Bool(value));
    }

    let previous_start_binding = arrow.start_binding.as_ref().map(core_binding_to_domain);
    if result.start_binding != previous_start_binding {
        patch.insert(
            "startBinding".to_string(),
            result
                .start_binding
                .as_ref()
                .map(domain_binding_to_value)
                .unwrap_or(Value::Null),
        );
    }

    let previous_end_binding = arrow.end_binding.as_ref().map(core_binding_to_domain);
    if result.end_binding != previous_end_binding {
        patch.insert(
            "endBinding".to_string(),
            result
                .end_binding
                .as_ref()
                .map(domain_binding_to_value)
                .unwrap_or(Value::Null),
        );
    }

    patch
}

fn apply_point_update(
    points: &[DrawPoint],
    updated_points: Option<Vec<DrawPoint>>,
) -> Vec<DrawPoint> {
    let Some(updated_points) = updated_points else {
        return points.to_vec();
    };

    if updated_points.len() == 2 && points.len() > 2 {
        return points
            .iter()
            .enumerate()
            .map(|(index, point)| {
                if index == 0 {
                    updated_points[0]
                } else if index + 1 == points.len() {
                    updated_points[1]
                } else {
                    *point
                }
            })
            .collect();
    }

    updated_points
}

fn validate_point_update(current_points: &[DrawPoint], updated_points: Option<&[DrawPoint]>) {
    let Some(updated_points) = updated_points else {
        return;
    };
    let valid = updated_points.len() == 2 || updated_points.len() == current_points.len();
    assert!(
        valid,
        "Updated point array length must match the arrow point length or contain exactly the new start and end points"
    );
}

fn read_arrow_state(value: &Value) -> Option<ArrowState> {
    let arrow = value.as_object()?;
    Some(ArrowState {
        id: arrow
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        x: arrow.get("x").and_then(Value::as_f64).unwrap_or(0.0),
        y: arrow.get("y").and_then(Value::as_f64).unwrap_or(0.0),
        width: arrow.get("width").and_then(Value::as_f64).unwrap_or(0.0),
        height: arrow.get("height").and_then(Value::as_f64).unwrap_or(0.0),
        points: arrow
            .get("points")
            .and_then(read_points)
            .unwrap_or_default(),
        start_binding: arrow.get("startBinding").and_then(read_binding),
        end_binding: arrow.get("endBinding").and_then(read_binding),
        start_arrowhead: arrow
            .get("startArrowhead")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        end_arrowhead: arrow
            .get("endArrowhead")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        elbowed: arrow
            .get("elbowed")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        fixed_segments: arrow.get("fixedSegments").and_then(read_fixed_segments),
        start_is_special: arrow.get("startIsSpecial").and_then(Value::as_bool),
        end_is_special: arrow.get("endIsSpecial").and_then(Value::as_bool),
    })
}

fn read_engine_context(value: &Value) -> Option<EngineContext> {
    let context = value.as_object()?;
    Some(EngineContext {
        zoom: context.get("zoom").and_then(Value::as_f64).unwrap_or(1.0),
        is_binding_enabled: context
            .get("isBindingEnabled")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        bind_mode: super::arrow_types::BIND_MODE_ORBIT,
        max_coordinate: context
            .get("maxCoordinate")
            .and_then(Value::as_f64)
            .filter(|value| value.is_finite() && *value > 0.0)
            .unwrap_or(1e6),
    })
}

fn read_bindable_elements(value: &Value) -> HashMap<String, CoreElbowElement> {
    let Some(bindables) = value.as_array() else {
        return HashMap::new();
    };

    bindables
        .iter()
        .filter_map(read_bindable_element)
        .map(|(id, element)| (id, element))
        .collect()
}

fn read_bindable_element(value: &Value) -> Option<(String, CoreElbowElement)> {
    let bindable = value.as_object()?;
    let id = bindable.get("id")?.as_str()?.to_string();
    let x = bindable.get("x").and_then(Value::as_f64)?;
    let y = bindable.get("y").and_then(Value::as_f64)?;
    let width = bindable.get("width").and_then(Value::as_f64)?;
    let height = bindable.get("height").and_then(Value::as_f64)?;
    let rotation = bindable.get("angle").and_then(Value::as_f64).unwrap_or(0.0);

    Some((
        id,
        CoreElbowElement {
            rect: DrawRect::new(x, y, x + width, y + height),
            rotation,
            previous_data: None,
        },
    ))
}

fn to_domain_arrow_data(arrow: &ArrowState) -> ArrowData {
    let rect = arrow.rect();
    let world_points = arrow
        .points
        .iter()
        .copied()
        .map(|point| DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
        .collect::<Vec<_>>();

    ArrowData {
        points: ArrowGeometry::normalize_points(&world_points, rect),
        color: Default::default(),
        stroke_width: 1.0,
        stroke_style: StrokeStyle::Solid,
        arrow_type: if arrow.elbowed {
            ArrowType::Elbow
        } else {
            ArrowType::Straight
        },
        start_arrowhead: parse_arrowhead(arrow.start_arrowhead.as_deref()),
        end_arrowhead: parse_arrowhead(arrow.end_arrowhead.as_deref()),
        start_binding: arrow.start_binding.as_ref().map(core_binding_to_domain),
        end_binding: arrow.end_binding.as_ref().map(core_binding_to_domain),
        fixed_segments: arrow
            .fixed_segments
            .as_ref()
            .map(|segments| segments.iter().map(core_fixed_segment_to_domain).collect()),
        start_is_special: arrow.start_is_special,
        end_is_special: arrow.end_is_special,
    }
}

fn core_binding_to_domain(binding: &FixedPointBinding) -> DomainArrowBinding {
    DomainArrowBinding::new(
        binding.element_id.clone(),
        binding.fixed_point,
        parse_binding_mode(Some(binding.mode.as_str())),
    )
}

fn domain_binding_to_value(binding: &DomainArrowBinding) -> Value {
    binding_to_value(&FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            ArrowBindingMode::Inside => "inside",
            ArrowBindingMode::Orbit => "orbit",
            ArrowBindingMode::Skip => "skip",
        }
        .to_string(),
    ))
}

fn core_fixed_segment_to_domain(segment: &FixedSegment) -> ElbowFixedSegment {
    ElbowFixedSegment::new(segment.index, segment.start, segment.end)
}

fn parse_arrowhead(value: Option<&str>) -> ArrowheadStyle {
    match value.unwrap_or("none") {
        "standard" => ArrowheadStyle::Standard,
        "triangle" => ArrowheadStyle::Triangle,
        "triangleOutline" => ArrowheadStyle::TriangleOutline,
        "square" => ArrowheadStyle::Square,
        "dot" => ArrowheadStyle::Dot,
        "circle" => ArrowheadStyle::Circle,
        "circleOutline" => ArrowheadStyle::CircleOutline,
        "diamond" => ArrowheadStyle::Diamond,
        "diamondOutline" => ArrowheadStyle::DiamondOutline,
        "crowfootOne" => ArrowheadStyle::CrowfootOne,
        "crowfootMany" => ArrowheadStyle::CrowfootMany,
        "crowfootOneOrMany" => ArrowheadStyle::CrowfootOneOrMany,
        "invertedTriangle" => ArrowheadStyle::InvertedTriangle,
        "verticalLine" => ArrowheadStyle::VerticalLine,
        _ => ArrowheadStyle::None,
    }
}

fn parse_binding_mode(value: Option<&str>) -> ArrowBindingMode {
    match value.unwrap_or("orbit") {
        "inside" => ArrowBindingMode::Inside,
        "skip" => ArrowBindingMode::Skip,
        _ => ArrowBindingMode::Orbit,
    }
}

fn read_binding_update(value: &Value) -> BindingOverride<DomainArrowBinding> {
    if value.is_null() {
        BindingOverride::Clear
    } else {
        read_binding(value)
            .map(|binding| BindingOverride::Value(core_binding_to_domain(&binding)))
            .unwrap_or(BindingOverride::Unset)
    }
}

fn read_fixed_segments_update(value: &Value) -> FixedSegmentsUpdate {
    if value.is_null() {
        FixedSegmentsUpdate::Null
    } else {
        read_fixed_segments(value)
            .map(|segments| {
                FixedSegmentsUpdate::Value(
                    segments
                        .iter()
                        .map(core_fixed_segment_to_domain)
                        .collect::<Vec<_>>(),
                )
            })
            .unwrap_or(FixedSegmentsUpdate::Unset)
    }
}

fn fixed_segments_override_to_option(
    update: &FixedSegmentsUpdate,
) -> Option<Vec<ElbowFixedSegment>> {
    match update {
        FixedSegmentsUpdate::Unset => None,
        FixedSegmentsUpdate::Null => Some(Vec::new()),
        FixedSegmentsUpdate::Value(value) => Some(value.clone()),
    }
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

fn points_to_value(points: &[DrawPoint]) -> Value {
    Value::Array(
        points
            .iter()
            .map(|point| Value::Array(vec![Value::from(point.x), Value::from(point.y)]))
            .collect(),
    )
}

fn model_fixed_segment_to_value(segment: &ElbowFixedSegment) -> Value {
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
    use crate::draw::elements::types::arrow::core::adapters::apply_arrow_patch;
    use serde_json::json;

    fn read_patch_points(patch: &ArrowPatch) -> Vec<DrawPoint> {
        patch
            .get("points")
            .and_then(read_points)
            .unwrap_or_default()
    }

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

    #[test]
    fn update_elbow_arrow_points_dispatches_real_recompute_logic() {
        let input = json!({
            "arrow": {
                "id": "arrow-1",
                "x": 10.0,
                "y": 20.0,
                "width": 40.0,
                "height": 30.0,
                "points": [[0.0, 0.0], [40.0, 30.0]],
                "elbowed": true,
                "startArrowhead": "none",
                "endArrowhead": "standard"
            },
            "context": {
                "zoom": 1.0,
                "maxCoordinate": 1000000.0
            }
        });

        let patch = update_elbow_arrow_points(
            input
                .as_object()
                .cloned()
                .expect("input object for elbow update"),
        );
        let points = read_patch_points(&patch);

        assert!(points.len() >= 2);
        assert!(validate_elbow_points(&points, DEDUP_THRESHOLD));
        assert!(patch.get("x").and_then(Value::as_f64).is_some());
        assert!(patch.get("y").and_then(Value::as_f64).is_some());
    }

    #[test]
    fn update_elbow_arrow_points_echoes_explicit_binding_and_segment_updates() {
        let input = json!({
            "arrow": {
                "id": "arrow-2",
                "x": 0.0,
                "y": 0.0,
                "width": 80.0,
                "height": 60.0,
                "points": [[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [80.0, 60.0]],
                "fixedSegments": [
                    {"index": 2, "start": [20.0, 0.0], "end": [20.0, 20.0]}
                ],
                "elbowed": true,
                "startArrowhead": "none",
                "endArrowhead": "standard"
            },
            "updates": {
                "points": [[5.0, 5.0], [75.0, 55.0]],
                "startBinding": {
                    "elementId": "box-1",
                    "fixedPoint": [0.25, 0.5],
                    "mode": "orbit"
                },
                "fixedSegments": null
            },
            "options": {
                "isDragging": true
            },
            "context": {
                "zoom": 1.0,
                "maxCoordinate": 1000000.0
            }
        });

        let patch = update_elbow_arrow_points(
            input
                .as_object()
                .cloned()
                .expect("input object for elbow update"),
        );

        assert!(patch.contains_key("startBinding"));
        assert!(patch.contains_key("fixedSegments"));
        assert!(patch.get("fixedSegments").is_some_and(Value::is_null));
        assert!(validate_elbow_points(
            &read_patch_points(&patch),
            DEDUP_THRESHOLD
        ));
    }

    #[test]
    fn update_elbow_arrow_points_allows_endpoint_drag_point_growth_by_default() {
        let input = json!({
            "arrow": {
                "id": "arrow-3",
                "x": 0.0,
                "y": 0.0,
                "width": 80.0,
                "height": 60.0,
                "points": [
                    [0.0, 0.0],
                    [20.0, 0.0],
                    [20.0, 20.0],
                    [40.0, 20.0],
                    [40.0, 40.0],
                    [60.0, 40.0],
                    [60.0, 60.0],
                    [80.0, 60.0]
                ],
                "fixedSegments": [
                    {"index": 2, "start": [20.0, 0.0], "end": [20.0, 20.0]},
                    {"index": 4, "start": [40.0, 20.0], "end": [40.0, 40.0]}
                ],
                "elbowed": true,
                "startArrowhead": "none",
                "endArrowhead": "standard"
            },
            "updates": {
                "points": [
                    [0.0, 10.0],
                    [20.0, 0.0],
                    [20.0, 20.0],
                    [40.0, 20.0],
                    [40.0, 40.0],
                    [60.0, 40.0],
                    [60.0, 60.0],
                    [80.0, 60.0],
                    [80.0, 90.0]
                ]
            },
            "options": {
                "isDragging": true
            },
            "context": {
                "zoom": 1.0,
                "maxCoordinate": 1000000.0
            }
        });

        let patch = update_elbow_arrow_points(
            input
                .as_object()
                .cloned()
                .expect("input object for elbow growth update"),
        );
        let patched = apply_arrow_patch(
            &read_arrow_state(&input["arrow"]).expect("arrow state"),
            &patch,
        );
        let global_start = [
            patched.x + patched.points[0].x,
            patched.y + patched.points[0].y,
        ];
        let global_end = [
            patched.x + patched.points.last().expect("end point").x,
            patched.y + patched.points.last().expect("end point").y,
        ];

        assert_eq!(patched.points.len(), 9);
        assert!(validate_elbow_invariant(&patched).is_empty());
        assert!((global_start[0] - 0.0).abs() < 1e-9);
        assert!((global_start[1] - 10.0).abs() < 1e-9);
        assert!((global_end[0] - 80.0).abs() < 1e-9);
        assert!((global_end[1] - 90.0).abs() < 1e-9);
    }

    #[test]
    #[should_panic(
        expected = "Updated point array length must match the arrow point length or contain exactly the new start and end points"
    )]
    fn update_elbow_arrow_points_rejects_point_growth_when_validation_is_enabled() {
        let input = json!({
            "arrow": {
                "id": "arrow-4",
                "x": 0.0,
                "y": 0.0,
                "width": 80.0,
                "height": 60.0,
                "points": [
                    [0.0, 0.0],
                    [20.0, 0.0],
                    [20.0, 20.0],
                    [40.0, 20.0],
                    [40.0, 40.0],
                    [60.0, 40.0],
                    [60.0, 60.0],
                    [80.0, 60.0]
                ],
                "elbowed": true,
                "startArrowhead": "none",
                "endArrowhead": "standard"
            },
            "updates": {
                "points": [
                    [0.0, 10.0],
                    [20.0, 0.0],
                    [20.0, 20.0],
                    [40.0, 20.0],
                    [40.0, 40.0],
                    [60.0, 40.0],
                    [60.0, 60.0],
                    [80.0, 60.0],
                    [80.0, 90.0]
                ]
            },
            "options": {
                "validateInvariants": true
            },
            "context": {
                "zoom": 1.0,
                "maxCoordinate": 1000000.0
            }
        });

        let _ = update_elbow_arrow_points(
            input
                .as_object()
                .cloned()
                .expect("input object for validated elbow growth update"),
        );
    }
}
