#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Converts `position` into the element-local coordinate space.
///
/// `rect` and `rotation` are the element's world-space bounds and rotation.
pub fn resolve_element_local_position(
    rect: DrawRect,
    rotation: f64,
    position: DrawPoint,
) -> DrawPoint {
    if rotation == 0.0 {
        return position;
    }
    let space = ElementSpace::new(rotation, rect.center());
    space.from_world(position)
}

/// Returns whether `value` has finite coordinates.
pub fn is_finite_draw_point(value: DrawPoint) -> bool {
    value.x.is_finite() && value.y.is_finite()
}

/// Returns whether `position` is inside `rect` expanded by `padding`.
pub fn is_point_inside_rect(rect: DrawRect, position: DrawPoint, padding: f64) -> bool {
    position.x >= rect.min_x - padding
        && position.x <= rect.max_x + padding
        && position.y >= rect.min_y - padding
        && position.y <= rect.max_y + padding
}

/// Hit-tests a normalized two-point stroke against `local_position`.
///
/// `normalized_start` and `normalized_end` are expected in `[0, 1]`
/// element-space coordinates.
pub fn hit_test_normalized_two_point_stroke(
    rect: DrawRect,
    normalized_start: DrawPoint,
    normalized_end: DrawPoint,
    local_position: DrawPoint,
    stroke_width: f64,
    tolerance: f64,
) -> bool {
    let radius = (stroke_width / 2.0) + tolerance;
    if !radius.is_finite() || radius <= 0.0 {
        return false;
    }
    if !is_point_inside_rect(rect, local_position, radius) {
        return false;
    }

    let width = rect.width();
    let height = rect.height();
    if !width.is_finite() || !height.is_finite() || width < 0.0 || height < 0.0 {
        return false;
    }

    let start = DrawPoint::new(
        rect.min_x + (normalized_start.x * width),
        rect.min_y + (normalized_start.y * height),
    );
    let end = DrawPoint::new(
        rect.min_x + (normalized_end.x * width),
        rect.min_y + (normalized_end.y * height),
    );
    if !is_finite_draw_point(start) || !is_finite_draw_point(end) {
        return false;
    }

    distance_squared_to_segment(local_position, start, end) <= radius * radius
}

/// Returns squared distance from point `p` to segment `a-b`.
pub fn distance_squared_to_segment(p: DrawPoint, a: DrawPoint, b: DrawPoint) -> f64 {
    let ab_x = b.x - a.x;
    let ab_y = b.y - a.y;
    let ap_x = p.x - a.x;
    let ap_y = p.y - a.y;
    let ab_length_sq = ab_x * ab_x + ab_y * ab_y;

    if ab_length_sq == 0.0 {
        return ap_x * ap_x + ap_y * ap_y;
    }

    let mut t = (ap_x * ab_x + ap_y * ab_y) / ab_length_sq;
    t = t.clamp(0.0, 1.0);

    let closest_x = a.x + ab_x * t;
    let closest_y = a.y + ab_y * t;
    let dx = p.x - closest_x;
    let dy = p.y - closest_y;
    dx * dx + dy * dy
}

/// Returns true when `point` lies inside `polygon` using even-odd winding.
pub fn is_point_inside_polygon(point: DrawPoint, polygon: &[DrawPoint], epsilon: f64) -> bool {
    if polygon.len() < 3 {
        return false;
    }

    let mut inside = false;
    let mut previous_index = polygon.len() - 1;
    for (index, current) in polygon.iter().copied().enumerate() {
        let previous = polygon[previous_index];
        let intersects = (current.y > point.y) != (previous.y > point.y)
            && point.x
                < (previous.x - current.x) * (point.y - current.y)
                    / if (previous.y - current.y).abs() < epsilon {
                        epsilon
                    } else {
                        previous.y - current.y
                    }
                    + current.x;
        if intersects {
            inside = !inside;
        }
        previous_index = index;
    }
    inside
}

/// Returns `a + b`.
pub fn add_draw_points(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new(a.x + b.x, a.y + b.y)
}

/// Returns `a + direction * scale`.
pub fn add_scaled_draw_point(a: DrawPoint, direction: DrawPoint, scale: f64) -> DrawPoint {
    DrawPoint::new(a.x + direction.x * scale, a.y + direction.y * scale)
}

/// Returns `a - direction * scale`.
pub fn subtract_scaled_draw_point(a: DrawPoint, direction: DrawPoint, scale: f64) -> DrawPoint {
    DrawPoint::new(a.x - direction.x * scale, a.y - direction.y * scale)
}

/// Returns normalized `value`, or `None` when it has zero length.
pub fn normalize_draw_vector(value: DrawPoint) -> Option<DrawPoint> {
    let length = (value.x * value.x + value.y * value.y).sqrt();
    if length == 0.0 {
        return None;
    }
    Some(DrawPoint::new(value.x / length, value.y / length))
}

/// Cubic segment used for curve flattening.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CubicDrawSegment {
    /// Segment start point.
    pub start: DrawPoint,
    /// First control point.
    pub control1: DrawPoint,
    /// Second control point.
    pub control2: DrawPoint,
    /// Segment end point.
    pub end: DrawPoint,
}

impl CubicDrawSegment {
    /// Creates an immutable cubic segment.
    pub const fn new(
        start: DrawPoint,
        control1: DrawPoint,
        control2: DrawPoint,
        end: DrawPoint,
    ) -> Self {
        Self {
            start,
            control1,
            control2,
            end,
        }
    }
}

/// Builds a Catmull-Rom-derived cubic segment at `index`.
pub fn build_catmull_rom_cubic_segment(
    points: &[DrawPoint],
    index: usize,
    tension: f64,
    phantom_first: Option<DrawPoint>,
    phantom_last: Option<DrawPoint>,
) -> CubicDrawSegment {
    let last_index = points.len() - 1;
    let p0 = if index == 0 {
        phantom_first.unwrap_or(points[index])
    } else {
        points[index - 1]
    };
    let p1 = points[index];
    let p2 = points[index + 1];
    let p3 = if index + 2 <= last_index {
        points[index + 2]
    } else {
        phantom_last.unwrap_or(points[index + 1])
    };

    let control1 = DrawPoint::new(
        p1.x + (p2.x - p0.x) * (tension / 6.0),
        p1.y + (p2.y - p0.y) * (tension / 6.0),
    );
    let control2 = DrawPoint::new(
        p2.x - (p3.x - p1.x) * (tension / 6.0),
        p2.y - (p3.y - p1.y) * (tension / 6.0),
    );

    CubicDrawSegment::new(p1, control1, control2, p2)
}

/// Flattens Catmull-Rom points into a polyline for hit testing.
pub fn flatten_catmull_rom_draw_points(
    points: &[DrawPoint],
    stroke_width: f64,
    max_points: usize,
    tension: f64,
    use_open_endpoint_phantom_points: bool,
) -> Vec<DrawPoint> {
    if points.is_empty() {
        return Vec::new();
    }
    if points.len() < 3 {
        return points.to_vec();
    }
    if max_points == 0 {
        return Vec::new();
    }

    let step = stroke_width.max(1.0);
    let tolerance = 0.5_f64.max(step * 0.35);
    let tolerance_sq = tolerance * tolerance;

    let mut phantom_first: Option<DrawPoint> = None;
    let mut phantom_last: Option<DrawPoint> = None;
    if use_open_endpoint_phantom_points && points.len() >= 2 {
        let first = points[0];
        let second = points[1];
        let penultimate = points[points.len() - 2];
        let last = points[points.len() - 1];
        phantom_first = Some(first + (first - second));
        phantom_last = Some(last + (last - penultimate));
    }

    let mut flattened = vec![points[0]];
    for index in 0..(points.len() - 1) {
        if flattened.len() >= max_points {
            break;
        }
        let segment =
            build_catmull_rom_cubic_segment(points, index, tension, phantom_first, phantom_last);
        flatten_cubic_segment(segment, tolerance_sq, &mut flattened, max_points);
    }
    flattened
}

fn flatten_cubic_segment(
    segment: CubicDrawSegment,
    tolerance_sq: f64,
    output: &mut Vec<DrawPoint>,
    max_points: usize,
) {
    if max_points == 0 {
        return;
    }

    let mut stack = vec![segment];
    while !stack.is_empty() && output.len() < max_points {
        let current = stack.pop().expect("stack is not empty");
        if is_cubic_flat_enough(current, tolerance_sq)
            || output.len() >= max_points.saturating_sub(1)
        {
            output.push(current.end);
            continue;
        }

        let (left, right) = split_cubic_segment(current);
        stack.push(right);
        stack.push(left);
    }
}

fn is_cubic_flat_enough(segment: CubicDrawSegment, tolerance_sq: f64) -> bool {
    let dist1 = distance_squared_to_line(segment.control1, segment.start, segment.end);
    let dist2 = distance_squared_to_line(segment.control2, segment.start, segment.end);
    dist1.max(dist2) <= tolerance_sq
}

fn split_cubic_segment(segment: CubicDrawSegment) -> (CubicDrawSegment, CubicDrawSegment) {
    let p01 = midpoint_draw_point(segment.start, segment.control1);
    let p12 = midpoint_draw_point(segment.control1, segment.control2);
    let p23 = midpoint_draw_point(segment.control2, segment.end);
    let p012 = midpoint_draw_point(p01, p12);
    let p123 = midpoint_draw_point(p12, p23);
    let p0123 = midpoint_draw_point(p012, p123);

    (
        CubicDrawSegment::new(segment.start, p01, p012, p0123),
        CubicDrawSegment::new(p0123, p123, p23, segment.end),
    )
}

fn midpoint_draw_point(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
}

fn distance_squared_to_line(point: DrawPoint, a: DrawPoint, b: DrawPoint) -> f64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let len_sq = dx * dx + dy * dy;
    if len_sq == 0.0 {
        let diff_x = point.x - a.x;
        let diff_y = point.y - a.y;
        return diff_x * diff_x + diff_y * diff_y;
    }
    let cross = dx * (point.y - a.y) - dy * (point.x - a.x);
    (cross * cross) / len_sq
}
