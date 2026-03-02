#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingUtils, ElementState,
};
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::elements::types::arrow::elbow::elbow_heading::ElbowHeading;
use crate::draw::elements::types::arrow::elbow::elbow_router::ElbowRouteResult;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowheadStyle;

/// Internal routing flow for elbow arrows.
#[allow(clippy::too_many_arguments)]
pub(crate) fn route_elbow_arrow_internal(
    start: DrawPoint,
    end: DrawPoint,
    elements_by_id: &HashMap<String, ElementState>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
) -> ElbowRouteResult {
    let endpoints = resolve_route_endpoints(
        start,
        end,
        elements_by_id,
        start_arrowhead,
        end_arrowhead,
        start_binding,
        end_binding,
    );
    let start_endpoint = endpoints.start;
    let end_endpoint = endpoints.end;

    if !start_endpoint.is_bound() && !end_endpoint.is_bound() {
        return build_route_result(
            start_endpoint.point,
            end_endpoint.point,
            fallback_path(
                start_endpoint.point,
                end_endpoint.point,
                start_endpoint.heading,
                end_endpoint.heading,
                start_endpoint.is_bound(),
                end_endpoint.is_bound(),
            ),
        );
    }

    let layout = plan_obstacle_layout(start_endpoint, end_endpoint);
    let direct = direct_path_if_clear(
        start_endpoint.point,
        end_endpoint.point,
        &layout.obstacles,
        start_endpoint.heading,
        end_endpoint.heading,
        start_endpoint.is_bound(),
        end_endpoint.is_bound(),
    );
    if let Some(points) = direct {
        return build_route_result(start_endpoint.point, end_endpoint.point, points);
    }

    let routed = route_via_grid_or_fallback(start_endpoint, end_endpoint, &layout);
    let finalized = finalize_routed_path(routed, start_endpoint.heading, &layout.obstacles);
    let harmonized = harmonize_bound_spacing(finalized, start_endpoint, end_endpoint);

    build_route_result(start_endpoint.point, end_endpoint.point, harmonized)
}

fn route_via_grid_or_fallback(
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
    layout: &ElbowObstacleLayout,
) -> Vec<DrawPoint> {
    let grid = build_grid(
        &layout.obstacles,
        layout.start_exit,
        layout.end_exit,
        layout.common_bounds,
    );

    let path = try_route_grid_path(
        &grid,
        start,
        end,
        layout.start_exit,
        layout.end_exit,
        &layout.obstacles,
    );

    let Some(path) = path else {
        return fallback_path(
            start.point,
            end.point,
            start.heading,
            end.heading,
            start.is_bound(),
            end.is_bound(),
        );
    };

    let mut points = Vec::with_capacity(path.len() + 2);
    if !points_close(layout.start_exit, start.point) {
        points.push(start.point);
    }
    points.extend(path.into_iter().map(|node| node.pos));
    if !points_close(layout.end_exit, end.point) {
        points.push(end.point);
    }
    points
}

fn build_route_result(
    start_point: DrawPoint,
    end_point: DrawPoint,
    points: Vec<DrawPoint>,
) -> ElbowRouteResult {
    ElbowRouteResult {
        points: merge_consecutive_same_heading(&points),
        start_point,
        end_point,
    }
}

/// Fully resolved endpoint for elbow routing.
#[derive(Clone, Copy, Debug)]
pub(crate) struct ResolvedEndpoint {
    pub point: DrawPoint,
    pub heading: ElbowHeading,
    pub has_arrowhead: bool,
    pub element_bounds: Option<DrawRect>,
    pub anchor: Option<DrawPoint>,
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

    pub(crate) fn is_bound(self) -> bool {
        self.element_bounds.is_some()
    }

    pub(crate) fn anchor_or_point(self) -> DrawPoint {
        self.anchor.unwrap_or(self.point)
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct ResolvedEndpoints {
    pub start: ResolvedEndpoint,
    pub end: ResolvedEndpoint,
}

fn resolve_endpoint(
    point: DrawPoint,
    binding: Option<&ArrowBinding>,
    elements_by_id: &HashMap<String, ElementState>,
    has_arrowhead: bool,
    fallback_heading: ElbowHeading,
) -> ResolvedEndpoint {
    let Some(binding) = binding else {
        return ResolvedEndpoint::unbound(point, fallback_heading, has_arrowhead);
    };
    let Some(element) = elements_by_id.get(binding.element_id.as_str()) else {
        return ResolvedEndpoint::unbound(point, fallback_heading, has_arrowhead);
    };

    let resolved = ArrowBindingUtils::resolve_elbow_bound_point(binding, element, has_arrowhead)
        .unwrap_or(point);
    let anchor = ArrowBindingUtils::resolve_elbow_anchor_point(binding, element);
    let bounds = compute_element_world_aabb(element.rect, element.rotation);
    let heading = heading_for_point_on_bounds(bounds, anchor.unwrap_or(resolved));

    ResolvedEndpoint {
        point: resolved,
        heading,
        has_arrowhead,
        element_bounds: Some(bounds),
        anchor,
    }
}

#[allow(clippy::too_many_arguments)]
fn resolve_route_endpoints(
    start_point: DrawPoint,
    end_point: DrawPoint,
    elements_by_id: &HashMap<String, ElementState>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
) -> ResolvedEndpoints {
    let start = resolve_endpoint(
        start_point,
        start_binding,
        elements_by_id,
        start_arrowhead != ArrowheadStyle::None,
        heading_for_vector(end_point.x - start_point.x, end_point.y - start_point.y),
    );
    let end = resolve_endpoint(
        end_point,
        end_binding,
        elements_by_id,
        end_arrowhead != ArrowheadStyle::None,
        heading_for_vector(start_point.x - end_point.x, start_point.y - end_point.y),
    );

    ResolvedEndpoints { start, end }
}

#[derive(Clone, Debug)]
struct ElbowObstacleLayout {
    common_bounds: DrawRect,
    start_exit: DrawPoint,
    end_exit: DrawPoint,
    obstacles: Vec<DrawRect>,
}

fn plan_obstacle_layout(start: ResolvedEndpoint, end: ResolvedEndpoint) -> ElbowObstacleLayout {
    let start_obstacle = clamp_bounds(element_bounds_for_elbow(start));
    let end_obstacle = clamp_bounds(element_bounds_for_elbow(end));

    let common_bounds = clamp_bounds(inflate_bounds(
        union_bounds(&[start_obstacle, end_obstacle]),
        ElbowConstants::BASE_PADDING,
    ));

    ElbowObstacleLayout {
        common_bounds,
        start_exit: exit_position(start_obstacle, start.heading, start.point),
        end_exit: exit_position(end_obstacle, end.heading, end.point),
        obstacles: vec![start_obstacle, end_obstacle],
    }
}

fn element_bounds_for_elbow(endpoint: ResolvedEndpoint) -> DrawRect {
    let Some(element_bounds) = endpoint.element_bounds else {
        return point_bounds(endpoint.point, ElbowConstants::EXIT_POINT_PADDING);
    };

    let side = ElbowConstants::ELEMENT_SIDE_PADDING;
    let head = if endpoint.has_arrowhead {
        ElbowConstants::BASE_PADDING * 0.5
    } else {
        ElbowConstants::BASE_PADDING
    };

    match endpoint.heading {
        ElbowHeading::Up => DrawRect::new(
            element_bounds.min_x - side,
            element_bounds.min_y - head,
            element_bounds.max_x + side,
            element_bounds.max_y + side,
        ),
        ElbowHeading::Right => DrawRect::new(
            element_bounds.min_x - side,
            element_bounds.min_y - side,
            element_bounds.max_x + head,
            element_bounds.max_y + side,
        ),
        ElbowHeading::Down => DrawRect::new(
            element_bounds.min_x - side,
            element_bounds.min_y - side,
            element_bounds.max_x + side,
            element_bounds.max_y + head,
        ),
        ElbowHeading::Left => DrawRect::new(
            element_bounds.min_x - head,
            element_bounds.min_y - side,
            element_bounds.max_x + side,
            element_bounds.max_y + side,
        ),
    }
}

fn point_bounds(point: DrawPoint, padding: f64) -> DrawRect {
    DrawRect::new(
        point.x - padding,
        point.y - padding,
        point.x + padding,
        point.y + padding,
    )
}

fn inflate_bounds(rect: DrawRect, padding: f64) -> DrawRect {
    DrawRect::new(
        rect.min_x - padding,
        rect.min_y - padding,
        rect.max_x + padding,
        rect.max_y + padding,
    )
}

fn union_bounds(bounds: &[DrawRect]) -> DrawRect {
    let first = bounds[0];
    let mut min_x = first.min_x;
    let mut min_y = first.min_y;
    let mut max_x = first.max_x;
    let mut max_y = first.max_y;

    for rect in bounds.iter().copied().skip(1) {
        min_x = min_x.min(rect.min_x);
        min_y = min_y.min(rect.min_y);
        max_x = max_x.max(rect.max_x);
        max_y = max_y.max(rect.max_y);
    }

    DrawRect::new(min_x, min_y, max_x, max_y)
}

fn clamp_bounds(rect: DrawRect) -> DrawRect {
    let max = ElbowConstants::MAX_POSITION;
    DrawRect::new(
        clamp(rect.min_x, -max, max),
        clamp(rect.min_y, -max, max),
        clamp(rect.max_x, -max, max),
        clamp(rect.max_y, -max, max),
    )
}

fn clamp_point(point: DrawPoint) -> DrawPoint {
    let max = ElbowConstants::MAX_POSITION;
    DrawPoint::new(clamp(point.x, -max, max), clamp(point.y, -max, max))
}

fn exit_position(bounds: DrawRect, heading: ElbowHeading, point: DrawPoint) -> DrawPoint {
    match heading {
        ElbowHeading::Up => DrawPoint::new(point.x, bounds.min_y),
        ElbowHeading::Right => DrawPoint::new(bounds.max_x, point.y),
        ElbowHeading::Down => DrawPoint::new(point.x, bounds.max_y),
        ElbowHeading::Left => DrawPoint::new(bounds.min_x, point.y),
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct ElbowGrid;

#[derive(Clone, Copy, Debug)]
struct ElbowGridNode {
    pos: DrawPoint,
}

fn build_grid(
    _obstacles: &[DrawRect],
    _start: DrawPoint,
    _end: DrawPoint,
    _bounds: DrawRect,
) -> ElbowGrid {
    ElbowGrid
}

#[allow(clippy::too_many_arguments)]
fn try_route_grid_path(
    _grid: &ElbowGrid,
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
    start_exit: DrawPoint,
    end_exit: DrawPoint,
    obstacles: &[DrawRect],
) -> Option<Vec<ElbowGridNode>> {
    let path = direct_path_if_clear(
        start_exit,
        end_exit,
        obstacles,
        start.heading,
        end.heading,
        start.is_bound(),
        end.is_bound(),
    )?;

    Some(path.into_iter().map(|pos| ElbowGridNode { pos }).collect())
}

#[allow(clippy::too_many_arguments)]
fn direct_path_if_clear(
    start: DrawPoint,
    end: DrawPoint,
    obstacles: &[DrawRect],
    start_heading: ElbowHeading,
    end_heading: ElbowHeading,
    start_constrained: bool,
    end_constrained: bool,
) -> Option<Vec<DrawPoint>> {
    let aligned_x = (start.x - end.x).abs() <= ElbowConstants::DEDUP_THRESHOLD;
    let aligned_y = (start.y - end.y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
    if aligned_x == aligned_y {
        return None;
    }

    if start_heading.is_horizontal() != aligned_y || end_heading.is_horizontal() != aligned_y {
        return None;
    }

    let segment_heading = heading_between(start, end)?;
    if start_constrained && segment_heading != start_heading {
        return None;
    }
    if end_constrained && segment_heading != end_heading.opposite() {
        return None;
    }
    if segment_intersects_any_bounds(start, end, obstacles) {
        return None;
    }

    Some(vec![start, end])
}

fn segment_intersects_any_bounds(start: DrawPoint, end: DrawPoint, obstacles: &[DrawRect]) -> bool {
    obstacles
        .iter()
        .copied()
        .any(|obstacle| segment_intersects_bounds(start, end, obstacle))
}

fn segment_intersects_bounds(start: DrawPoint, end: DrawPoint, bounds: DrawRect) -> bool {
    let inner_bounds = DrawRect::new(
        bounds.min_x + ElbowConstants::INTERSECTION_EPSILON,
        bounds.min_y + ElbowConstants::INTERSECTION_EPSILON,
        bounds.max_x - ElbowConstants::INTERSECTION_EPSILON,
        bounds.max_y - ElbowConstants::INTERSECTION_EPSILON,
    );
    if inner_bounds.min_x >= inner_bounds.max_x || inner_bounds.min_y >= inner_bounds.max_y {
        return false;
    }

    if (start.x - end.x).abs() <= ElbowConstants::DEDUP_THRESHOLD {
        let x = (start.x + end.x) / 2.0;
        if x < inner_bounds.min_x || x > inner_bounds.max_x {
            return false;
        }

        return overlap_length(
            start.y.min(end.y),
            start.y.max(end.y),
            inner_bounds.min_y,
            inner_bounds.max_y,
        ) > ElbowConstants::INTERSECTION_EPSILON;
    }

    if (start.y - end.y).abs() > ElbowConstants::DEDUP_THRESHOLD {
        return false;
    }

    let y = (start.y + end.y) / 2.0;
    if y < inner_bounds.min_y || y > inner_bounds.max_y {
        return false;
    }

    overlap_length(
        start.x.min(end.x),
        start.x.max(end.x),
        inner_bounds.min_x,
        inner_bounds.max_x,
    ) > ElbowConstants::INTERSECTION_EPSILON
}

fn overlap_length(min_a: f64, max_a: f64, min_b: f64, max_b: f64) -> f64 {
    max_a.min(max_b) - min_a.max(min_b)
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

fn finalize_routed_path(
    points: Vec<DrawPoint>,
    start_heading: ElbowHeading,
    obstacles: &[DrawRect],
) -> Vec<DrawPoint> {
    let orthogonalized = ensure_orthogonal_path(&points, start_heading);
    let backtrack_collapsed = collapse_route_backtracks(&orthogonalized, obstacles);
    let cleaned = corner_points(&remove_short_segments(
        &backtrack_collapsed,
        ElbowConstants::DEDUP_THRESHOLD,
    ));

    cleaned.into_iter().map(clamp_point).collect()
}

fn harmonize_bound_spacing(
    points: Vec<DrawPoint>,
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
) -> Vec<DrawPoint> {
    if !start.is_bound() || !end.is_bound() {
        return points;
    }

    // Full spacing harmonization depends on elbow_spacing and obstacle-path
    // modules that are still being translated. Keep routed points stable here.
    points
}

fn ensure_orthogonal_path(points: &[DrawPoint], start_heading: ElbowHeading) -> Vec<DrawPoint> {
    if points.len() < 2 {
        return points.to_vec();
    }

    let mut result = Vec::with_capacity(points.len() + 2);
    result.push(points[0]);

    for next in points.iter().copied().skip(1) {
        let prev = result[result.len() - 1];
        let dx = (next.x - prev.x).abs();
        let dy = (next.y - prev.y).abs();
        if dx <= ElbowConstants::DEDUP_THRESHOLD || dy <= ElbowConstants::DEDUP_THRESHOLD {
            if !points_close(next, prev) {
                result.push(next);
            }
            continue;
        }

        let prefer_horizontal = if result.len() > 1 {
            segment_is_horizontal(result[result.len() - 2], prev)
        } else {
            start_heading.is_horizontal()
        };
        let mid = if prefer_horizontal {
            DrawPoint::new(next.x, prev.y)
        } else {
            DrawPoint::new(prev.x, next.y)
        };

        if !points_close(mid, prev) {
            result.push(mid);
        }
        if !points_close(next, mid) {
            result.push(next);
        }
    }

    result
}

fn collapse_route_backtracks(points: &[DrawPoint], obstacles: &[DrawRect]) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points.to_vec();
    }

    let mut updated = points.to_vec();
    let mut changed = true;
    while changed {
        changed = false;
        let len = updated.len();

        'scan: for i in 1..len.saturating_sub(2) {
            for j in (i + 2)..(len - 1) {
                let a = updated[i];
                let d = updated[j];
                let aligned_x = (a.x - d.x).abs() <= ElbowConstants::DEDUP_THRESHOLD;
                let aligned_y = (a.y - d.y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
                if !aligned_x && !aligned_y {
                    continue;
                }
                if segment_intersects_any_bounds(a, d, obstacles) {
                    continue;
                }

                let mut deviates = false;
                for point in updated.iter().take(j).skip(i + 1).copied() {
                    let delta = if aligned_x {
                        (point.x - a.x).abs()
                    } else {
                        (point.y - a.y).abs()
                    };
                    if delta > ElbowConstants::DEDUP_THRESHOLD {
                        deviates = true;
                        break;
                    }
                }

                if !deviates {
                    continue;
                }

                let mut collapsed = Vec::with_capacity(updated.len());
                collapsed.extend_from_slice(&updated[..=i]);
                collapsed.push(d);
                if j + 1 < updated.len() {
                    collapsed.extend_from_slice(&updated[(j + 1)..]);
                }
                updated = collapsed;
                changed = true;
                break 'scan;
            }
        }
    }

    updated
}

fn remove_short_segments(points: &[DrawPoint], min_length: f64) -> Vec<DrawPoint> {
    if points.len() < 4 {
        return points.to_vec();
    }

    let mut result = Vec::with_capacity(points.len());
    result.push(points[0]);

    for index in 1..(points.len() - 1) {
        if manhattan_distance(points[index - 1], points[index]) > min_length {
            result.push(points[index]);
        }
    }

    result.push(points[points.len() - 1]);
    result
}

fn corner_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() <= 2 {
        return points.to_vec();
    }

    let mut prev_horizontal = segment_is_horizontal(points[0], points[1]);
    let mut result = Vec::with_capacity(points.len());
    result.push(points[0]);

    for index in 1..(points.len() - 1) {
        let next_horizontal = segment_is_horizontal(points[index], points[index + 1]);
        if prev_horizontal != next_horizontal {
            result.push(points[index]);
        }
        prev_horizontal = next_horizontal;
    }

    result.push(points[points.len() - 1]);
    result
}

fn segment_is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
    (a.y - b.y).abs() <= (a.x - b.x).abs()
}

fn merge_consecutive_same_heading(points: &[DrawPoint]) -> Vec<DrawPoint> {
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
    dedupe_consecutive_points(&merged)
}

fn dedupe_consecutive_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.is_empty() {
        return Vec::new();
    }

    let mut result = Vec::with_capacity(points.len());
    result.push(points[0]);

    for point in points.iter().copied().skip(1) {
        if !points_close(point, result[result.len() - 1]) {
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

fn axis_aligned(a: DrawPoint, b: DrawPoint) -> bool {
    approx_eq(a.x, b.x) || approx_eq(a.y, b.y)
}

fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
    (a.x - b.x).abs() + (a.y - b.y).abs()
}

fn points_close(a: DrawPoint, b: DrawPoint) -> bool {
    (a.x - b.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        && (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
}

fn approx_eq(a: f64, b: f64) -> bool {
    (a - b).abs() <= ElbowConstants::INTERSECTION_EPSILON
}

fn clamp(value: f64, min: f64, max: f64) -> f64 {
    value.max(min).min(max)
}

fn compute_element_world_aabb(rect: DrawRect, rotation: f64) -> DrawRect {
    if approx_eq(rotation, 0.0) {
        return rect;
    }

    let center = rect.center();
    let half_width = rect.width().abs() / 2.0;
    let half_height = rect.height().abs() / 2.0;
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
