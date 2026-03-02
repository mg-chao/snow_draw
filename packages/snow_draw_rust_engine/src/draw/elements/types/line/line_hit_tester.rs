#![allow(dead_code)]

use std::sync::{LazyLock, Mutex};

use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::elements::types::arrow::arrow_hit_tester::{
    ArrowHitTestElement, ArrowHitTester, ArrowLikeData,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::lru_cache::LruCache;

/// Hit tester for line elements.
///
/// The fallback [`ElementState`] used by this crate does not yet carry typed
/// element payload data. Use [`Self::hit_test_line`] with
/// [`LineHitTestElement`] for full-fidelity hit testing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct LineHitTester;

impl LineHitTester {
    const CACHE_LIMIT: usize = 512;
    const POLYGON_EPSILON: f64 = 1e-9;
    const CATMULL_ROM_TENSION: f64 = 1.0;
    const CATMULL_ROM_MAX_POINTS: usize = 120;

    /// Hit-tests a line element with explicit line payload data.
    pub fn hit_test_line<D: LineLikeData + ?Sized>(
        &self,
        element: &LineHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        if self.hit_test_stroke(element, position, tolerance) {
            return true;
        }

        let fill_opacity = (element.data.fill_alpha() * element.opacity).clamp(0.0, 1.0);
        if fill_opacity <= 0.0 || !is_closed(element.data.points()) {
            return false;
        }

        let local_position =
            resolve_element_local_position(element.rect, element.rotation, position);
        if !is_point_inside_rect(element.rect, local_position, 0.0) {
            return false;
        }

        let fill_outline = self.resolve_fill_outline(element);
        if fill_outline.len() < 3 {
            return false;
        }

        let test_point = DrawPoint::new(
            local_position.x - element.rect.min_x,
            local_position.y - element.rect.min_y,
        );
        is_point_inside_polygon(test_point, &fill_outline, Self::POLYGON_EPSILON)
    }

    fn hit_test_stroke<D: LineLikeData + ?Sized>(
        &self,
        element: &LineHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        if element.data.stroke_width() <= 0.0 {
            return false;
        }

        if element.data.points().len() == 2 {
            let local_position =
                resolve_element_local_position(element.rect, element.rotation, position);
            if hit_test_two_point_stroke_fast(
                element.rect,
                element.data.points()[0],
                element.data.points()[1],
                local_position,
                element.data.stroke_width(),
                tolerance,
            ) {
                return true;
            }
        }

        let as_arrow_data = LineAsArrowData {
            inner: element.data,
        };
        let arrow_element = ArrowHitTestElement {
            id: element.id,
            rect: element.rect,
            rotation: element.rotation,
            data: &as_arrow_data,
        };
        ArrowHitTester.hit_test_arrow(&arrow_element, position, tolerance)
    }

    fn resolve_fill_outline<D: LineLikeData + ?Sized>(
        &self,
        element: &LineHitTestElement<'_, D>,
    ) -> Vec<DrawPoint> {
        let rect = element.rect;
        let width = rect.width();
        let height = rect.height();
        let id = element.id;
        let data_identity = (element.data as *const D as *const ()) as usize;

        let mut cache = FILL_OUTLINE_CACHE
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let id_key = id.to_owned();
        if let Some(cached) = cache.get(&id_key).cloned() {
            if cached.matches(width, height, data_identity) {
                return cached.fill_outline;
            }
        }

        let local_points: Vec<DrawPoint> = element
            .data
            .points()
            .iter()
            .map(|point| DrawPoint::new(point.x * width, point.y * height))
            .collect();
        let fill_outline =
            if element.data.arrow_type() == ArrowType::Curved && local_points.len() > 2 {
                flatten_catmull_rom_draw_points(&local_points, element.data.stroke_width())
            } else {
                local_points
            };
        let normalized_outline = ensure_closed_outline(fill_outline);
        cache.put(
            id_key,
            LineFillOutlineCacheEntry {
                width,
                height,
                data_identity,
                fill_outline: normalized_outline.clone(),
            },
        );
        normalized_outline
    }
}

impl ElementHitTester for LineHitTester {
    fn hit_test_with_tolerance(
        &self,
        _element: &ElementState,
        _position: DrawPoint,
        _tolerance: f64,
    ) -> bool {
        // Requires typed line payload data that is not present in the current
        // fallback `ElementState` translation.
        false
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

/// Line-only snapshot used by [`LineHitTester::hit_test_line`].
#[derive(Clone, Copy, Debug)]
pub struct LineHitTestElement<'a, D: LineLikeData + ?Sized> {
    pub id: &'a str,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub data: &'a D,
}

/// Shared payload contract for line-like data.
pub trait LineLikeData {
    /// Normalized control points in element-local space (`0..1`).
    fn points(&self) -> &[DrawPoint];
    fn stroke_width(&self) -> f64;

    /// Normalized fill alpha in `[0, 1]`.
    fn fill_alpha(&self) -> f64;

    /// Line elements are curved by default.
    fn arrow_type(&self) -> ArrowType {
        ArrowType::Curved
    }
}

#[derive(Clone, Copy, Debug)]
struct LineAsArrowData<'a, D: LineLikeData + ?Sized> {
    inner: &'a D,
}

impl<D: LineLikeData + ?Sized> ArrowLikeData for LineAsArrowData<'_, D> {
    fn points(&self) -> &[DrawPoint] {
        self.inner.points()
    }

    fn stroke_width(&self) -> f64 {
        self.inner.stroke_width()
    }

    fn arrow_type(&self) -> ArrowType {
        self.inner.arrow_type()
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        ArrowheadStyle::None
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        ArrowheadStyle::None
    }
}

#[derive(Clone, Debug)]
struct LineFillOutlineCacheEntry {
    width: f64,
    height: f64,
    data_identity: usize,
    fill_outline: Vec<DrawPoint>,
}

impl LineFillOutlineCacheEntry {
    fn matches(&self, width: f64, height: f64, data_identity: usize) -> bool {
        self.width == width && self.height == height && self.data_identity == data_identity
    }
}

static FILL_OUTLINE_CACHE: LazyLock<Mutex<LruCache<String, LineFillOutlineCacheEntry>>> =
    LazyLock::new(|| Mutex::new(LruCache::new(LineHitTester::CACHE_LIMIT)));

fn resolve_element_local_position(rect: DrawRect, rotation: f64, position: DrawPoint) -> DrawPoint {
    if rotation == 0.0 {
        return position;
    }

    let center = rect.center();
    rotate_point(position, center, -rotation)
}

fn rotate_point(point: DrawPoint, center: DrawPoint, angle_radians: f64) -> DrawPoint {
    let sin = angle_radians.sin();
    let cos = angle_radians.cos();
    let dx = point.x - center.x;
    let dy = point.y - center.y;
    DrawPoint::new(
        center.x + (dx * cos - dy * sin),
        center.y + (dx * sin + dy * cos),
    )
}

fn is_point_inside_rect(rect: DrawRect, position: DrawPoint, padding: f64) -> bool {
    position.x >= rect.min_x - padding
        && position.x <= rect.max_x + padding
        && position.y >= rect.min_y - padding
        && position.y <= rect.max_y + padding
}

fn is_closed(points: &[DrawPoint]) -> bool {
    points.len() > 2 && same_location(points[0], points[points.len() - 1])
}

fn same_location(a: DrawPoint, b: DrawPoint) -> bool {
    a.x == b.x && a.y == b.y
}

fn hit_test_two_point_stroke_fast(
    rect: DrawRect,
    normalized_start: DrawPoint,
    normalized_end: DrawPoint,
    local_position: DrawPoint,
    stroke_width: f64,
    tolerance: f64,
) -> bool {
    hit_test_normalized_two_point_stroke(
        rect,
        normalized_start,
        normalized_end,
        local_position,
        stroke_width,
        tolerance,
    )
}

fn hit_test_normalized_two_point_stroke(
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

fn is_finite_draw_point(value: DrawPoint) -> bool {
    value.x.is_finite() && value.y.is_finite()
}

fn distance_squared_to_segment(p: DrawPoint, a: DrawPoint, b: DrawPoint) -> f64 {
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

fn is_point_inside_polygon(point: DrawPoint, polygon: &[DrawPoint], epsilon: f64) -> bool {
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

fn ensure_closed_outline(mut points: Vec<DrawPoint>) -> Vec<DrawPoint> {
    if points.is_empty() {
        return points;
    }
    if same_location(points[0], points[points.len() - 1]) {
        return points;
    }
    points.push(points[0]);
    points
}

#[derive(Clone, Copy, Debug)]
struct CubicDrawSegment {
    start: DrawPoint,
    control1: DrawPoint,
    control2: DrawPoint,
    end: DrawPoint,
}

fn flatten_catmull_rom_draw_points(points: &[DrawPoint], stroke_width: f64) -> Vec<DrawPoint> {
    if points.is_empty() {
        return Vec::new();
    }
    if points.len() < 3 {
        return points.to_vec();
    }

    let step = stroke_width.max(1.0);
    let tolerance = 0.5_f64.max(step * 0.35);
    let tolerance_sq = tolerance * tolerance;

    let mut flattened = vec![points[0]];
    for index in 0..(points.len() - 1) {
        if flattened.len() >= LineHitTester::CATMULL_ROM_MAX_POINTS {
            break;
        }
        let segment = build_catmull_rom_cubic_segment(
            points,
            index,
            LineHitTester::CATMULL_ROM_TENSION,
            None,
            None,
        );
        flatten_cubic_segment(
            segment,
            tolerance_sq,
            &mut flattened,
            LineHitTester::CATMULL_ROM_MAX_POINTS,
        );
    }

    flattened
}

fn build_catmull_rom_cubic_segment(
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

    CubicDrawSegment {
        start: p1,
        control1,
        control2,
        end: p2,
    }
}

fn flatten_cubic_segment(
    segment: CubicDrawSegment,
    tolerance_sq: f64,
    output: &mut Vec<DrawPoint>,
    max_points: usize,
) {
    let mut stack = vec![segment];
    while let Some(current) = stack.pop() {
        if output.len() >= max_points {
            break;
        }

        if is_cubic_flat_enough(current, tolerance_sq) || output.len() >= max_points - 1 {
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

fn split_cubic_segment(segment: CubicDrawSegment) -> (CubicDrawSegment, CubicDrawSegment) {
    let p01 = midpoint_draw_point(segment.start, segment.control1);
    let p12 = midpoint_draw_point(segment.control1, segment.control2);
    let p23 = midpoint_draw_point(segment.control2, segment.end);
    let p012 = midpoint_draw_point(p01, p12);
    let p123 = midpoint_draw_point(p12, p23);
    let p0123 = midpoint_draw_point(p012, p123);

    let left = CubicDrawSegment {
        start: segment.start,
        control1: p01,
        control2: p012,
        end: p0123,
    };
    let right = CubicDrawSegment {
        start: p0123,
        control1: p123,
        control2: p23,
        end: segment.end,
    };
    (left, right)
}

fn midpoint_draw_point(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
}
