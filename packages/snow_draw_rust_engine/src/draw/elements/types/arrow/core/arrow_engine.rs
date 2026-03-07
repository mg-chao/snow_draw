#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use serde_json::Value;

pub use super::arrow_focus_core::{
    resolve_focus_point_hit, resolve_focus_point_hit_with_offset, resolve_visible_focus_points,
};
pub use super::arrow_state_core::apply_engine_result;
pub use super::arrow_state_core::reduce_arrow_engine_events_to_order;

use super::arrow_binding_core::{
    calculate_fixed_point_for_binding, get_global_fixed_point_for_bindable_element,
    get_snap_outline_mid_point, max_binding_distance_simple, pick_hovered_bindable_for_focus,
};
use super::arrow_binding_lifecycle::{
    derive_bindable_patches_for_binding_change, reconcile_bindable_patches_for_arrow,
};
use super::arrow_elbow_core::{validate_elbow_invariant, validate_elbow_points};
use super::arrow_geom::normalize_arrow_from_global_points;
use super::arrow_types::{
    ArrowBindingState, ArrowEndpointEdge, ArrowEngineEvent, ArrowPatch, ArrowState, BindablePatch,
    BindableRelationState, BindableState, BindingBrokenEvent, EngineContext, EngineResult,
    FixedPointBinding, ReorderArrowEvent, SuggestedBinding, ValidationReport,
};
use crate::draw::types::draw_point::DrawPoint;

pub fn empty_engine_result() -> EngineResult {
    EngineResult {
        arrow_patch: ArrowPatch::new(),
        bindable_patches: Vec::new(),
        suggested_binding: None,
        events: Vec::new(),
    }
}

pub fn finalize_focus_drag(
    arrow: &ArrowBindingState,
    bindables: &[BindableRelationState],
) -> EngineResult {
    EngineResult {
        arrow_patch: ArrowPatch::new(),
        bindable_patches: reconcile_bindable_patches_for_arrow(arrow, bindables),
        suggested_binding: None,
        events: Vec::new(),
    }
}

pub fn compute_focus_drag(
    arrow: &ArrowState,
    pointer: DrawPoint,
    dragged_edge: ArrowEndpointEdge,
    bindables: &[BindableState],
    context: EngineContext,
    switch_to_inside_binding: bool,
) -> EngineResult {
    if arrow.elbowed || arrow.points.len() < 2 {
        return empty_engine_result();
    }

    let mut bindables_by_id = HashMap::<String, BindableState>::new();
    for bindable in bindables {
        bindables_by_id.insert(bindable.id.clone(), bindable.clone());
    }

    let mut start_binding = arrow.start_binding.clone();
    let mut end_binding = arrow.end_binding.clone();
    let mut next_global_points = global_points(arrow);

    let hovered = if context.is_binding_enabled && !bindables.is_empty() {
        pick_hovered_bindable_for_focus(
            pointer,
            arrow,
            bindables,
            max_binding_distance_simple(context.zoom),
        )
    } else {
        None
    };

    let dragged_index = match dragged_edge {
        ArrowEndpointEdge::Start => 0,
        ArrowEndpointEdge::End => arrow.points.len() - 1,
    };
    let other_edge = match dragged_edge {
        ArrowEndpointEdge::Start => ArrowEndpointEdge::End,
        ArrowEndpointEdge::End => ArrowEndpointEdge::Start,
    };
    let other_index = match other_edge {
        ArrowEndpointEdge::Start => 0,
        ArrowEndpointEdge::End => arrow.points.len() - 1,
    };

    let current_dragged_binding =
        binding_for_edge(dragged_edge, &start_binding, &end_binding).cloned();
    if let Some(hovered) = hovered.as_ref() {
        let mut mode = current_dragged_binding
            .as_ref()
            .map(|binding| binding.mode.clone())
            .unwrap_or_else(|| "orbit".to_string());
        if switch_to_inside_binding && mode == "orbit" {
            mode = "inside".to_string();
        } else if !switch_to_inside_binding && mode == "inside" {
            mode = "orbit".to_string();
        }

        let next_binding = FixedPointBinding::new(
            hovered.id.clone(),
            calculate_fixed_point_for_binding(pointer, hovered),
            mode,
        );
        set_binding_for_edge(
            dragged_edge,
            Some(next_binding),
            &mut start_binding,
            &mut end_binding,
        );
    } else {
        set_binding_for_edge(dragged_edge, None, &mut start_binding, &mut end_binding);
        next_global_points[dragged_index] = pointer;
    }

    let dragged_binding = binding_for_edge(dragged_edge, &start_binding, &end_binding).cloned();
    let dragged_bindable = dragged_binding
        .as_ref()
        .and_then(|binding| bindables_by_id.get(&binding.element_id))
        .cloned();

    if let (Some(dragged_binding), Some(dragged_bindable)) =
        (dragged_binding.as_ref(), dragged_bindable.as_ref())
    {
        let opposite_binding = binding_for_edge(other_edge, &start_binding, &end_binding);
        let bound_to_same_element = opposite_binding
            .map(|binding| binding.element_id == dragged_binding.element_id)
            .unwrap_or(false);
        let updated_dragged_binding = FixedPointBinding::new(
            dragged_binding.element_id.clone(),
            dragged_binding.fixed_point,
            if switch_to_inside_binding || bound_to_same_element {
                "inside"
            } else {
                "orbit"
            },
        );
        set_binding_for_edge(
            dragged_edge,
            Some(updated_dragged_binding.clone()),
            &mut start_binding,
            &mut end_binding,
        );
        next_global_points[dragged_index] =
            get_global_fixed_point_for_bindable_element(&updated_dragged_binding, dragged_bindable);
    }

    if let Some(other_binding) = binding_for_edge(other_edge, &start_binding, &end_binding).cloned()
    {
        if other_binding.mode == "orbit" && context.is_binding_enabled {
            if let Some(other_bindable) = bindables_by_id.get(&other_binding.element_id) {
                let bound_to_same_after_update = dragged_bindable
                    .as_ref()
                    .map(|bindable| bindable.id == other_binding.element_id)
                    .unwrap_or(false);
                let updated_other_binding = FixedPointBinding::new(
                    other_binding.element_id.clone(),
                    other_binding.fixed_point,
                    if switch_to_inside_binding || bound_to_same_after_update {
                        "inside"
                    } else {
                        "orbit"
                    },
                );
                set_binding_for_edge(
                    other_edge,
                    Some(updated_other_binding.clone()),
                    &mut start_binding,
                    &mut end_binding,
                );
                next_global_points[other_index] = get_global_fixed_point_for_bindable_element(
                    &updated_other_binding,
                    other_bindable,
                );
            }
        }
    }

    let mut patch = compute_patch_from_global_points(&next_global_points, context.max_coordinate);
    patch.insert(
        "startBinding".to_string(),
        binding_to_value(start_binding.as_ref()),
    );
    patch.insert(
        "endBinding".to_string(),
        binding_to_value(end_binding.as_ref()),
    );

    let previous = ArrowBindingState {
        id: arrow.id.clone(),
        start_binding: arrow.start_binding.clone(),
        end_binding: arrow.end_binding.clone(),
    };
    let next = ArrowBindingState {
        id: arrow.id.clone(),
        start_binding: start_binding.clone(),
        end_binding: end_binding.clone(),
    };
    let bindable_patches = derive_bindable_patches_for_binding_change(&arrow.id, &previous, &next);

    let mut events = Vec::new();
    let mut reorder_targets = HashSet::<String>::new();
    collect_binding_transition(
        &arrow.id,
        ArrowEndpointEdge::Start,
        arrow.start_binding.as_ref(),
        start_binding.as_ref(),
        &mut events,
        &mut reorder_targets,
    );
    collect_binding_transition(
        &arrow.id,
        ArrowEndpointEdge::End,
        arrow.end_binding.as_ref(),
        end_binding.as_ref(),
        &mut events,
        &mut reorder_targets,
    );

    EngineResult {
        arrow_patch: patch,
        bindable_patches,
        suggested_binding: hovered.map(|bindable| SuggestedBinding {
            bindable_id: Some(bindable.id.clone()),
            mid_point: get_snap_outline_mid_point(pointer, &bindable, context.zoom),
            element: bindable,
        }),
        events,
    }
}

pub fn validate_arrow_invariant(arrow: &ArrowState) -> ValidationReport {
    let mut violations = Vec::new();
    if arrow.points.len() < 2 {
        violations.push("arrow must contain at least two points".to_string());
    }
    if let Some(first) = arrow.points.first() {
        if *first != DrawPoint::ZERO {
            violations
                .push("arrow points must be normalized with [0,0] as first point".to_string());
        }
    }
    if arrow.elbowed {
        if !validate_elbow_points(&arrow.points, 1.0) {
            violations.push("elbow arrow must keep orthogonal segments".to_string());
        }
        violations.extend(validate_elbow_invariant(arrow));
    }
    ValidationReport {
        valid: violations.is_empty(),
        violations,
    }
}

fn binding_for_edge<'a>(
    edge: ArrowEndpointEdge,
    start_binding: &'a Option<FixedPointBinding>,
    end_binding: &'a Option<FixedPointBinding>,
) -> Option<&'a FixedPointBinding> {
    match edge {
        ArrowEndpointEdge::Start => start_binding.as_ref(),
        ArrowEndpointEdge::End => end_binding.as_ref(),
    }
}

fn set_binding_for_edge(
    edge: ArrowEndpointEdge,
    binding: Option<FixedPointBinding>,
    start_binding: &mut Option<FixedPointBinding>,
    end_binding: &mut Option<FixedPointBinding>,
) {
    match edge {
        ArrowEndpointEdge::Start => *start_binding = binding,
        ArrowEndpointEdge::End => *end_binding = binding,
    }
}

fn global_points(arrow: &ArrowState) -> Vec<DrawPoint> {
    arrow
        .points
        .iter()
        .map(|point| DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
        .collect()
}

fn compute_patch_from_global_points(points: &[DrawPoint], max_coordinate: f64) -> ArrowPatch {
    let normalized = normalize_arrow_from_global_points(points, max_coordinate);
    let mut patch = ArrowPatch::new();
    patch.insert("x".to_string(), Value::from(normalized.x));
    patch.insert("y".to_string(), Value::from(normalized.y));
    patch.insert("width".to_string(), Value::from(normalized.width));
    patch.insert("height".to_string(), Value::from(normalized.height));
    patch.insert(
        "points".to_string(),
        Value::Array(
            normalized
                .points
                .iter()
                .map(|point| Value::Array(vec![Value::from(point.x), Value::from(point.y)]))
                .collect(),
        ),
    );
    patch
}

fn collect_binding_transition(
    arrow_id: &str,
    edge: ArrowEndpointEdge,
    previous_binding: Option<&FixedPointBinding>,
    next_binding: Option<&FixedPointBinding>,
    events: &mut Vec<ArrowEngineEvent>,
    reorder_targets: &mut HashSet<String>,
) {
    if let Some(previous_binding) = previous_binding {
        if next_binding
            .map(|binding| binding.element_id.as_str() != previous_binding.element_id.as_str())
            .unwrap_or(true)
        {
            if next_binding.is_none() {
                events.push(ArrowEngineEvent::BindingBroken(BindingBrokenEvent {
                    arrow_id: arrow_id.to_string(),
                    edge,
                }));
            }
        }
    }

    if let Some(next_binding) = next_binding {
        if previous_binding
            .map(|binding| binding.element_id.as_str() != next_binding.element_id.as_str())
            .unwrap_or(true)
        {
            if reorder_targets.insert(next_binding.element_id.clone()) {
                events.push(ArrowEngineEvent::ReorderArrow(ReorderArrowEvent {
                    arrow_id: arrow_id.to_string(),
                    bindable_id: next_binding.element_id.clone(),
                }));
            }
        }
    }
}

fn binding_to_value(binding: Option<&FixedPointBinding>) -> Value {
    let Some(binding) = binding else {
        return Value::Null;
    };
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

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_arrow() -> ArrowState {
        ArrowState {
            id: "arrow-1".to_string(),
            x: 10.0,
            y: 10.0,
            width: 100.0,
            height: 20.0,
            points: vec![DrawPoint::ZERO, DrawPoint::new(100.0, 20.0)],
            start_binding: None,
            end_binding: None,
            start_arrowhead: None,
            end_arrowhead: None,
            elbowed: false,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }

    fn sample_bindable(id: &str) -> BindableState {
        BindableState {
            id: id.to_string(),
            shape: "rectangle".to_string(),
            x: 20.0,
            y: 30.0,
            width: 100.0,
            height: 80.0,
            angle: 0.0,
            stroke_width: 2.0,
            roundness: None,
            z_index: Some(1.0),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: None,
        }
    }

    #[test]
    fn validate_arrow_invariant_requires_two_points_and_zero_origin() {
        let mut arrow = sample_arrow();
        arrow.points = vec![DrawPoint::new(1.0, 0.0)];

        let report = validate_arrow_invariant(&arrow);

        assert!(!report.valid);
        assert_eq!(report.violations.len(), 2);
    }

    #[test]
    fn finalize_focus_drag_reconciles_missing_relation_membership() {
        let arrow = ArrowBindingState {
            id: "arrow-1".to_string(),
            start_binding: Some(FixedPointBinding::new(
                "rect-1",
                DrawPoint::new(0.2, 0.5),
                "orbit",
            )),
            end_binding: None,
        };
        let bindables = vec![BindableRelationState {
            id: "rect-1".to_string(),
            bound_arrow_ids: Vec::new(),
        }];

        let result = finalize_focus_drag(&arrow, &bindables);

        assert_eq!(result.bindable_patches.len(), 1);
        assert_eq!(
            result.bindable_patches[0].add_bound_arrow_id.as_deref(),
            Some("arrow-1")
        );
    }

    #[test]
    fn compute_focus_drag_suggests_hovered_bindable() {
        let arrow = sample_arrow();
        let bindable = sample_bindable("rect-1");

        let result = compute_focus_drag(
            &arrow,
            DrawPoint::new(20.0, 60.0),
            ArrowEndpointEdge::Start,
            &[bindable],
            EngineContext {
                zoom: 1.0,
                is_binding_enabled: true,
                bind_mode: "orbit",
                max_coordinate: 1e6,
            },
            false,
        );

        assert_eq!(
            result
                .suggested_binding
                .as_ref()
                .and_then(|binding| binding.bindable_id.as_deref()),
            Some("rect-1")
        );
    }
}
