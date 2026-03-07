#![allow(dead_code)]

use std::cmp::Ordering;
use std::collections::HashMap;

use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::binary_heap::BinaryHeap;

use super::elbow_constants::ElbowConstants;
use super::elbow_geometry::ElbowGeometry;
use super::elbow_heading::ElbowHeading;

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
    pub(crate) const fn is_bound(self) -> bool {
        self.element_bounds.is_some()
    }

    pub(crate) fn anchor_or_point(self) -> DrawPoint {
        self.anchor.unwrap_or(self.point)
    }
}

/// Returns a direct 2-point route when alignment + constraints allow it.
pub(crate) fn direct_path_if_clear(
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

    let segment_heading = heading_for_segment(start, end);
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

pub(crate) fn segment_intersects_bounds(
    start: DrawPoint,
    end: DrawPoint,
    bounds: DrawRect,
) -> bool {
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

pub(crate) fn fallback_path(
    start: DrawPoint,
    end: DrawPoint,
    start_heading: ElbowHeading,
    end_heading: Option<ElbowHeading>,
    start_constrained: bool,
    end_constrained: bool,
) -> Vec<DrawPoint> {
    let resolved_end_heading = end_heading.unwrap_or(start_heading.opposite());

    if start_constrained || end_constrained {
        let mut candidates = vec![
            vec![start, end],
            ElbowGeometry::direct_elbow_path(start, end, true),
            ElbowGeometry::direct_elbow_path(start, end, false),
        ];

        for horizontal in [true, false] {
            if let Some(mid) = resolve_fallback_mid(
                start,
                end,
                start_heading,
                resolved_end_heading,
                start_constrained,
                end_constrained,
                horizontal,
            ) {
                candidates.push(build_elbow_through_mid(start, end, horizontal, mid));
            }
        }

        let mut best: Option<Vec<DrawPoint>> = None;
        let mut best_length = f64::INFINITY;
        for candidate in candidates {
            let short_removed = ElbowGeometry::remove_short_segments(&candidate);
            let cleaned = ElbowGeometry::corner_points(&short_removed);
            if cleaned.len() < 2 || ElbowGeometry::has_diagonal_segments(&cleaned) {
                continue;
            }

            if start_constrained && heading_for_segment(cleaned[0], cleaned[1]) != start_heading {
                continue;
            }

            if end_constrained
                && heading_for_segment(cleaned[cleaned.len() - 2], cleaned[cleaned.len() - 1])
                    != resolved_end_heading.opposite()
            {
                continue;
            }

            let length = ElbowGeometry::path_length(&cleaned);
            if length < best_length {
                best_length = length;
                best = Some(cleaned);
            }
        }

        if let Some(path) = best {
            return path;
        }
    }

    if ElbowGeometry::manhattan_distance(start, end) < ElbowConstants::MIN_ARROW_LENGTH {
        let mid_y = (start.y + end.y) / 2.0;
        return build_elbow_through_mid(start, end, false, mid_y);
    }

    if (start.x - end.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        || (start.y - end.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
    {
        return vec![start, end];
    }

    let horizontal = start_heading.is_horizontal();
    let mid = if horizontal {
        (start.x + end.x) / 2.0
    } else {
        (start.y + end.y) / 2.0
    };
    build_elbow_through_mid(start, end, horizontal, mid)
}

fn build_elbow_through_mid(
    start: DrawPoint,
    end: DrawPoint,
    horizontal: bool,
    mid: f64,
) -> Vec<DrawPoint> {
    if horizontal {
        return vec![
            start,
            DrawPoint::new(mid, start.y),
            DrawPoint::new(mid, end.y),
            end,
        ];
    }

    vec![
        start,
        DrawPoint::new(start.x, mid),
        DrawPoint::new(end.x, mid),
        end,
    ]
}

fn resolve_fallback_mid(
    start: DrawPoint,
    end: DrawPoint,
    start_heading: ElbowHeading,
    end_heading: ElbowHeading,
    start_constrained: bool,
    end_constrained: bool,
    horizontal: bool,
) -> Option<f64> {
    let padding = ElbowConstants::DIRECTION_FIX_PADDING;
    let mut min = f64::NEG_INFINITY;
    let mut max = f64::INFINITY;

    let entries = [
        (
            start_constrained,
            start_heading,
            if horizontal { start.x } else { start.y },
        ),
        (
            end_constrained,
            end_heading,
            if horizontal { end.x } else { end.y },
        ),
    ];
    for (constrained, heading, value) in entries {
        if !constrained || heading.is_horizontal() != horizontal {
            continue;
        }
        let positive = if horizontal {
            heading == ElbowHeading::Right
        } else {
            heading == ElbowHeading::Down
        };
        if positive {
            min = min.max(value + padding);
        } else {
            max = max.min(value - padding);
        }
    }

    if min.is_finite() && max.is_finite() && min > max {
        return None;
    }

    let candidate = if horizontal {
        (start.x + end.x) / 2.0
    } else {
        (start.y + end.y) / 2.0
    };

    if min.is_finite() && candidate < min {
        return Some(min);
    }
    if max.is_finite() && candidate > max {
        return Some(max);
    }

    Some(candidate)
}

/// Final cleanup for routed paths: orthogonalize, prune, and clamp.
pub(crate) fn finalize_routed_path(
    points: &[DrawPoint],
    start_heading: ElbowHeading,
    obstacles: &[DrawRect],
) -> Vec<DrawPoint> {
    let orthogonalized = ensure_orthogonal_path(points, start_heading);
    let backtrack_collapsed = collapse_route_backtracks(&orthogonalized, obstacles);
    let short_removed = ElbowGeometry::remove_short_segments(&backtrack_collapsed);
    let cleaned = ElbowGeometry::corner_points(&short_removed);
    cleaned.into_iter().map(clamp_point).collect()
}

pub(crate) fn harmonize_bound_spacing(
    points: &[DrawPoint],
    start: &ResolvedEndpoint,
    end: &ResolvedEndpoint,
) -> Vec<DrawPoint> {
    let Some(start_bounds) = start.element_bounds else {
        return points.to_vec();
    };
    let Some(end_bounds) = end.element_bounds else {
        return points.to_vec();
    };
    if !start.is_bound() || !end.is_bound() {
        return points.to_vec();
    }

    let mut segments = Vec::new();
    for index in 0..points.len().saturating_sub(1) {
        if ElbowGeometry::manhattan_distance(points[index], points[index + 1])
            <= ElbowConstants::DEDUP_THRESHOLD
        {
            continue;
        }
        segments.push(RouteSegment {
            index,
            start: points[index],
            end: points[index + 1],
            heading: heading_for_segment(points[index], points[index + 1]),
        });
    }

    if segments.len() == 3 {
        return balance_three_segment_path(points, &segments, start, end, start_bounds, end_bounds);
    }

    if segments.len() < 4 {
        return points.to_vec();
    }

    let start_segment = segments[1];
    let end_segment = segments[segments.len() - 2];
    if start_segment.heading.is_horizontal() == start.heading.is_horizontal()
        || end_segment.heading.is_horizontal() == end.heading.is_horizontal()
    {
        return points.to_vec();
    }

    let start_spacing = segment_spacing(start_segment, start_bounds, start.heading);
    let end_spacing = segment_spacing(end_segment, end_bounds, end.heading);
    let Some(resolved_spacing) = ElbowSpacing::resolve_shared_spacing(
        start_spacing,
        end_spacing,
        start.has_arrowhead,
        end.has_arrowhead,
    ) else {
        return points.to_vec();
    };

    let mut updated = points.to_vec();
    apply_segment_spacing(
        &mut updated,
        start_segment,
        start_bounds,
        start.heading,
        resolved_spacing,
    );
    apply_segment_spacing(
        &mut updated,
        end_segment,
        end_bounds,
        end.heading,
        resolved_spacing,
    );

    updated
}

/// Balances a 3-segment path where the first and last segments share the
/// same axis by centering the middle perpendicular segment in the gap.
fn balance_three_segment_path(
    points: &[DrawPoint],
    segments: &[RouteSegment],
    start: &ResolvedEndpoint,
    end: &ResolvedEndpoint,
    start_bounds: DrawRect,
    end_bounds: DrawRect,
) -> Vec<DrawPoint> {
    let first = segments[0];
    let last = segments[segments.len() - 1];
    if first.heading.is_horizontal() != last.heading.is_horizontal() {
        return points.to_vec();
    }

    let horizontal = first.heading.is_horizontal();
    let min_spacing = ElbowSpacing::min_binding_spacing(start.has_arrowhead)
        .max(ElbowSpacing::min_binding_spacing(end.has_arrowhead));
    let forward = if horizontal {
        first.heading != ElbowHeading::Left
    } else {
        first.heading != ElbowHeading::Up
    };

    let bounds_limit = |bounds: DrawRect, for_start: bool| -> f64 {
        if horizontal {
            if forward == for_start {
                bounds.max_x + min_spacing
            } else {
                bounds.min_x - min_spacing
            }
        } else if forward == for_start {
            bounds.max_y + min_spacing
        } else {
            bounds.min_y - min_spacing
        }
    };

    let start_limit = bounds_limit(start_bounds, true);
    let end_limit = bounds_limit(end_bounds, false);
    let start_value = if horizontal { points[0].x } else { points[0].y };
    let end_value = if horizontal {
        points[points.len() - 1].x
    } else {
        points[points.len() - 1].y
    };
    let lo = start_limit.min(end_limit);
    let hi = start_limit.max(end_limit);
    let balanced = ((start_value + end_value) / 2.0).clamp(lo, hi);

    let mid = segments[1];
    let mut updated = points.to_vec();
    if horizontal {
        updated[mid.index] = point_with_x(updated[mid.index], balanced);
        updated[mid.index + 1] = point_with_x(updated[mid.index + 1], balanced);
    } else {
        updated[mid.index] = point_with_y(updated[mid.index], balanced);
        updated[mid.index + 1] = point_with_y(updated[mid.index + 1], balanced);
    }

    updated
}

pub(crate) fn collapse_route_backtracks(
    points: &[DrawPoint],
    obstacles: &[DrawRect],
) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points.to_vec();
    }

    let mut updated = points.to_vec();
    let mut changed = true;
    while changed {
        changed = false;
        for i in 1..updated.len().saturating_sub(2) {
            if changed {
                break;
            }
            for j in (i + 2)..updated.len().saturating_sub(1) {
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
                for point in &updated[(i + 1)..j] {
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

                if deviates {
                    let mut collapsed = Vec::with_capacity(updated.len() - (j - i - 1));
                    collapsed.extend_from_slice(&updated[..=i]);
                    collapsed.push(d);
                    collapsed.extend_from_slice(&updated[(j + 1)..]);
                    updated = collapsed;
                    changed = true;
                    break;
                }
            }
        }
    }

    updated
}

pub(crate) fn segment_intersects_any_bounds(
    start: DrawPoint,
    end: DrawPoint,
    obstacles: &[DrawRect],
) -> bool {
    obstacles
        .iter()
        .copied()
        .any(|obstacle| segment_intersects_bounds(start, end, obstacle))
}

#[derive(Clone, Copy, Debug)]
struct RouteSegment {
    index: usize,
    start: DrawPoint,
    end: DrawPoint,
    heading: ElbowHeading,
}

impl RouteSegment {
    fn mid_x(self) -> f64 {
        (self.start.x + self.end.x) / 2.0
    }

    fn mid_y(self) -> f64 {
        (self.start.y + self.end.y) / 2.0
    }
}

fn segment_spacing(segment: RouteSegment, bounds: DrawRect, heading: ElbowHeading) -> Option<f64> {
    let spacing = match heading {
        ElbowHeading::Up => bounds.min_y - segment.mid_y(),
        ElbowHeading::Right => segment.mid_x() - bounds.max_x,
        ElbowHeading::Down => segment.mid_y() - bounds.max_y,
        ElbowHeading::Left => bounds.min_x - segment.mid_x(),
    };
    if !spacing.is_finite() || spacing <= ElbowConstants::INTERSECTION_EPSILON {
        return None;
    }
    Some(spacing)
}

fn apply_segment_spacing(
    points: &mut [DrawPoint],
    segment: RouteSegment,
    bounds: DrawRect,
    heading: ElbowHeading,
    spacing: f64,
) {
    let i = segment.index;
    if i + 1 >= points.len() {
        return;
    }

    let is_vertical_segment = matches!(heading, ElbowHeading::Up | ElbowHeading::Down);
    let value = match heading {
        ElbowHeading::Up => bounds.min_y - spacing,
        ElbowHeading::Right => bounds.max_x + spacing,
        ElbowHeading::Down => bounds.max_y + spacing,
        ElbowHeading::Left => bounds.min_x - spacing,
    };
    if is_vertical_segment {
        points[i] = point_with_y(points[i], value);
        points[i + 1] = point_with_y(points[i + 1], value);
    } else {
        points[i] = point_with_x(points[i], value);
        points[i + 1] = point_with_x(points[i + 1], value);
    }
}

pub(crate) fn ensure_orthogonal_path(
    points: &[DrawPoint],
    start_heading: ElbowHeading,
) -> Vec<DrawPoint> {
    if points.len() < 2 {
        return points.to_vec();
    }

    let mut result = Vec::with_capacity(points.len() * 2);
    result.push(points[0]);
    for next in points.iter().copied().skip(1) {
        let prev = result[result.len() - 1];
        let dx = (next.x - prev.x).abs();
        let dy = (next.y - prev.y).abs();
        if dx <= ElbowConstants::DEDUP_THRESHOLD || dy <= ElbowConstants::DEDUP_THRESHOLD {
            if next != prev {
                result.push(next);
            }
            continue;
        }

        let prefer_horizontal = if result.len() > 1 {
            ElbowGeometry::segment_is_horizontal(result[result.len() - 2], prev)
        } else {
            start_heading.is_horizontal()
        };
        let mid = if prefer_horizontal {
            DrawPoint::new(next.x, prev.y)
        } else {
            DrawPoint::new(prev.x, next.y)
        };
        if mid != prev {
            result.push(mid);
        }
        if next != mid {
            result.push(next);
        }
    }

    result
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) struct ElbowGridAddress {
    pub col: usize,
    pub row: usize,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct ElbowGridNode {
    pub pos: DrawPoint,
    pub addr: ElbowGridAddress,
}

#[derive(Clone, Debug)]
pub(crate) struct ElbowGrid {
    pub rows: usize,
    pub cols: usize,
    pub nodes: Vec<ElbowGridNode>,
    x_index: HashMap<u64, usize>,
    y_index: HashMap<u64, usize>,
}

impl ElbowGrid {
    pub(crate) fn node_at(&self, col: isize, row: isize) -> Option<ElbowGridNode> {
        let index = self.node_index_signed(col, row)?;
        self.nodes.get(index).copied()
    }

    pub(crate) fn node_for_point(&self, point: DrawPoint) -> Option<ElbowGridNode> {
        let col = *self.x_index.get(&axis_key(point.x))?;
        let row = *self.y_index.get(&axis_key(point.y))?;
        self.node_at(col as isize, row as isize)
    }

    fn node_index_signed(&self, col: isize, row: isize) -> Option<usize> {
        if col < 0 || row < 0 {
            return None;
        }
        self.node_index(col as usize, row as usize)
    }

    fn node_index(&self, col: usize, row: usize) -> Option<usize> {
        if col >= self.cols || row >= self.rows {
            return None;
        }
        Some(row * self.cols + col)
    }
}

fn add_bounds_to_axes(xs: &mut Vec<f64>, ys: &mut Vec<f64>, bounds: DrawRect) {
    xs.push(bounds.min_x);
    xs.push(bounds.max_x);
    ys.push(bounds.min_y);
    ys.push(bounds.max_y);
}

fn build_axis_index(sorted_axis: &[f64]) -> HashMap<u64, usize> {
    let mut result = HashMap::with_capacity(sorted_axis.len());
    for (index, value) in sorted_axis.iter().copied().enumerate() {
        result.insert(axis_key(value), index);
    }
    result
}

pub(crate) fn build_grid(
    obstacles: &[DrawRect],
    start: DrawPoint,
    end: DrawPoint,
    bounds: DrawRect,
) -> ElbowGrid {
    let mut xs = vec![start.x, end.x, bounds.min_x, bounds.max_x];
    let mut ys = vec![start.y, end.y, bounds.min_y, bounds.max_y];
    for obstacle in obstacles.iter().copied() {
        add_bounds_to_axes(&mut xs, &mut ys, obstacle);
    }

    let sorted_x = sorted_unique_axis(xs);
    let sorted_y = sorted_unique_axis(ys);
    let x_index = build_axis_index(&sorted_x);
    let y_index = build_axis_index(&sorted_y);

    let mut nodes = Vec::with_capacity(sorted_x.len() * sorted_y.len());
    for (row, y) in sorted_y.iter().copied().enumerate() {
        for (col, x) in sorted_x.iter().copied().enumerate() {
            nodes.push(ElbowGridNode {
                pos: DrawPoint::new(x, y),
                addr: ElbowGridAddress { col, row },
            });
        }
    }

    ElbowGrid {
        rows: sorted_y.len(),
        cols: sorted_x.len(),
        nodes,
        x_index,
        y_index,
    }
}

#[derive(Clone, Copy, Debug)]
struct BendPenalty {
    squared: f64,
    cubed: f64,
}

impl BendPenalty {
    fn new(base: f64) -> Self {
        Self {
            squared: base * base,
            cubed: base * base * base,
        }
    }
}

/// A* router that walks the sparse elbow grid with bend penalties.
pub(crate) struct ElbowGridRouter<'a> {
    pub grid: &'a ElbowGrid,
    pub start: ElbowGridAddress,
    pub end: ElbowGridAddress,
    pub start_heading: ElbowHeading,
    pub end_heading: ElbowHeading,
    pub start_constrained: bool,
    pub end_constrained: bool,
    pub obstacles: &'a [DrawRect],
}

impl ElbowGridRouter<'_> {
    pub(crate) fn find_path(&self) -> Vec<ElbowGridNode> {
        let Some(start_index) = self.grid.node_index(self.start.col, self.start.row) else {
            return Vec::new();
        };
        let Some(end_index) = self.grid.node_index(self.end.col, self.end.row) else {
            return Vec::new();
        };
        let start_node = self.grid.nodes[start_index];
        let end_node = self.grid.nodes[end_index];

        let bend_penalty = BendPenalty::new(ElbowGeometry::manhattan_distance(
            start_node.pos,
            end_node.pos,
        ));
        let end_heading_flip = self.end_heading.opposite();

        let count = self.grid.nodes.len();
        let mut g_scores = vec![f64::INFINITY; count];
        let mut f_scores = vec![f64::INFINITY; count];
        let mut closed = vec![false; count];
        let mut visited = vec![false; count];
        let mut parent: Vec<Option<usize>> = vec![None; count];

        g_scores[start_index] = 0.0;
        f_scores[start_index] = self.heuristic_score(
            start_node.pos,
            end_node.pos,
            self.start_heading,
            end_heading_flip,
            bend_penalty.squared,
        );
        visited[start_index] = true;

        let mut open_set: BinaryHeap<OpenNode, _> = BinaryHeap::new(|node: &OpenNode| node.f);
        open_set.push(OpenNode {
            index: start_index,
            f: f_scores[start_index],
        });

        while open_set.is_not_empty() {
            let Some(current_entry) = open_set.pop() else {
                break;
            };
            let current_index = current_entry.index;
            if closed[current_index] {
                continue;
            }
            if current_entry.f > f_scores[current_index] + ElbowConstants::INTERSECTION_EPSILON {
                continue;
            }
            if current_index == end_index {
                return reconstruct_path(self.grid, &parent, current_index);
            }

            closed[current_index] = true;
            let current_node = self.grid.nodes[current_index];
            let previous_heading = if let Some(parent_index) = parent[current_index] {
                heading_for_segment(self.grid.nodes[parent_index].pos, current_node.pos)
            } else {
                self.start_heading
            };
            let is_start_node = current_index == start_index;

            for offset in NEIGHBOR_OFFSETS {
                let next_col = current_node.addr.col as isize + offset.dx as isize;
                let next_row = current_node.addr.row as isize + offset.dy as isize;
                let Some(next_index) = self.grid.node_index_signed(next_col, next_row) else {
                    continue;
                };
                if closed[next_index] {
                    continue;
                }
                let next_node = self.grid.nodes[next_index];

                if !self.can_traverse_neighbor(
                    current_node,
                    next_node,
                    is_start_node,
                    previous_heading,
                    offset.heading,
                    end_heading_flip,
                ) {
                    continue;
                }

                let direction_changed = offset.heading != previous_heading;
                let move_cost = ElbowGeometry::manhattan_distance(current_node.pos, next_node.pos);
                let bend_cost = if direction_changed {
                    bend_penalty.cubed
                } else {
                    0.0
                };
                let g_score = g_scores[current_index] + move_cost + bend_cost;

                if !visited[next_index] || g_score < g_scores[next_index] {
                    let h_score = self.heuristic_score(
                        next_node.pos,
                        end_node.pos,
                        offset.heading,
                        end_heading_flip,
                        bend_penalty.squared,
                    );
                    parent[next_index] = Some(current_index);
                    g_scores[next_index] = g_score;
                    f_scores[next_index] = g_score + h_score;
                    visited[next_index] = true;
                    open_set.push(OpenNode {
                        index: next_index,
                        f: f_scores[next_index],
                    });
                }
            }
        }

        Vec::new()
    }

    fn can_traverse_neighbor(
        &self,
        current: ElbowGridNode,
        next: ElbowGridNode,
        is_start_node: bool,
        previous_heading: ElbowHeading,
        neighbor_heading: ElbowHeading,
        end_heading_flip: ElbowHeading,
    ) -> bool {
        if segment_intersects_any_bounds(current.pos, next.pos, self.obstacles) {
            return false;
        }

        if neighbor_heading == previous_heading.opposite() {
            return false;
        }

        if is_start_node
            && !allows_heading_from_start(
                self.start_constrained,
                neighbor_heading,
                self.start_heading,
            )
        {
            return false;
        }

        if next.addr == self.end
            && !allows_heading_into_end(self.end_constrained, neighbor_heading, end_heading_flip)
        {
            return false;
        }

        true
    }

    fn heuristic_score(
        &self,
        from: DrawPoint,
        to: DrawPoint,
        from_heading: ElbowHeading,
        end_heading: ElbowHeading,
        bend_penalty_squared: f64,
    ) -> f64 {
        ElbowGeometry::manhattan_distance(from, to)
            + estimated_bend_penalty(from, to, from_heading, end_heading, bend_penalty_squared)
    }
}

fn estimated_bend_penalty(
    start: DrawPoint,
    end: DrawPoint,
    start_heading: ElbowHeading,
    end_heading: ElbowHeading,
    bend_penalty_squared: f64,
) -> f64 {
    let same_axis = start_heading.is_horizontal() == end_heading.is_horizontal();
    if !same_axis {
        return bend_penalty_squared;
    }

    let aligned_on_axis = if start_heading.is_horizontal() {
        (start.y - end.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
    } else {
        (start.x - end.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
    };
    if aligned_on_axis {
        0.0
    } else {
        bend_penalty_squared
    }
}

pub(crate) fn try_route_grid_path(
    grid: &ElbowGrid,
    start: &ResolvedEndpoint,
    end: &ResolvedEndpoint,
    start_exit: DrawPoint,
    end_exit: DrawPoint,
    obstacles: &[DrawRect],
) -> Option<Vec<ElbowGridNode>> {
    let start_node = grid.node_for_point(start_exit)?;
    let end_node = grid.node_for_point(end_exit)?;
    let path = ElbowGridRouter {
        grid,
        start: start_node.addr,
        end: end_node.addr,
        start_heading: start.heading,
        end_heading: end.heading,
        start_constrained: start.is_bound(),
        end_constrained: end.is_bound(),
        obstacles,
    }
    .find_path();

    if path.is_empty() {
        None
    } else {
        Some(path)
    }
}

pub(crate) fn allows_heading_from_start(
    constrained: bool,
    neighbor_heading: ElbowHeading,
    start_heading: ElbowHeading,
) -> bool {
    if !constrained {
        return true;
    }
    neighbor_heading == start_heading
}

pub(crate) fn allows_heading_into_end(
    constrained: bool,
    neighbor_heading: ElbowHeading,
    end_heading_flip: ElbowHeading,
) -> bool {
    !constrained || neighbor_heading == end_heading_flip
}

fn reconstruct_path(
    grid: &ElbowGrid,
    parent: &[Option<usize>],
    current: usize,
) -> Vec<ElbowGridNode> {
    let mut reversed = Vec::new();
    let mut cursor = Some(current);
    while let Some(index) = cursor {
        reversed.push(grid.nodes[index]);
        cursor = parent[index];
    }
    reversed.reverse();
    reversed
}

#[derive(Clone, Copy, Debug)]
struct ElbowNeighborOffset {
    dx: i32,
    dy: i32,
    heading: ElbowHeading,
}

const NEIGHBOR_OFFSETS: [ElbowNeighborOffset; 4] = [
    ElbowNeighborOffset {
        dx: 0,
        dy: -1,
        heading: ElbowHeading::Up,
    },
    ElbowNeighborOffset {
        dx: 1,
        dy: 0,
        heading: ElbowHeading::Right,
    },
    ElbowNeighborOffset {
        dx: 0,
        dy: 1,
        heading: ElbowHeading::Down,
    },
    ElbowNeighborOffset {
        dx: -1,
        dy: 0,
        heading: ElbowHeading::Left,
    },
];

#[derive(Clone, Copy, Debug)]
struct OpenNode {
    index: usize,
    f: f64,
}

struct ElbowSpacing;

impl ElbowSpacing {
    fn min_binding_spacing(has_arrowhead: bool) -> f64 {
        let base = ArrowBindingUtils::ELBOW_BINDING_GAP_BASE;
        if has_arrowhead {
            base * ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
        } else {
            base
        }
    }

    fn resolve_shared_spacing(
        start_spacing: Option<f64>,
        end_spacing: Option<f64>,
        start_has_arrowhead: bool,
        end_has_arrowhead: bool,
    ) -> Option<f64> {
        let start_spacing = start_spacing?;
        let end_spacing = end_spacing?;
        let shared = start_spacing.min(end_spacing);
        if !shared.is_finite() {
            return None;
        }
        let min_allowed = Self::min_binding_spacing(start_has_arrowhead)
            .max(Self::min_binding_spacing(end_has_arrowhead));
        Some(shared.max(min_allowed))
    }
}

fn heading_for_segment(from: DrawPoint, to: DrawPoint) -> ElbowHeading {
    let dx = to.x - from.x;
    let dy = to.y - from.y;
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

fn point_with_x(point: DrawPoint, x: f64) -> DrawPoint {
    point.copy_with(Some(x), None, None, None)
}

fn point_with_y(point: DrawPoint, y: f64) -> DrawPoint {
    point.copy_with(None, Some(y), None, None)
}

fn clamp_point(point: DrawPoint) -> DrawPoint {
    let max = ElbowConstants::MAX_POSITION;
    point.copy_with(
        Some(point.x.clamp(-max, max)),
        Some(point.y.clamp(-max, max)),
        None,
        None,
    )
}

fn sorted_unique_axis(mut axis: Vec<f64>) -> Vec<f64> {
    for value in &mut axis {
        if *value == 0.0 {
            *value = 0.0;
        }
    }
    axis.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
    axis.dedup_by(|a, b| (*a - *b).abs() <= ElbowConstants::INTERSECTION_EPSILON);
    axis
}

fn axis_key(value: f64) -> u64 {
    let normalized = if value == 0.0 { 0.0 } else { value };
    normalized.to_bits()
}
