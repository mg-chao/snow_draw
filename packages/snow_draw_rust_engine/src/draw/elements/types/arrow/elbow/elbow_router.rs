#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as PipelineArrowBinding, ArrowBindingMode as PipelineArrowBindingMode,
};
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowData};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::models::element_state::ElementState as ModelElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowheadStyle;

pub use crate::draw::elements::types::arrow::elbow::elbow_heading::ElbowHeading;

use super::elbow_router_pipeline::route_elbow_arrow_internal as route_elbow_arrow_internal_pipeline;

const AXIS_EPSILON: f64 = 1e-6;
const BASE_BINDING_GAP: f64 = 5.0;
const ARROWHEAD_BINDING_GAP: f64 = 6.0;

/// Routing result in world space (with resolved endpoints).
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowRouteResult {
    pub points: Vec<DrawPoint>,
    pub start_point: DrawPoint,
    pub end_point: DrawPoint,
}

/// Local + world points for an element-routed elbow arrow.
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowRoutedPoints {
    pub local_points: Vec<DrawPoint>,
    pub world_points: Vec<DrawPoint>,
}

/// Minimal element contract required by elbow routing.
pub trait ElbowRouteElement {
    fn rect(&self) -> DrawRect;
    fn rotation(&self) -> f64;

    fn model_element(&self) -> Option<&ModelElementState> {
        None
    }
}

impl ElbowRouteElement for crate::draw::models::element_state::ElementState {
    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn rotation(&self) -> f64 {
        self.rotation
    }

    fn model_element(&self) -> Option<&ModelElementState> {
        Some(self)
    }
}

/// Routes an elbow arrow in world space.
///
/// The returned points are orthogonal and include bound-endpoint resolution.
#[allow(clippy::too_many_arguments)]
pub fn route_elbow_arrow<E>(
    start: DrawPoint,
    end: DrawPoint,
    elements_by_id: &HashMap<String, E>,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
) -> ElbowRouteResult
where
    E: ElbowRouteElement,
{
    let fallback_start_binding = start_binding;
    let fallback_end_binding = end_binding;
    let pipeline_elements_by_id = elements_by_id
        .iter()
        .filter_map(|(id, element)| element.model_element().cloned().map(|value| (id.clone(), value)))
        .collect::<HashMap<_, _>>();
    let start_binding = start_binding.map(to_pipeline_binding);
    let end_binding = end_binding.map(to_pipeline_binding);

    if !pipeline_elements_by_id.is_empty() || start_binding.is_none() || end_binding.is_none() {
        return route_elbow_arrow_internal_pipeline(
            start,
            end,
            &pipeline_elements_by_id,
            start_arrowhead,
            end_arrowhead,
            start_binding.as_ref(),
            end_binding.as_ref(),
        );
    }

    route_elbow_arrow_fallback(
        start,
        end,
        elements_by_id,
        fallback_start_binding,
        fallback_end_binding,
        start_arrowhead,
        end_arrowhead,
    )
}

/// Routes an elbow arrow for an element and returns both local + world points.
pub fn route_elbow_arrow_for_element<E>(
    element: &E,
    data: &ArrowData,
    elements_by_id: &HashMap<String, E>,
    start_override: Option<DrawPoint>,
    end_override: Option<DrawPoint>,
) -> ElbowRoutedPoints
where
    E: ElbowRouteElement,
{
    let resolved_points = ArrowGeometry::resolve_world_points(element.rect(), &data.points);
    let start_point = start_override
        .or_else(|| resolved_points.first().copied())
        .unwrap_or(DrawPoint::ZERO);
    let end_point = end_override
        .or_else(|| resolved_points.last().copied())
        .unwrap_or(start_point);

    route_elbow_arrow_for_element_points(
        element,
        start_point,
        end_point,
        elements_by_id,
        data.start_binding.as_ref(),
        data.end_binding.as_ref(),
        data.start_arrowhead,
        data.end_arrowhead,
    )
}

/// Routes an elbow arrow for explicit local endpoints on an element.
#[allow(clippy::too_many_arguments)]
pub fn route_elbow_arrow_for_element_points<E>(
    element: &E,
    start_local: DrawPoint,
    end_local: DrawPoint,
    elements_by_id: &HashMap<String, E>,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
) -> ElbowRoutedPoints
where
    E: ElbowRouteElement,
{
    let space = ElementSpace::new(element.rotation(), element.rect().center());
    let world_start = space.to_world(start_local);
    let world_end = space.to_world(end_local);

    let routed = route_elbow_arrow(
        world_start,
        world_end,
        elements_by_id,
        start_binding,
        end_binding,
        start_arrowhead,
        end_arrowhead,
    );

    let local_points = routed
        .points
        .iter()
        .copied()
        .map(|point| space.from_world(point))
        .collect();

    ElbowRoutedPoints {
        local_points,
        world_points: routed.points,
    }
}

#[allow(clippy::too_many_arguments)]
fn route_elbow_arrow_fallback<E>(
    start: DrawPoint,
    end: DrawPoint,
    elements_by_id: &HashMap<String, E>,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
) -> ElbowRouteResult
where
    E: ElbowRouteElement,
{
    let endpoints = resolve_route_endpoints(
        start,
        end,
        elements_by_id,
        start_binding,
        end_binding,
        start_arrowhead,
        end_arrowhead,
    );

    let raw_points = fallback_path(
        endpoints.start.point,
        endpoints.end.point,
        endpoints.start.heading,
        endpoints.end.heading,
        endpoints.start.is_bound(),
        endpoints.end.is_bound(),
    );

    build_route_result(endpoints.start.point, endpoints.end.point, raw_points)
}

fn to_pipeline_binding(binding: &ArrowBinding) -> PipelineArrowBinding {
    PipelineArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Inside => {
                PipelineArrowBindingMode::Inside
            }
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Orbit => {
                PipelineArrowBindingMode::Orbit
            }
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Skip => {
                PipelineArrowBindingMode::Skip
            }
        },
    )
}

fn build_route_result(
    start_point: DrawPoint,
    end_point: DrawPoint,
    points: Vec<DrawPoint>,
) -> ElbowRouteResult {
    ElbowRouteResult {
        points: merge_consecutive_same_heading(points),
        start_point,
        end_point,
    }
}

fn resolve_route_endpoints<E>(
    start_point: DrawPoint,
    end_point: DrawPoint,
    elements_by_id: &HashMap<String, E>,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
) -> ResolvedEndpoints
where
    E: ElbowRouteElement,
{
    let start_fallback =
        heading_for_vector(end_point.x - start_point.x, end_point.y - start_point.y);
    let end_fallback = heading_for_vector(start_point.x - end_point.x, start_point.y - end_point.y);

    let start = resolve_endpoint(
        start_point,
        start_binding,
        elements_by_id,
        start_arrowhead != ArrowheadStyle::None,
        start_fallback,
    );
    let end = resolve_endpoint(
        end_point,
        end_binding,
        elements_by_id,
        end_arrowhead != ArrowheadStyle::None,
        end_fallback,
    );

    ResolvedEndpoints { start, end }
}

fn resolve_endpoint<E>(
    point: DrawPoint,
    binding: Option<&ArrowBinding>,
    elements_by_id: &HashMap<String, E>,
    has_arrowhead: bool,
    fallback_heading: ElbowHeading,
) -> ResolvedEndpoint
where
    E: ElbowRouteElement,
{
    let Some(binding) = binding else {
        return ResolvedEndpoint::unbound(point, fallback_heading, has_arrowhead);
    };
    let Some(element) = elements_by_id.get(&binding.element_id) else {
        return ResolvedEndpoint::unbound(point, fallback_heading, has_arrowhead);
    };

    let rect = element.rect();
    let space = ElementSpace::new(element.rotation(), rect.center());

    let local_anchor = DrawPoint::new(
        rect.min_x + rect.width() * binding.anchor.x,
        rect.min_y + rect.height() * binding.anchor.y,
    );
    let anchor_world = space.to_world(local_anchor);

    let bounds = compute_element_world_aabb(rect, element.rotation());
    let heading = heading_for_point_on_bounds(bounds, anchor_world);
    let gap = if has_arrowhead {
        ARROWHEAD_BINDING_GAP
    } else {
        BASE_BINDING_GAP
    };
    let resolved = offset_point(anchor_world, heading, gap);

    ResolvedEndpoint {
        point: resolved,
        heading,
        has_arrowhead,
        element_bounds: Some(bounds),
        anchor: Some(anchor_world),
    }
}

#[allow(clippy::too_many_arguments)]
fn fallback_path(
    start: DrawPoint,
    end: DrawPoint,
    start_heading: ElbowHeading,
    end_heading: ElbowHeading,
    start_constrained: bool,
    end_constrained: bool,
) -> Vec<DrawPoint> {
    if axis_aligned(start, end) {
        return vec![start, end];
    }

    let horizontal_first_corner = DrawPoint::new(end.x, start.y);
    let vertical_first_corner = DrawPoint::new(start.x, end.y);

    let horizontal_score = candidate_score(
        start,
        end,
        horizontal_first_corner,
        start_heading,
        end_heading,
        start_constrained,
        end_constrained,
    );
    let vertical_score = candidate_score(
        start,
        end,
        vertical_first_corner,
        start_heading,
        end_heading,
        start_constrained,
        end_constrained,
    );

    if horizontal_score < vertical_score {
        vec![start, horizontal_first_corner, end]
    } else if vertical_score < horizontal_score {
        vec![start, vertical_first_corner, end]
    } else if (end.x - start.x).abs() >= (end.y - start.y).abs() {
        vec![start, horizontal_first_corner, end]
    } else {
        vec![start, vertical_first_corner, end]
    }
}

#[allow(clippy::too_many_arguments)]
fn candidate_score(
    start: DrawPoint,
    end: DrawPoint,
    corner: DrawPoint,
    start_heading: ElbowHeading,
    end_heading: ElbowHeading,
    start_constrained: bool,
    end_constrained: bool,
) -> i32 {
    let mut score = 0;

    if start_constrained {
        let outbound = heading_between(start, corner);
        if outbound != Some(start_heading) {
            score += 4;
        }
    }

    if end_constrained {
        let inbound_from_end = heading_between(end, corner);
        if inbound_from_end != Some(end_heading) {
            score += 4;
        }
    }

    if !axis_aligned(start, corner) {
        score += 1;
    }
    if !axis_aligned(corner, end) {
        score += 1;
    }

    score
}

fn merge_consecutive_same_heading(points: Vec<DrawPoint>) -> Vec<DrawPoint> {
    let deduped = dedupe_consecutive_points(points);
    if deduped.len() < 3 {
        return deduped;
    }

    let mut merged = Vec::with_capacity(deduped.len());
    merged.push(deduped[0]);

    for index in 1..(deduped.len() - 1) {
        let current = deduped[index];
        let previous = merged[merged.len() - 1];
        let next = deduped[index + 1];

        let incoming = heading_between(previous, current);
        let outgoing = heading_between(current, next);
        if incoming.is_some() && incoming == outgoing {
            continue;
        }

        merged.push(current);
    }

    merged.push(deduped[deduped.len() - 1]);
    dedupe_consecutive_points(merged)
}

fn dedupe_consecutive_points(points: Vec<DrawPoint>) -> Vec<DrawPoint> {
    if points.is_empty() {
        return points;
    }

    let mut result = Vec::with_capacity(points.len());
    result.push(points[0]);

    for point in points.into_iter().skip(1) {
        if point != result[result.len() - 1] {
            result.push(point);
        }
    }

    if result.len() == 1 {
        result.push(result[0]);
    }

    result
}

fn heading_between(a: DrawPoint, b: DrawPoint) -> Option<ElbowHeading> {
    if approx_eq(a.x, b.x) {
        if approx_eq(a.y, b.y) {
            return None;
        }
        return if b.y > a.y {
            Some(ElbowHeading::Down)
        } else {
            Some(ElbowHeading::Up)
        };
    }

    if approx_eq(a.y, b.y) {
        return if b.x > a.x {
            Some(ElbowHeading::Right)
        } else {
            Some(ElbowHeading::Left)
        };
    }

    None
}

fn heading_for_vector(dx: f64, dy: f64) -> ElbowHeading {
    if dx.abs() >= dy.abs() {
        if dx >= 0.0 {
            ElbowHeading::Right
        } else {
            ElbowHeading::Left
        }
    } else if dy >= 0.0 {
        ElbowHeading::Down
    } else {
        ElbowHeading::Up
    }
}

fn heading_for_point_on_bounds(bounds: DrawRect, point: DrawPoint) -> ElbowHeading {
    let left = (point.x - bounds.min_x).abs();
    let right = (bounds.max_x - point.x).abs();
    let top = (point.y - bounds.min_y).abs();
    let bottom = (bounds.max_y - point.y).abs();

    let min = left.min(right).min(top.min(bottom));
    if approx_eq(min, left) {
        ElbowHeading::Left
    } else if approx_eq(min, right) {
        ElbowHeading::Right
    } else if approx_eq(min, top) {
        ElbowHeading::Up
    } else {
        ElbowHeading::Down
    }
}

fn offset_point(point: DrawPoint, heading: ElbowHeading, distance: f64) -> DrawPoint {
    DrawPoint::new(
        point.x + heading.dx() as f64 * distance,
        point.y + heading.dy() as f64 * distance,
    )
}

fn axis_aligned(a: DrawPoint, b: DrawPoint) -> bool {
    approx_eq(a.x, b.x) || approx_eq(a.y, b.y)
}

fn approx_eq(a: f64, b: f64) -> bool {
    (a - b).abs() <= AXIS_EPSILON
}

fn compute_element_world_aabb(rect: DrawRect, rotation: f64) -> DrawRect {
    if approx_eq(rotation, 0.0) {
        return rect;
    }

    let center = rect.center();
    let half_width = rect.width().abs() * 0.5;
    let half_height = rect.height().abs() * 0.5;
    let cos_theta = rotation.cos().abs();
    let sin_theta = rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;

    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

#[derive(Clone, Copy, Debug)]
struct ResolvedEndpoint {
    point: DrawPoint,
    heading: ElbowHeading,
    has_arrowhead: bool,
    element_bounds: Option<DrawRect>,
    anchor: Option<DrawPoint>,
}

impl ResolvedEndpoint {
    fn unbound(point: DrawPoint, heading: ElbowHeading, has_arrowhead: bool) -> Self {
        Self {
            point,
            heading,
            has_arrowhead,
            element_bounds: None,
            anchor: None,
        }
    }

    fn is_bound(self) -> bool {
        self.element_bounds.is_some()
    }
}

#[derive(Clone, Copy, Debug)]
struct ResolvedEndpoints {
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
}
