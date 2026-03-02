#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingUtils, ElementState as ArrowElementState,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::elbow_constants::ElbowConstants;

/// Internal axis tagging for elbow paths.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ElbowAxis {
    Horizontal,
    Vertical,
}

impl ElbowAxis {
    /// Whether this axis is horizontal.
    pub const fn is_horizontal(self) -> bool {
        matches!(self, Self::Horizontal)
    }

    /// Whether this axis is vertical.
    pub const fn is_vertical(self) -> bool {
        matches!(self, Self::Vertical)
    }
}

/// Cardinal heading used by elbow path geometry.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ElbowHeading {
    Up,
    Right,
    Down,
    Left,
}

impl ElbowHeading {
    /// Horizontal unit component of this heading.
    pub const fn dx(self) -> f64 {
        match self {
            Self::Left => -1.0,
            Self::Right => 1.0,
            _ => 0.0,
        }
    }

    /// Vertical unit component of this heading.
    pub const fn dy(self) -> f64 {
        match self {
            Self::Up => -1.0,
            Self::Down => 1.0,
            _ => 0.0,
        }
    }
}

/// Shared geometry helpers for elbow routing and editing.
pub struct ElbowGeometry;

impl ElbowGeometry {
    const HEADING_EPSILON: f64 = 1e-6;

    /// Returns the dominant cardinal heading for a vector.
    ///
    /// The dominant axis wins; ties favor horizontal headings.
    pub fn heading_for_vector(dx: f64, dy: f64) -> ElbowHeading {
        let abs_x = dx.abs();
        let abs_y = dy.abs();
        if abs_x >= abs_y {
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

    /// Returns the heading for a segment from `from` to `to`.
    pub fn heading_for_segment(from: DrawPoint, to: DrawPoint) -> ElbowHeading {
        Self::heading_for_vector(to.x - from.x, to.y - from.y)
    }

    /// Manhattan distance between two points.
    pub fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
        (a.x - b.x).abs() + (a.y - b.y).abs()
    }

    /// Returns true when the segment is closer to horizontal than vertical.
    pub fn is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
        (a.y - b.y).abs() <= (a.x - b.x).abs()
    }

    /// Determines which side of the bounds a point belongs to.
    pub fn heading_for_point_on_bounds(bounds: DrawRect, point: DrawPoint) -> ElbowHeading {
        let center = bounds.center();
        let dx = point.x - center.x;
        let dy = point.y - center.y;
        let width = bounds.width().abs();
        let height = bounds.height().abs();
        if width <= Self::HEADING_EPSILON || height <= Self::HEADING_EPSILON {
            return ElbowHeading::Left;
        }

        let horizontal_weight = dx.abs() * height;
        let vertical_weight = dy.abs() * width;
        let tolerance = Self::HEADING_EPSILON * width * height;

        if dy <= Self::HEADING_EPSILON
            && dy >= -height - Self::HEADING_EPSILON
            && horizontal_weight <= vertical_weight + tolerance
        {
            return ElbowHeading::Up;
        }
        if dx >= -Self::HEADING_EPSILON
            && dx <= width + Self::HEADING_EPSILON
            && vertical_weight <= horizontal_weight + tolerance
        {
            return ElbowHeading::Right;
        }
        if dy >= -Self::HEADING_EPSILON
            && dy <= height + Self::HEADING_EPSILON
            && horizontal_weight <= vertical_weight + tolerance
        {
            return ElbowHeading::Down;
        }

        ElbowHeading::Left
    }

    /// Returns an axis only when the segment is axis-aligned within tolerance.
    pub fn axis_aligned_for_segment(a: DrawPoint, b: DrawPoint) -> Option<ElbowAxis> {
        Self::axis_aligned_for_segment_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns an axis only when the segment is axis-aligned within tolerance.
    pub fn axis_aligned_for_segment_with_epsilon(
        a: DrawPoint,
        b: DrawPoint,
        epsilon: f64,
    ) -> Option<ElbowAxis> {
        let dx = (a.x - b.x).abs();
        let dy = (a.y - b.y).abs();
        if dx <= epsilon && dy <= epsilon {
            return None;
        }
        if dy <= epsilon {
            return Some(ElbowAxis::Horizontal);
        }
        if dx <= epsilon {
            return Some(ElbowAxis::Vertical);
        }
        None
    }

    /// Returns a stable axis for a segment, falling back to the dominant axis.
    pub fn axis_for_segment(a: DrawPoint, b: DrawPoint) -> ElbowAxis {
        Self::axis_for_segment_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns a stable axis for a segment, falling back to the dominant axis.
    pub fn axis_for_segment_with_epsilon(a: DrawPoint, b: DrawPoint, epsilon: f64) -> ElbowAxis {
        Self::axis_aligned_for_segment_with_epsilon(a, b, epsilon).unwrap_or_else(|| {
            if Self::is_horizontal(a, b) {
                ElbowAxis::Horizontal
            } else {
                ElbowAxis::Vertical
            }
        })
    }

    /// Returns true when a segment is (or should be treated as) horizontal.
    pub fn segment_is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
        Self::segment_is_horizontal_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns true when a segment is (or should be treated as) horizontal.
    pub fn segment_is_horizontal_with_epsilon(a: DrawPoint, b: DrawPoint, epsilon: f64) -> bool {
        Self::axis_for_segment_with_epsilon(a, b, epsilon).is_horizontal()
    }

    /// Returns true when a segment is (or should be treated as) vertical.
    pub fn segment_is_vertical(a: DrawPoint, b: DrawPoint) -> bool {
        Self::segment_is_vertical_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns true when a segment is (or should be treated as) vertical.
    pub fn segment_is_vertical_with_epsilon(a: DrawPoint, b: DrawPoint, epsilon: f64) -> bool {
        Self::axis_for_segment_with_epsilon(a, b, epsilon).is_vertical()
    }

    /// Returns the shared axis coordinate for a segment.
    pub fn axis_value(start: DrawPoint, end: DrawPoint, axis: ElbowAxis) -> f64 {
        if axis.is_horizontal() {
            (start.y + end.y) / 2.0
        } else {
            (start.x + end.x) / 2.0
        }
    }

    /// Returns true when two points are nearly identical.
    pub fn points_close(a: DrawPoint, b: DrawPoint) -> bool {
        Self::points_close_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns true when two points are nearly identical.
    pub fn points_close_with_epsilon(a: DrawPoint, b: DrawPoint, epsilon: f64) -> bool {
        (a.x - b.x).abs() <= epsilon && (a.y - b.y).abs() <= epsilon
    }

    /// Returns true when two points align on either axis.
    pub fn points_aligned(a: DrawPoint, b: DrawPoint) -> bool {
        Self::points_aligned_with_epsilon(a, b, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns true when two points align on either axis.
    pub fn points_aligned_with_epsilon(a: DrawPoint, b: DrawPoint, epsilon: f64) -> bool {
        (a.x - b.x).abs() <= epsilon || (a.y - b.y).abs() <= epsilon
    }

    /// Returns true when three points form a straight orthogonal line.
    pub fn segments_collinear(a: DrawPoint, b: DrawPoint, c: DrawPoint) -> bool {
        Self::segments_collinear_with_epsilon(a, b, c, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Returns true when three points form a straight orthogonal line.
    pub fn segments_collinear_with_epsilon(
        a: DrawPoint,
        b: DrawPoint,
        c: DrawPoint,
        epsilon: f64,
    ) -> bool {
        let Some(axis) = Self::axis_aligned_for_segment_with_epsilon(a, b, epsilon) else {
            return false;
        };
        let Some(next_axis) = Self::axis_aligned_for_segment_with_epsilon(b, c, epsilon) else {
            return false;
        };
        if axis != next_axis {
            return false;
        }

        let axis_value_a = Self::axis_value(a, b, axis);
        let axis_value_b = Self::axis_value(b, c, axis);
        (axis_value_a - axis_value_b).abs() <= epsilon
    }

    /// Returns a direct elbow path with a single corner when possible.
    pub fn direct_elbow_path(
        start: DrawPoint,
        end: DrawPoint,
        prefer_horizontal: bool,
    ) -> Vec<DrawPoint> {
        Self::direct_elbow_path_with_epsilon(
            start,
            end,
            prefer_horizontal,
            ElbowConstants::DEDUP_THRESHOLD,
        )
    }

    /// Returns a direct elbow path with a single corner when possible.
    pub fn direct_elbow_path_with_epsilon(
        start: DrawPoint,
        end: DrawPoint,
        prefer_horizontal: bool,
        epsilon: f64,
    ) -> Vec<DrawPoint> {
        if (start.x - end.x).abs() <= epsilon || (start.y - end.y).abs() <= epsilon {
            return vec![start, end];
        }

        let mid = if prefer_horizontal {
            DrawPoint::new(end.x, start.y)
        } else {
            DrawPoint::new(start.x, end.y)
        };
        vec![start, mid, end]
    }

    /// Removes short interior segments while keeping endpoints intact.
    pub fn remove_short_segments(points: &[DrawPoint]) -> Vec<DrawPoint> {
        Self::remove_short_segments_with_min_length(points, ElbowConstants::DEDUP_THRESHOLD)
    }

    /// Removes short interior segments while keeping endpoints intact.
    pub fn remove_short_segments_with_min_length(
        points: &[DrawPoint],
        min_length: f64,
    ) -> Vec<DrawPoint> {
        if points.len() < 4 {
            return points.to_vec();
        }

        let mut result = Vec::with_capacity(points.len());
        result.push(points[0]);
        for index in 1..(points.len() - 1) {
            if Self::manhattan_distance(points[index - 1], points[index]) > min_length {
                result.push(points[index]);
            }
        }
        result.push(points[points.len() - 1]);
        result
    }

    /// Keeps only the corner points of an orthogonal polyline.
    pub fn corner_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
        if points.len() <= 2 {
            return points.to_vec();
        }

        let mut prev_horizontal = Self::segment_is_horizontal(points[0], points[1]);
        let mut result = Vec::with_capacity(points.len());
        result.push(points[0]);

        for index in 1..(points.len() - 1) {
            let next_horizontal = Self::segment_is_horizontal(points[index], points[index + 1]);
            if prev_horizontal != next_horizontal {
                result.push(points[index]);
            }
            prev_horizontal = next_horizontal;
        }

        result.push(points[points.len() - 1]);
        result
    }

    /// Simplifies an orthogonal path while keeping pinned points intact.
    pub fn simplify_path(points: &[DrawPoint]) -> Vec<DrawPoint> {
        let pinned = HashSet::new();
        Self::simplify_path_with_pinned(points, &pinned)
    }

    /// Simplifies an orthogonal path while keeping pinned points intact.
    pub fn simplify_path_with_pinned(
        points: &[DrawPoint],
        pinned: &HashSet<DrawPoint>,
    ) -> Vec<DrawPoint> {
        if points.len() < 3 {
            return points.to_vec();
        }

        let mut reduced = Vec::with_capacity(points.len());
        reduced.push(points[0]);
        for index in 1..(points.len() - 1) {
            let point = points[index];
            let last = *reduced.last().expect("reduced always has first point");
            let has_turn = Self::segment_is_horizontal(last, point)
                != Self::segment_is_horizontal(point, points[index + 1]);
            if pinned.contains(&point) || has_turn {
                reduced.push(point);
            }
        }
        reduced.push(points[points.len() - 1]);

        let mut cleaned = Vec::with_capacity(reduced.len());
        cleaned.push(reduced[0]);
        for point in reduced.iter().copied().skip(1) {
            let last = *cleaned.last().expect("cleaned always has first point");
            if point != last
                && (pinned.contains(&point)
                    || Self::manhattan_distance(last, point) > ElbowConstants::DEDUP_THRESHOLD)
            {
                cleaned.push(point);
            }
        }

        cleaned
    }

    /// Merges consecutive segments that share the same heading.
    pub fn merge_consecutive_same_heading(points: &[DrawPoint]) -> Vec<DrawPoint> {
        let pinned = HashSet::new();
        Self::merge_consecutive_same_heading_with_pinned(points, &pinned)
    }

    /// Merges consecutive segments that share the same heading.
    ///
    /// Two segments with the same heading but at different axis values indicate
    /// a redundant intermediate point. Removing it collapses the pair into a
    /// single segment.
    pub fn merge_consecutive_same_heading_with_pinned(
        points: &[DrawPoint],
        pinned: &HashSet<DrawPoint>,
    ) -> Vec<DrawPoint> {
        if points.len() < 3 {
            return points.to_vec();
        }

        let mut merged = Vec::with_capacity(points.len());
        merged.push(points[0]);
        merged.push(points[1]);

        for point in points.iter().copied().skip(2) {
            merged.push(point);
            while merged.len() >= 3 {
                let prev = merged[merged.len() - 3];
                let mid = merged[merged.len() - 2];
                let next = merged[merged.len() - 1];
                let prev_len = Self::manhattan_distance(prev, mid);
                let next_len = Self::manhattan_distance(mid, next);

                if prev_len <= ElbowConstants::DEDUP_THRESHOLD
                    || next_len <= ElbowConstants::DEDUP_THRESHOLD
                    || pinned.contains(&mid)
                    || Self::heading_for_segment(prev, mid) != Self::heading_for_segment(mid, next)
                {
                    break;
                }

                merged.remove(merged.len() - 2);
            }
        }

        merged
    }

    /// Returns true when any segment is diagonal beyond the tolerance.
    pub fn has_diagonal_segments(points: &[DrawPoint]) -> bool {
        for index in 1..points.len() {
            if (points[index].x - points[index - 1].x).abs() > ElbowConstants::DEDUP_THRESHOLD
                && (points[index].y - points[index - 1].y).abs() > ElbowConstants::DEDUP_THRESHOLD
            {
                return true;
            }
        }
        false
    }

    /// Offsets `point` along `heading` by `distance`.
    pub fn offset_point(point: DrawPoint, heading: ElbowHeading, distance: f64) -> DrawPoint {
        DrawPoint::new(
            point.x + heading.dx() * distance,
            point.y + heading.dy() * distance,
        )
    }

    /// Total Manhattan path length across all segments.
    pub fn path_length(points: &[DrawPoint]) -> f64 {
        points
            .windows(2)
            .map(|segment| Self::manhattan_distance(segment[0], segment[1]))
            .sum()
    }

    /// Whether two point lists are element-wise equal.
    pub fn point_lists_equal(a: &[DrawPoint], b: &[DrawPoint]) -> bool {
        if a.len() != b.len() {
            return false;
        }

        a.iter().zip(b.iter()).all(|(left, right)| left == right)
    }

    /// Whether two point lists are equal except at the endpoints.
    pub fn point_lists_equal_except_endpoints(a: &[DrawPoint], b: &[DrawPoint]) -> bool {
        if a.len() != b.len() || a.len() < 2 {
            return false;
        }

        for index in 1..(a.len() - 1) {
            if a[index] != b[index] {
                return false;
            }
        }

        true
    }

    /// Resolves the bound heading for an arrow endpoint.
    ///
    /// Returns the cardinal direction the arrow should exit from the bound
    /// element, or `None` when the binding target is missing.
    pub fn resolve_bound_heading(
        binding: &ArrowBinding,
        elements_by_id: &HashMap<String, ArrowElementState>,
        point: DrawPoint,
    ) -> Option<ElbowHeading> {
        let element = elements_by_id.get(binding.element_id.as_str())?;
        let bounds = compute_element_world_aabb(element);
        let anchor = ArrowBindingUtils::resolve_elbow_anchor_point(binding, element);
        Some(Self::heading_for_point_on_bounds(
            bounds,
            anchor.unwrap_or(point),
        ))
    }
}

fn compute_element_world_aabb(element: &ArrowElementState) -> DrawRect {
    let rect = element.rect;
    let rotation = element.rotation;
    if rotation == 0.0 {
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
