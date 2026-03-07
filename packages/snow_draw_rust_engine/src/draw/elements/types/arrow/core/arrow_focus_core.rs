#![allow(dead_code)]

use super::arrow_binding_core::{
    get_global_fixed_point_for_bindable_element, max_binding_distance_simple,
};
use super::arrow_hit_test::{
    distance_to_bindable_outline, is_bindable_visible_at_point, is_point_in_bindable,
};
use super::arrow_types::{
    ArrowEndpointEdge, ArrowState, BindableState, EngineContext, FixedPointBinding,
    FocusPointDescriptor, FocusPointHit,
};
use crate::draw::types::draw_point::DrawPoint;

const FOCUS_POINT_SIZE: f64 = 10.0 / 1.5;

fn focus_hit_threshold(zoom: f64) -> f64 {
    (FOCUS_POINT_SIZE * 1.5) / zoom.max(1e-6)
}

fn binding_gap(bindable: &BindableState, elbowed: bool) -> f64 {
    let base = (bindable.stroke_width.max(1.0) * 2.0).max(6.0);
    if elbowed {
        base.max(8.0)
    } else {
        base
    }
}

fn endpoint_global_point(arrow: &ArrowState, edge: ArrowEndpointEdge) -> Option<DrawPoint> {
    let point = match edge {
        ArrowEndpointEdge::Start => arrow.points.first().copied(),
        ArrowEndpointEdge::End => arrow.points.last().copied(),
    }?;

    Some(DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
}

pub fn is_focus_point_visible(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    binding: &FixedPointBinding,
    bindable: &BindableState,
    context: EngineContext,
    ignore_overlap: bool,
) -> bool {
    if arrow.elbowed || !context.is_binding_enabled || arrow.points.len() != 2 {
        return false;
    }

    let focus_point = get_global_fixed_point_for_bindable_element(binding, bindable);
    if !is_bindable_visible_at_point(focus_point, bindable) {
        return false;
    }

    let threshold = focus_hit_threshold(context.zoom);
    if !ignore_overlap {
        let associated_edge = match arrow.start_binding.as_ref() {
            Some(start_binding) if start_binding.element_id == bindable.id => {
                ArrowEndpointEdge::Start
            }
            _ => ArrowEndpointEdge::End,
        };
        if let Some(associated_point) = endpoint_global_point(arrow, associated_edge) {
            if focus_point.distance(associated_point) < threshold {
                return false;
            }
        }
    }

    let Some(endpoint) = endpoint_global_point(arrow, edge) else {
        return false;
    };

    let inside_or_near_outline = is_point_in_bindable(focus_point, bindable)
        || distance_to_bindable_outline(focus_point, bindable)
            <= binding_gap(bindable, arrow.elbowed);

    focus_point.distance(endpoint) >= threshold && inside_or_near_outline
}

pub fn resolve_visible_focus_points(
    arrow: &ArrowState,
    bindables: &[BindableState],
    context: EngineContext,
    ignore_overlap: bool,
) -> Vec<FocusPointDescriptor> {
    let mut bindables_by_id = std::collections::HashMap::<String, &BindableState>::new();
    for bindable in bindables {
        bindables_by_id.insert(bindable.id.clone(), bindable);
    }

    let mut points = Vec::new();

    if let Some(start_binding) = arrow.start_binding.as_ref() {
        if let Some(bindable) = bindables_by_id.get(&start_binding.element_id) {
            if is_focus_point_visible(
                arrow,
                ArrowEndpointEdge::Start,
                start_binding,
                bindable,
                context,
                ignore_overlap,
            ) {
                points.push(FocusPointDescriptor {
                    edge: ArrowEndpointEdge::Start,
                    point: get_global_fixed_point_for_bindable_element(start_binding, bindable),
                    binding: start_binding.clone(),
                });
            }
        }
    }

    if let Some(end_binding) = arrow.end_binding.as_ref() {
        if let Some(bindable) = bindables_by_id.get(&end_binding.element_id) {
            if is_focus_point_visible(
                arrow,
                ArrowEndpointEdge::End,
                end_binding,
                bindable,
                context,
                ignore_overlap,
            ) {
                points.push(FocusPointDescriptor {
                    edge: ArrowEndpointEdge::End,
                    point: get_global_fixed_point_for_bindable_element(end_binding, bindable),
                    binding: end_binding.clone(),
                });
            }
        }
    }

    points
}

pub fn list_visible_focus_points(
    arrow: &ArrowState,
    bindables: &[BindableState],
    context: EngineContext,
    ignore_overlap: bool,
) -> Vec<FocusPointDescriptor> {
    resolve_visible_focus_points(arrow, bindables, context, ignore_overlap)
}

pub fn resolve_focus_point_hit(
    arrow: &ArrowState,
    bindables: &[BindableState],
    pointer: DrawPoint,
    context: EngineContext,
    ignore_overlap: bool,
) -> Option<ArrowEndpointEdge> {
    resolve_focus_point_hit_with_offset(arrow, bindables, pointer, context, ignore_overlap).edge
}

pub fn pick_focus_point(
    arrow: &ArrowState,
    bindables: &[BindableState],
    pointer: DrawPoint,
    context: EngineContext,
    ignore_overlap: bool,
) -> Option<ArrowEndpointEdge> {
    resolve_focus_point_hit(arrow, bindables, pointer, context, ignore_overlap)
}

pub fn resolve_focus_point_hit_with_offset(
    arrow: &ArrowState,
    bindables: &[BindableState],
    pointer: DrawPoint,
    context: EngineContext,
    ignore_overlap: bool,
) -> FocusPointHit {
    let threshold = focus_hit_threshold(context.zoom);
    for descriptor in resolve_visible_focus_points(arrow, bindables, context, ignore_overlap) {
        if pointer.distance(descriptor.point) <= threshold {
            return FocusPointHit {
                edge: Some(descriptor.edge),
                pointer_offset: DrawPoint::new(
                    pointer.x - descriptor.point.x,
                    pointer.y - descriptor.point.y,
                ),
            };
        }
    }

    FocusPointHit {
        edge: None,
        pointer_offset: DrawPoint::ZERO,
    }
}

pub fn pick_focus_point_with_offset(
    arrow: &ArrowState,
    bindables: &[BindableState],
    pointer: DrawPoint,
    context: EngineContext,
    ignore_overlap: bool,
) -> FocusPointHit {
    resolve_focus_point_hit_with_offset(arrow, bindables, pointer, context, ignore_overlap)
}

pub fn is_point_near_bindable_for_focus(
    point: DrawPoint,
    bindable: &BindableState,
    zoom: f64,
) -> bool {
    is_bindable_visible_at_point(point, bindable)
        && (is_point_in_bindable(point, bindable)
            || distance_to_bindable_outline(point, bindable)
                <= max_binding_distance_simple(zoom) + bindable.stroke_width / 2.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_bindable(id: &str, x: f64, y: f64, width: f64, height: f64) -> BindableState {
        BindableState {
            id: id.to_string(),
            shape: "rectangle".to_string(),
            x,
            y,
            width,
            height,
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

    fn sample_arrow(start_binding: Option<FixedPointBinding>) -> ArrowState {
        ArrowState {
            id: "arrow-1".to_string(),
            x: 10.0,
            y: 10.0,
            width: 100.0,
            height: 20.0,
            points: vec![DrawPoint::ZERO, DrawPoint::new(100.0, 20.0)],
            start_binding,
            end_binding: None,
            start_arrowhead: None,
            end_arrowhead: None,
            elbowed: false,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }

    #[test]
    fn visible_focus_points_use_binding_anchor_instead_of_endpoint() {
        let bindable = sample_bindable("rect-1", 20.0, 30.0, 100.0, 80.0);
        let binding = FixedPointBinding::new("rect-1", DrawPoint::new(0.5, 0.5), "orbit");
        let arrow = sample_arrow(Some(binding.clone()));

        let focus_points =
            resolve_visible_focus_points(&arrow, &[bindable], EngineContext::default(), false);

        assert_eq!(focus_points.len(), 1);
        assert_eq!(focus_points[0].edge, ArrowEndpointEdge::Start);
        assert_eq!(focus_points[0].binding, binding);
        assert_eq!(focus_points[0].point, DrawPoint::new(70.0, 70.0));
    }

    #[test]
    fn visible_focus_points_hide_anchors_that_overlap_endpoint() {
        let bindable = sample_bindable("rect-1", 10.0, 10.0, 100.0, 100.0);
        let binding = FixedPointBinding::new("rect-1", DrawPoint::new(0.0, 0.0), "orbit");
        let arrow = sample_arrow(Some(binding));

        let focus_points =
            resolve_visible_focus_points(&arrow, &[bindable], EngineContext::default(), false);

        assert!(focus_points.is_empty());
    }
}
