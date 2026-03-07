#![allow(dead_code)]

use std::sync::{LazyLock, Mutex};
use std::{
    collections::hash_map::DefaultHasher,
    hash::{Hash, Hasher},
};

use crate::draw::config::draw_config::ConfigDefaults;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::lru_cache::LruCache;

use super::free_draw_data::FreeDrawData;

/// Hit tester for free-draw elements.
///
/// Mirrors Dart `FreeDrawHitTester` behavior and uses typed free-draw payload
/// data for stroke/fill hit-testing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FreeDrawHitTester;

impl FreeDrawHitTester {
    const GEOMETRY_CACHE_LIMIT: usize = 256;

    /// Hit-tests a free-draw element with explicit free-draw payload data.
    pub fn hit_test_free_draw<D: FreeDrawLikeData + ?Sized>(
        &self,
        element: &FreeDrawHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        let rect = element.rect;
        let world_local_position = resolve_element_local_position(rect, element.rotation, position);
        let local_position = self.to_element_rect_local_position(world_local_position, rect);
        let local_rect = self.to_element_rect_local_bounds(rect);
        let points = element.data.points();

        if points.len() == 2 {
            if element.data.stroke_width() <= 0.0 {
                return false;
            }
            return self.hit_test_two_point_stroke_fast(
                local_rect,
                points,
                local_position,
                tolerance,
                element.data.stroke_width(),
            );
        }

        let has_stroke = element.data.stroke_width() > 0.0;
        let fill_opacity = (element.data.fill_alpha() * element.opacity).clamp(0.0, 1.0);
        let has_fill = fill_opacity > 0.0 && self.is_closed(points, rect);
        if !has_stroke && !has_fill {
            return false;
        }

        let geometry = self.resolve_geometry(element, points);
        if geometry.stroke_points.len() < 2 {
            return false;
        }

        if has_stroke
            && self.hit_test_stroke(
                local_rect,
                element.data.stroke_width(),
                local_position,
                tolerance,
                &geometry.flattened_stroke_points,
            )
        {
            return true;
        }

        if !has_fill
            || geometry.fill_outline.len() < 3
            || !is_point_inside_rect(local_rect, local_position, 0.0)
        {
            return false;
        }
        is_point_inside_polygon(local_position, &geometry.fill_outline, 1e-9)
    }

    fn resolve_geometry<D: FreeDrawLikeData + ?Sized>(
        &self,
        element: &FreeDrawHitTestElement<'_, D>,
        points: &[DrawPoint],
    ) -> FreeDrawHitGeometry {
        let rect = element.rect;
        let width = rect.width();
        let height = rect.height();
        let data_signature = free_draw_data_signature(element.data);
        let id = element.id;

        let mut cache = FREE_DRAW_HIT_GEOMETRY_CACHE
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(cached) = cache.get(&id.to_owned()) {
            if cached.matches(width, height, data_signature) {
                return cached.clone();
            }
        }

        let stroke_points = self.resolve_stroke_points(rect, points);
        let flattened_stroke_points = if stroke_points.len() < 2 {
            Vec::new()
        } else {
            self.resolve_flattened_stroke_points(&stroke_points, element.data.stroke_width())
        };
        let fill_outline = if flattened_stroke_points.len() < 3 {
            Vec::new()
        } else {
            self.resolve_closed_fill_outline_points_from_flattened(&flattened_stroke_points)
        };

        let resolved = FreeDrawHitGeometry {
            data_signature,
            width,
            height,
            stroke_points,
            flattened_stroke_points,
            fill_outline,
        };
        cache.put(id.to_owned(), resolved.clone());
        resolved
    }

    fn resolve_stroke_points(&self, rect: DrawRect, points: &[DrawPoint]) -> Vec<DrawPoint> {
        if points.is_empty() {
            return Vec::new();
        }

        let width = rect.width();
        let height = rect.height();
        if !width.is_finite() || !height.is_finite() || width < 0.0 || height < 0.0 {
            return Vec::new();
        }

        points
            .iter()
            .map(|point| {
                DrawPoint::with_pressure_and_timestamp(
                    point.x * width,
                    point.y * height,
                    point.pressure,
                    point.timestamp,
                )
            })
            .collect()
    }

    fn is_closed(&self, points: &[DrawPoint], rect: DrawRect) -> bool {
        if points.len() < 3 {
            return false;
        }

        let first = points[0];
        let last = points[points.len() - 1];
        if first == last {
            return true;
        }

        let close_tolerance =
            ConfigDefaults::HANDLE_TOLERANCE * ConfigDefaults::FREE_DRAW_CLOSE_TOLERANCE_MULTIPLIER;
        let dx = (first.x - last.x) * rect.width();
        let dy = (first.y - last.y) * rect.height();
        (dx * dx + dy * dy) <= close_tolerance * close_tolerance
    }

    fn to_element_rect_local_bounds(&self, rect: DrawRect) -> DrawRect {
        DrawRect::new(0.0, 0.0, rect.width(), rect.height())
    }

    fn to_element_rect_local_position(&self, position: DrawPoint, rect: DrawRect) -> DrawPoint {
        DrawPoint::with_pressure_and_timestamp(
            position.x - rect.min_x,
            position.y - rect.min_y,
            position.pressure,
            position.timestamp,
        )
    }

    fn hit_test_two_point_stroke_fast(
        &self,
        rect: DrawRect,
        points: &[DrawPoint],
        local_position: DrawPoint,
        tolerance: f64,
        stroke_width: f64,
    ) -> bool {
        hit_test_normalized_two_point_stroke(
            rect,
            points[0],
            points[points.len() - 1],
            local_position,
            stroke_width,
            tolerance,
        )
    }

    fn hit_test_stroke(
        &self,
        rect: DrawRect,
        stroke_width: f64,
        local_position: DrawPoint,
        tolerance: f64,
        flattened_stroke_points: &[DrawPoint],
    ) -> bool {
        let radius = (stroke_width / 2.0) + tolerance;
        if !radius.is_finite() || radius <= 0.0 {
            return false;
        }
        if !is_point_inside_rect(rect, local_position, radius) {
            return false;
        }
        if flattened_stroke_points.len() < 2 {
            return false;
        }

        let radius_sq = radius * radius;
        for index in 1..flattened_stroke_points.len() {
            let distance = distance_squared_to_segment(
                local_position,
                flattened_stroke_points[index - 1],
                flattened_stroke_points[index],
            );
            if distance <= radius_sq {
                return true;
            }
        }
        false
    }

    fn resolve_flattened_stroke_points(
        &self,
        stroke_points: &[DrawPoint],
        stroke_width: f64,
    ) -> Vec<DrawPoint> {
        if stroke_points.len() < 3 {
            return stroke_points.to_vec();
        }

        let closed = same_location(stroke_points[0], stroke_points[stroke_points.len() - 1]);
        let source = if closed && stroke_points.len() > 3 {
            stroke_points[..(stroke_points.len() - 1)].to_vec()
        } else {
            stroke_points.to_vec()
        };

        let flattened = flatten_catmull_rom_draw_points(&source, stroke_width, 1024, 0.5, !closed);

        if flattened.len() < 2 {
            return source;
        }
        if closed && !same_location(flattened[0], flattened[flattened.len() - 1]) {
            let mut closed_flattened = flattened;
            closed_flattened.push(closed_flattened[0]);
            return closed_flattened;
        }
        flattened
    }

    fn resolve_closed_fill_outline_points_from_flattened(
        &self,
        flattened: &[DrawPoint],
    ) -> Vec<DrawPoint> {
        if flattened.len() < 3 {
            return Vec::new();
        }

        let mut outline = Vec::with_capacity(flattened.len() + 1);
        let mut previous: Option<DrawPoint> = None;
        for point in flattened {
            if let Some(previous_point) = previous {
                if previous_point.x == point.x && previous_point.y == point.y {
                    continue;
                }
            }
            outline.push(*point);
            previous = Some(*point);
        }

        if outline.len() < 3 {
            return Vec::new();
        }

        let first = outline[0];
        let last = outline[outline.len() - 1];
        if first.x != last.x || first.y != last.y {
            outline.push(first);
        }
        outline
    }
}

impl ElementHitTester for FreeDrawHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        assert!(
            element.type_id().as_str() == FreeDrawData::TYPE_ID_TOKEN,
            "FreeDrawHitTester can only hit test FreeDrawData (got {})",
            element.type_id().as_str()
        );

        let data = FreeDrawData::from_json_value(&element.data.to_json_value())
            .expect("FreeDrawHitTester received invalid FreeDrawData payload");

        self.hit_test_free_draw(
            &FreeDrawHitTestElement {
                id: &element.id,
                rect: element.rect,
                rotation: element.rotation,
                opacity: element.opacity,
                data: &data,
            },
            position,
            tolerance,
        )
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

/// Free-draw-only snapshot used by [`FreeDrawHitTester::hit_test_free_draw`].
#[derive(Clone, Copy, Debug)]
pub struct FreeDrawHitTestElement<'a, D: FreeDrawLikeData + ?Sized> {
    pub id: &'a str,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub data: &'a D,
}

/// Shared payload contract for free-draw data.
pub trait FreeDrawLikeData {
    fn points(&self) -> &[DrawPoint];
    fn stroke_width(&self) -> f64;

    /// Normalized fill alpha in `[0, 1]`.
    fn fill_alpha(&self) -> f64;
}

impl FreeDrawLikeData for FreeDrawData {
    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn stroke_width(&self) -> f64 {
        self.stroke_width
    }

    fn fill_alpha(&self) -> f64 {
        self.fill_color.a()
    }
}

#[derive(Clone, Debug)]
struct FreeDrawHitGeometry {
    data_signature: u64,
    width: f64,
    height: f64,
    stroke_points: Vec<DrawPoint>,
    flattened_stroke_points: Vec<DrawPoint>,
    fill_outline: Vec<DrawPoint>,
}

impl FreeDrawHitGeometry {
    fn matches(&self, width: f64, height: f64, data_signature: u64) -> bool {
        self.width == width && self.height == height && self.data_signature == data_signature
    }
}

fn free_draw_data_signature<D: FreeDrawLikeData + ?Sized>(data: &D) -> u64 {
    let mut hasher = DefaultHasher::new();
    data.stroke_width().to_bits().hash(&mut hasher);
    data.fill_alpha().to_bits().hash(&mut hasher);
    data.points().len().hash(&mut hasher);
    for point in data.points() {
        point.x.to_bits().hash(&mut hasher);
        point.y.to_bits().hash(&mut hasher);
        point.pressure.to_bits().hash(&mut hasher);
        point.timestamp.hash(&mut hasher);
    }
    hasher.finish()
}

static FREE_DRAW_HIT_GEOMETRY_CACHE: LazyLock<Mutex<LruCache<String, FreeDrawHitGeometry>>> =
    LazyLock::new(|| Mutex::new(LruCache::new(FreeDrawHitTester::GEOMETRY_CACHE_LIMIT)));

fn same_location(a: DrawPoint, b: DrawPoint) -> bool {
    a.x == b.x && a.y == b.y
}

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
    DrawPoint::with_pressure_and_timestamp(
        center.x + (dx * cos - dy * sin),
        center.y + (dx * sin + dy * cos),
        point.pressure,
        point.timestamp,
    )
}

fn is_finite_draw_point(value: DrawPoint) -> bool {
    value.x.is_finite() && value.y.is_finite()
}

fn is_point_inside_rect(rect: DrawRect, position: DrawPoint, padding: f64) -> bool {
    position.x >= rect.min_x - padding
        && position.x <= rect.max_x + padding
        && position.y >= rect.min_y - padding
        && position.y <= rect.max_y + padding
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

#[derive(Clone, Copy, Debug)]
struct CubicDrawSegment {
    start: DrawPoint,
    control1: DrawPoint,
    control2: DrawPoint,
    end: DrawPoint,
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

fn flatten_catmull_rom_draw_points(
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
    let mut stack = vec![segment];
    while !stack.is_empty() && output.len() < max_points {
        let current = stack.pop().expect("stack is not empty");
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

fn split_cubic_segment(segment: CubicDrawSegment) -> (CubicDrawSegment, CubicDrawSegment) {
    let p01 = midpoint_draw_point(segment.start, segment.control1);
    let p12 = midpoint_draw_point(segment.control1, segment.control2);
    let p23 = midpoint_draw_point(segment.control2, segment.end);
    let p012 = midpoint_draw_point(p01, p12);
    let p123 = midpoint_draw_point(p12, p23);
    let p0123 = midpoint_draw_point(p012, p123);

    (
        CubicDrawSegment {
            start: segment.start,
            control1: p01,
            control2: p012,
            end: p0123,
        },
        CubicDrawSegment {
            start: p0123,
            control1: p123,
            control2: p23,
            end: segment.end,
        },
    )
}

fn midpoint_draw_point(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
}
