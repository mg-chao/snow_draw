#![allow(dead_code)]

use std::collections::{HashMap, VecDeque};
use std::sync::{LazyLock, Mutex};
use std::{
    collections::hash_map::DefaultHasher,
    hash::{Hash, Hasher},
};

use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

use super::arrow_data::ArrowData;

/// Hit tester for arrow-like elements.
///
/// Mirrors Dart `ArrowHitTester` behavior and accepts any arrow-like payload
/// (`ArrowData` and `LineData`) via [`ArrowLikeData`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ArrowHitTester;

impl ArrowHitTester {
    const CACHE_LIMIT: usize = 512;

    /// Hit-tests an arrow element with explicit arrow payload data.
    pub fn hit_test_arrow<D: ArrowLikeData + ?Sized>(
        &self,
        element: &ArrowHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        if element.data.stroke_width() <= 0.0 {
            return false;
        }

        let local_position =
            resolve_element_local_position(element.rect, element.rotation, position);
        let radius = (element.data.stroke_width() / 2.0) + tolerance;
        let bounds_padding = radius + arrowhead_extent(element.data);
        if !is_point_inside_rect(element.rect, local_position, bounds_padding) {
            return false;
        }

        let cache = resolve_cache(element);
        let test_point = DrawPoint::new(
            local_position.x - element.rect.min_x,
            local_position.y - element.rect.min_y,
        );

        let radius_sq = radius * radius;
        if hit_test_segments(&cache.shaft_points, test_point, radius_sq) {
            return true;
        }

        hit_test_arrowheads(&cache.arrowhead_targets, test_point, radius, radius_sq)
    }
}

impl ElementHitTester for ArrowHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        let type_id = element.type_id();
        let type_value = type_id.as_str();
        let payload = element.data.to_json_value();

        if type_value == ArrowData::TYPE_ID_TOKEN {
            let data = ArrowData::from_json_value(&payload)
                .expect("ArrowHitTester received invalid ArrowData payload");

            return self.hit_test_arrow(
                &ArrowHitTestElement {
                    id: &element.id,
                    rect: element.rect,
                    rotation: element.rotation,
                    data: &data,
                },
                position,
                tolerance,
            );
        }

        if type_value == LineData::TYPE_ID_TOKEN {
            let data = LineData::from_json_value(&payload)
                .expect("ArrowHitTester received invalid LineData payload");

            return self.hit_test_arrow(
                &ArrowHitTestElement {
                    id: &element.id,
                    rect: element.rect,
                    rotation: element.rotation,
                    data: &data,
                },
                position,
                tolerance,
            );
        }

        panic!(
            "ArrowHitTester can only hit test ArrowLikeData (got {})",
            type_value
        );
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

/// Arrow-only snapshot used by [`ArrowHitTester::hit_test_arrow`].
#[derive(Clone, Copy, Debug)]
pub struct ArrowHitTestElement<'a, D: ArrowLikeData + ?Sized> {
    pub id: &'a str,
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a D,
}

/// Shared payload contract for arrow-like data.
pub trait ArrowLikeData {
    fn points(&self) -> &[DrawPoint];
    fn stroke_width(&self) -> f64;
    fn arrow_type(&self) -> ArrowType;
    fn start_arrowhead(&self) -> ArrowheadStyle;
    fn end_arrowhead(&self) -> ArrowheadStyle;
}

impl ArrowLikeData for ArrowData {
    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn stroke_width(&self) -> f64 {
        self.stroke_width
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        self.start_arrowhead
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        self.end_arrowhead
    }
}

impl ArrowLikeData for LineData {
    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn stroke_width(&self) -> f64 {
        self.stroke_width
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        self.start_arrowhead
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        self.end_arrowhead
    }
}

#[derive(Clone, Debug)]
struct ArrowHitTestCacheEntry {
    width: f64,
    height: f64,
    data_signature: u64,
    shaft_points: Vec<DrawPoint>,
    arrowhead_targets: Vec<ArrowheadHitTarget>,
}

impl ArrowHitTestCacheEntry {
    fn matches(&self, width: f64, height: f64, data_signature: u64) -> bool {
        self.width == width && self.height == height && self.data_signature == data_signature
    }

    fn build<D: ArrowLikeData + ?Sized>(
        element: &ArrowHitTestElement<'_, D>,
        data_signature: u64,
    ) -> Self {
        let geometry = ArrowGeometryDescriptor::new(element.data, element.rect);
        let points = geometry.local_draw_points.clone();
        let has_curved_shaft = element.data.arrow_type() == ArrowType::Curved && points.len() > 2;
        let shaft_points = if has_curved_shaft {
            flatten_catmull_rom_draw_points(&points, element.data.stroke_width())
        } else {
            points
        };

        let arrowhead_targets = build_arrowhead_targets(&geometry);

        Self {
            width: element.rect.width(),
            height: element.rect.height(),
            data_signature,
            shaft_points,
            arrowhead_targets,
        }
    }
}

#[derive(Default)]
struct ArrowHitTestCache {
    entries: HashMap<String, ArrowHitTestCacheEntry>,
    lru_order: VecDeque<String>,
}

impl ArrowHitTestCache {
    fn get(&mut self, id: &str) -> Option<ArrowHitTestCacheEntry> {
        let entry = self.entries.get(id).cloned()?;
        self.touch(id);
        Some(entry)
    }

    fn put(&mut self, id: String, entry: ArrowHitTestCacheEntry) {
        if self.entries.contains_key(&id) {
            self.entries.insert(id.clone(), entry);
            self.touch(&id);
            return;
        }

        self.entries.insert(id.clone(), entry);
        self.lru_order.push_back(id);
        self.trim_to_limit();
    }

    fn touch(&mut self, id: &str) {
        if let Some(index) = self.lru_order.iter().position(|value| value == id) {
            self.lru_order.remove(index);
        }
        self.lru_order.push_back(id.to_owned());
    }

    fn trim_to_limit(&mut self) {
        while self.entries.len() > ArrowHitTester::CACHE_LIMIT {
            let Some(evict_id) = self.lru_order.pop_front() else {
                break;
            };
            self.entries.remove(&evict_id);
        }
    }
}

static HIT_TEST_CACHE: LazyLock<Mutex<ArrowHitTestCache>> =
    LazyLock::new(|| Mutex::new(ArrowHitTestCache::default()));

fn resolve_cache<D: ArrowLikeData + ?Sized>(
    element: &ArrowHitTestElement<'_, D>,
) -> ArrowHitTestCacheEntry {
    let id = element.id;
    let rect = element.rect;
    let width = rect.width();
    let height = rect.height();
    let data_signature = arrow_data_signature(element.data);

    let mut cache = HIT_TEST_CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    if let Some(cached) = cache.get(id) {
        if cached.matches(width, height, data_signature) {
            return cached;
        }
    }

    let next = ArrowHitTestCacheEntry::build(element, data_signature);
    cache.put(id.to_owned(), next.clone());
    next
}

fn arrow_data_signature<D: ArrowLikeData + ?Sized>(data: &D) -> u64 {
    let mut hasher = DefaultHasher::new();
    data.stroke_width().to_bits().hash(&mut hasher);
    match data.arrow_type() {
        ArrowType::Straight => 0_u8.hash(&mut hasher),
        ArrowType::Curved => 1_u8.hash(&mut hasher),
        ArrowType::Elbow => 2_u8.hash(&mut hasher),
    }
    match data.start_arrowhead() {
        ArrowheadStyle::None => 0_u8.hash(&mut hasher),
        ArrowheadStyle::Standard => 1_u8.hash(&mut hasher),
        ArrowheadStyle::Triangle => 2_u8.hash(&mut hasher),
        ArrowheadStyle::TriangleOutline => 3_u8.hash(&mut hasher),
        ArrowheadStyle::Square => 4_u8.hash(&mut hasher),
        ArrowheadStyle::Dot => 5_u8.hash(&mut hasher),
        ArrowheadStyle::Circle => 6_u8.hash(&mut hasher),
        ArrowheadStyle::CircleOutline => 7_u8.hash(&mut hasher),
        ArrowheadStyle::Diamond => 8_u8.hash(&mut hasher),
        ArrowheadStyle::DiamondOutline => 9_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootOne => 10_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootMany => 11_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootOneOrMany => 12_u8.hash(&mut hasher),
        ArrowheadStyle::InvertedTriangle => 13_u8.hash(&mut hasher),
        ArrowheadStyle::VerticalLine => 14_u8.hash(&mut hasher),
    }
    match data.end_arrowhead() {
        ArrowheadStyle::None => 0_u8.hash(&mut hasher),
        ArrowheadStyle::Standard => 1_u8.hash(&mut hasher),
        ArrowheadStyle::Triangle => 2_u8.hash(&mut hasher),
        ArrowheadStyle::TriangleOutline => 3_u8.hash(&mut hasher),
        ArrowheadStyle::Square => 4_u8.hash(&mut hasher),
        ArrowheadStyle::Dot => 5_u8.hash(&mut hasher),
        ArrowheadStyle::Circle => 6_u8.hash(&mut hasher),
        ArrowheadStyle::CircleOutline => 7_u8.hash(&mut hasher),
        ArrowheadStyle::Diamond => 8_u8.hash(&mut hasher),
        ArrowheadStyle::DiamondOutline => 9_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootOne => 10_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootMany => 11_u8.hash(&mut hasher),
        ArrowheadStyle::CrowfootOneOrMany => 12_u8.hash(&mut hasher),
        ArrowheadStyle::InvertedTriangle => 13_u8.hash(&mut hasher),
        ArrowheadStyle::VerticalLine => 14_u8.hash(&mut hasher),
    }
    data.points().len().hash(&mut hasher);
    for point in data.points() {
        point.x.to_bits().hash(&mut hasher);
        point.y.to_bits().hash(&mut hasher);
        point.pressure.to_bits().hash(&mut hasher);
        point.timestamp.hash(&mut hasher);
    }
    hasher.finish()
}

fn hit_test_segments(points: &[DrawPoint], position: DrawPoint, radius_sq: f64) -> bool {
    for index in 1..points.len() {
        let distance = distance_squared_to_segment(position, points[index - 1], points[index]);
        if distance <= radius_sq {
            return true;
        }
    }
    false
}

fn hit_test_arrowheads(
    targets: &[ArrowheadHitTarget],
    position: DrawPoint,
    radius: f64,
    radius_sq: f64,
) -> bool {
    targets
        .iter()
        .any(|target| target.hit_test(position, radius, radius_sq))
}

#[derive(Clone, Copy, Debug)]
struct ArrowheadSegment {
    start: DrawPoint,
    end: DrawPoint,
}

#[derive(Clone, Debug)]
enum ArrowheadHitTarget {
    Segments(Vec<ArrowheadSegment>),
    Circle { center: DrawPoint, radius: f64 },
}

impl ArrowheadHitTarget {
    fn hit_test(&self, position: DrawPoint, tolerance: f64, radius_sq: f64) -> bool {
        match self {
            Self::Segments(segments) => segments.iter().any(|segment| {
                distance_squared_to_segment(position, segment.start, segment.end) <= radius_sq
            }),
            Self::Circle { center, radius } => {
                let dx = position.x - center.x;
                let dy = position.y - center.y;
                let distance_sq = dx * dx + dy * dy;
                let min = (radius - tolerance).max(0.0);
                let max = radius + tolerance;
                distance_sq >= min * min && distance_sq <= max * max
            }
        }
    }
}

fn arrowhead_extent<D: ArrowLikeData + ?Sized>(data: &D) -> f64 {
    let has_arrowhead = data.start_arrowhead() != ArrowheadStyle::None
        || data.end_arrowhead() != ArrowheadStyle::None;
    if !has_arrowhead {
        return 0.0;
    }
    let length = arrowhead_length(data.stroke_width());
    length * 0.3
}

fn arrowhead_length(stroke_width: f64) -> f64 {
    stroke_width * 4.0 + 12.0
}

fn build_arrowhead_targets<D: ArrowLikeData + ?Sized>(
    geometry: &ArrowGeometryDescriptor<'_, D>,
) -> Vec<ArrowheadHitTarget> {
    let points = &geometry.local_draw_points;
    let data = geometry.data;
    let mut targets = Vec::new();

    if let Some(start_direction) = geometry.start_direction_point {
        if data.start_arrowhead() != ArrowheadStyle::None {
            if let Some(target) = arrowhead_target_for_style(
                points.first().copied().unwrap_or(DrawPoint::ZERO),
                start_direction,
                data.start_arrowhead(),
                data.stroke_width(),
            ) {
                targets.push(target);
            }
        }
    }

    if let Some(end_direction) = geometry.end_direction_point {
        if data.end_arrowhead() != ArrowheadStyle::None {
            if let Some(target) = arrowhead_target_for_style(
                points.last().copied().unwrap_or(DrawPoint::ZERO),
                end_direction,
                data.end_arrowhead(),
                data.stroke_width(),
            ) {
                targets.push(target);
            }
        }
    }

    targets
}

fn arrowhead_target_for_style(
    tip: DrawPoint,
    direction: DrawPoint,
    style: ArrowheadStyle,
    stroke_width: f64,
) -> Option<ArrowheadHitTarget> {
    let mut dir = normalize_draw_vector(direction)?;
    let length = arrowhead_length(stroke_width);
    let width = length * 0.6;

    if style == ArrowheadStyle::InvertedTriangle {
        dir = -dir;
    }

    let perp = DrawPoint::new(-dir.y, dir.x);

    match style {
        ArrowheadStyle::Standard => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            Some(ArrowheadHitTarget::Segments(vec![
                ArrowheadSegment {
                    start: tip,
                    end: left,
                },
                ArrowheadSegment {
                    start: tip,
                    end: right,
                },
            ]))
        }
        ArrowheadStyle::Triangle
        | ArrowheadStyle::TriangleOutline
        | ArrowheadStyle::InvertedTriangle => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            Some(ArrowheadHitTarget::Segments(closed_segments(&[
                tip, left, right,
            ])))
        }
        ArrowheadStyle::Square => {
            let side = length * 0.6;
            let half = side / 2.0;
            let center = subtract_scaled_draw_point(tip, dir, half);
            let corner1 = add_draw_points(
                add_scaled_draw_point(center, perp, half),
                add_scaled_draw_point(DrawPoint::ZERO, dir, half),
            );
            let corner2 = add_draw_points(
                add_scaled_draw_point(center, perp, -half),
                add_scaled_draw_point(DrawPoint::ZERO, dir, half),
            );
            let corner3 = add_draw_points(
                add_scaled_draw_point(center, perp, -half),
                add_scaled_draw_point(DrawPoint::ZERO, dir, -half),
            );
            let corner4 = add_draw_points(
                add_scaled_draw_point(center, perp, half),
                add_scaled_draw_point(DrawPoint::ZERO, dir, -half),
            );
            Some(ArrowheadHitTarget::Segments(closed_segments(&[
                corner1, corner2, corner3, corner4,
            ])))
        }
        ArrowheadStyle::Dot | ArrowheadStyle::Circle | ArrowheadStyle::CircleOutline => {
            let radius = length * 0.3;
            let center = subtract_scaled_draw_point(tip, dir, radius);
            Some(ArrowheadHitTarget::Circle { center, radius })
        }
        ArrowheadStyle::Diamond | ArrowheadStyle::DiamondOutline => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let mid = subtract_scaled_draw_point(tip, dir, length / 2.0);
            let left = add_scaled_draw_point(mid, perp, width / 2.0);
            let right = add_scaled_draw_point(mid, perp, -width / 2.0);
            Some(ArrowheadHitTarget::Segments(closed_segments(&[
                tip, left, base, right,
            ])))
        }
        ArrowheadStyle::CrowfootOne => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            Some(ArrowheadHitTarget::Segments(vec![ArrowheadSegment {
                start: left,
                end: right,
            }]))
        }
        ArrowheadStyle::CrowfootMany | ArrowheadStyle::CrowfootOneOrMany => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            let mut segments = vec![
                ArrowheadSegment {
                    start: tip,
                    end: left,
                },
                ArrowheadSegment {
                    start: tip,
                    end: right,
                },
            ];
            if style == ArrowheadStyle::CrowfootOneOrMany {
                segments.push(ArrowheadSegment {
                    start: left,
                    end: right,
                });
            }
            Some(ArrowheadHitTarget::Segments(segments))
        }
        ArrowheadStyle::VerticalLine => {
            let half = width / 2.0;
            let left = add_scaled_draw_point(tip, perp, half);
            let right = add_scaled_draw_point(tip, perp, -half);
            Some(ArrowheadHitTarget::Segments(vec![ArrowheadSegment {
                start: left,
                end: right,
            }]))
        }
        ArrowheadStyle::None => None,
    }
}

fn closed_segments(vertices: &[DrawPoint]) -> Vec<ArrowheadSegment> {
    let mut segments = Vec::with_capacity(vertices.len());
    for index in 0..vertices.len() {
        let next = vertices[(index + 1) % vertices.len()];
        segments.push(ArrowheadSegment {
            start: vertices[index],
            end: next,
        });
    }
    segments
}

#[derive(Clone, Copy, Debug)]
struct CubicDrawSegment {
    start: DrawPoint,
    control1: DrawPoint,
    control2: DrawPoint,
    end: DrawPoint,
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

fn add_draw_points(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new(a.x + b.x, a.y + b.y)
}

fn add_scaled_draw_point(a: DrawPoint, direction: DrawPoint, scale: f64) -> DrawPoint {
    DrawPoint::new(a.x + direction.x * scale, a.y + direction.y * scale)
}

fn subtract_scaled_draw_point(a: DrawPoint, direction: DrawPoint, scale: f64) -> DrawPoint {
    DrawPoint::new(a.x - direction.x * scale, a.y - direction.y * scale)
}

fn midpoint_draw_point(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
}

fn normalize_draw_vector(value: DrawPoint) -> Option<DrawPoint> {
    let length = (value.x * value.x + value.y * value.y).sqrt();
    if length == 0.0 {
        return None;
    }
    Some(DrawPoint::new(value.x / length, value.y / length))
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

fn flatten_catmull_rom_draw_points(points: &[DrawPoint], stroke_width: f64) -> Vec<DrawPoint> {
    const MAX_POINTS: usize = 120;
    const TENSION: f64 = 1.0;

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
        if flattened.len() >= MAX_POINTS {
            break;
        }
        let segment = build_catmull_rom_cubic_segment(points, index, TENSION, None, None);
        flatten_cubic_segment(segment, tolerance_sq, &mut flattened, MAX_POINTS);
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

#[derive(Clone, Debug)]
struct ArrowGeometryDescriptor<'a, D: ArrowLikeData + ?Sized> {
    data: &'a D,
    local_draw_points: Vec<DrawPoint>,
    start_direction_point: Option<DrawPoint>,
    end_direction_point: Option<DrawPoint>,
}

impl<'a, D: ArrowLikeData + ?Sized> ArrowGeometryDescriptor<'a, D> {
    fn new(data: &'a D, rect: DrawRect) -> Self {
        let local_draw_points = resolve_local_points(rect, data.points());
        let start_inset = calculate_arrowhead_inset(data.start_arrowhead(), data.stroke_width());
        let end_inset = calculate_arrowhead_inset(data.end_arrowhead(), data.stroke_width());
        let start_direction_offset =
            calculate_arrowhead_direction_offset(data.start_arrowhead(), data.stroke_width());
        let end_direction_offset =
            calculate_arrowhead_direction_offset(data.end_arrowhead(), data.stroke_width());

        let start_direction_point = resolve_start_direction(
            &local_draw_points,
            data.arrow_type(),
            start_inset,
            end_inset,
            start_direction_offset,
        );
        let end_direction_point = resolve_end_direction(
            &local_draw_points,
            data.arrow_type(),
            start_inset,
            end_inset,
            end_direction_offset,
        );

        Self {
            data,
            local_draw_points,
            start_direction_point,
            end_direction_point,
        }
    }
}

fn resolve_local_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
    let points = ensure_min_points(normalized_points);
    let width = rect.width();
    let height = rect.height();
    points
        .into_iter()
        .map(|point| DrawPoint::new(point.x * width, point.y * height))
        .collect()
}

fn ensure_min_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() >= 2 {
        return points.to_vec();
    }
    if points.is_empty() {
        return vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];
    }
    vec![points[0], points[0]]
}

fn calculate_arrowhead_inset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
    if stroke_width <= 0.0 {
        return 0.0;
    }

    let length = arrowhead_length(stroke_width);
    match style {
        ArrowheadStyle::Dot | ArrowheadStyle::Circle | ArrowheadStyle::CircleOutline => {
            length * 0.6
        }
        ArrowheadStyle::Square => length * 0.6,
        ArrowheadStyle::Triangle
        | ArrowheadStyle::TriangleOutline
        | ArrowheadStyle::Diamond
        | ArrowheadStyle::DiamondOutline => length,
        ArrowheadStyle::InvertedTriangle
        | ArrowheadStyle::Standard
        | ArrowheadStyle::CrowfootOne
        | ArrowheadStyle::CrowfootMany
        | ArrowheadStyle::CrowfootOneOrMany
        | ArrowheadStyle::VerticalLine
        | ArrowheadStyle::None => 0.0,
    }
}

fn calculate_arrowhead_direction_offset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
    if stroke_width <= 0.0 {
        return 0.0;
    }

    let length = arrowhead_length(stroke_width);
    match style {
        ArrowheadStyle::Dot
        | ArrowheadStyle::Circle
        | ArrowheadStyle::CircleOutline
        | ArrowheadStyle::Square
        | ArrowheadStyle::VerticalLine => length * 0.6,
        ArrowheadStyle::Standard
        | ArrowheadStyle::Triangle
        | ArrowheadStyle::TriangleOutline
        | ArrowheadStyle::Diamond
        | ArrowheadStyle::DiamondOutline
        | ArrowheadStyle::CrowfootOne
        | ArrowheadStyle::CrowfootMany
        | ArrowheadStyle::CrowfootOneOrMany
        | ArrowheadStyle::InvertedTriangle => length,
        ArrowheadStyle::None => 0.0,
    }
}

fn resolve_start_direction(
    points: &[DrawPoint],
    arrow_type: ArrowType,
    start_inset: f64,
    end_inset: f64,
    direction_offset: f64,
) -> Option<DrawPoint> {
    if points.len() < 2 {
        return None;
    }

    let has_insets = start_inset > 0.0 || end_inset > 0.0;
    let working_points = if has_insets {
        apply_insets(points, start_inset, end_inset)
    } else {
        points.to_vec()
    };

    if working_points.len() < 2 {
        return None;
    }

    if arrow_type == ArrowType::Curved && working_points.len() > 2 {
        let effective_offset = (direction_offset - start_inset).max(0.0);
        if let Some(direction) =
            CurvedPathAnalysis::new(&working_points).direction_from_start(effective_offset)
        {
            return Some(-direction);
        }
    }

    normalize_draw_vector(working_points[0] - working_points[1])
}

fn resolve_end_direction(
    points: &[DrawPoint],
    arrow_type: ArrowType,
    start_inset: f64,
    end_inset: f64,
    direction_offset: f64,
) -> Option<DrawPoint> {
    if points.len() < 2 {
        return None;
    }

    let has_insets = start_inset > 0.0 || end_inset > 0.0;
    let working_points = if has_insets {
        apply_insets(points, start_inset, end_inset)
    } else {
        points.to_vec()
    };

    if working_points.len() < 2 {
        return None;
    }

    if arrow_type == ArrowType::Curved && working_points.len() > 2 {
        let effective_offset = (direction_offset - end_inset).max(0.0);
        if let Some(direction) =
            CurvedPathAnalysis::new(&working_points).direction_from_end(effective_offset)
        {
            return Some(direction);
        }
    }

    let last = working_points.len() - 1;
    normalize_draw_vector(working_points[last] - working_points[last - 1])
}

fn apply_insets(points: &[DrawPoint], start_inset: f64, end_inset: f64) -> Vec<DrawPoint> {
    if points.len() < 2 {
        return points.to_vec();
    }

    let mut adjusted = points.to_vec();
    if start_inset > 0.0 {
        adjusted = inset_from_start(&adjusted, start_inset);
        if adjusted.len() < 2 {
            return adjusted;
        }
    }

    if end_inset > 0.0 {
        adjusted = inset_from_end(&adjusted, end_inset);
    }

    adjusted
}

fn inset_from_start(points: &[DrawPoint], inset: f64) -> Vec<DrawPoint> {
    if points.len() < 2 || inset <= 0.0 {
        return points.to_vec();
    }

    let mut remaining_inset = inset;
    for index in 0..(points.len() - 1) {
        let segment_vector = points[index + 1] - points[index];
        let segment_length = segment_vector.distance(DrawPoint::ZERO);
        if segment_length <= 0.0 {
            continue;
        }

        if remaining_inset < segment_length {
            let direction = segment_vector / segment_length;
            let new_start = points[index] + direction * remaining_inset;
            let mut result = Vec::with_capacity(points.len() - index);
            result.push(new_start);
            result.extend_from_slice(&points[(index + 1)..]);
            return result;
        }

        remaining_inset -= segment_length;
    }

    vec![*points.last().unwrap_or(&DrawPoint::ZERO)]
}

fn inset_from_end(points: &[DrawPoint], inset: f64) -> Vec<DrawPoint> {
    if points.len() < 2 || inset <= 0.0 {
        return points.to_vec();
    }

    let mut remaining_inset = inset;
    for index in (1..points.len()).rev() {
        let segment_vector = points[index - 1] - points[index];
        let segment_length = segment_vector.distance(DrawPoint::ZERO);
        if segment_length <= 0.0 {
            continue;
        }

        if remaining_inset < segment_length {
            let direction = segment_vector / segment_length;
            let new_end = points[index] + direction * remaining_inset;
            let mut result = Vec::with_capacity(index + 1);
            result.extend_from_slice(&points[..index]);
            result.push(new_end);
            return result;
        }

        remaining_inset -= segment_length;
    }

    vec![points[0]]
}

#[derive(Clone, Debug)]
struct CurvedPathAnalysis {
    segments: Vec<CubicDrawSegment>,
    lengths: Vec<f64>,
}

impl CurvedPathAnalysis {
    fn new(points: &[DrawPoint]) -> Self {
        let mut segments = Vec::with_capacity(points.len().saturating_sub(1));
        let mut lengths = Vec::with_capacity(points.len().saturating_sub(1));

        for index in 0..points.len().saturating_sub(1) {
            let segment = build_cubic_segment(points, index);
            let length = approximate_cubic_length(segment);
            segments.push(segment);
            lengths.push(length);
        }

        Self { segments, lengths }
    }

    fn direction_from_start(&self, offset: f64) -> Option<DrawPoint> {
        if self.segments.is_empty() {
            return None;
        }

        let mut remaining = if offset.is_finite() {
            offset.max(0.0)
        } else {
            0.0
        };
        for index in 0..self.segments.len() {
            let length = self.lengths[index];
            if length <= 0.0 {
                continue;
            }
            if remaining <= length || index == self.segments.len() - 1 {
                let t = (remaining / length).clamp(0.0, 1.0);
                return normalize_draw_vector(cubic_tangent(self.segments[index], t));
            }
            remaining -= length;
        }

        None
    }

    fn direction_from_end(&self, offset: f64) -> Option<DrawPoint> {
        if self.segments.is_empty() {
            return None;
        }

        let mut remaining = if offset.is_finite() {
            offset.max(0.0)
        } else {
            0.0
        };
        for index in (0..self.segments.len()).rev() {
            let length = self.lengths[index];
            if length <= 0.0 {
                continue;
            }
            if remaining <= length || index == 0 {
                let t = (1.0 - (remaining / length)).clamp(0.0, 1.0);
                return normalize_draw_vector(cubic_tangent(self.segments[index], t));
            }
            remaining -= length;
        }

        None
    }
}

fn build_cubic_segment(points: &[DrawPoint], index: usize) -> CubicDrawSegment {
    let p0 = if index == 0 {
        points[index]
    } else {
        points[index - 1]
    };
    let p1 = points[index];
    let p2 = points[index + 1];
    let p3 = if index + 2 < points.len() {
        points[index + 2]
    } else {
        points[index + 1]
    };

    let tension = 1.0;
    let control1 = p1 + (p2 - p0) * (tension / 6.0);
    let control2 = p2 - (p3 - p1) * (tension / 6.0);
    CubicDrawSegment {
        start: p1,
        control1,
        control2,
        end: p2,
    }
}

fn approximate_cubic_length(segment: CubicDrawSegment) -> f64 {
    let mut length = 0.0;
    let mut previous = segment.start;
    const STEPS: usize = 8;
    for step in 1..=STEPS {
        let t = step as f64 / STEPS as f64;
        let point = evaluate_cubic(segment, t);
        length += (point - previous).distance(DrawPoint::ZERO);
        previous = point;
    }
    length
}

fn evaluate_cubic(segment: CubicDrawSegment, t: f64) -> DrawPoint {
    let mt = 1.0 - t;
    let mt2 = mt * mt;
    let t2 = t * t;
    let a = mt2 * mt;
    let b = 3.0 * mt2 * t;
    let c = 3.0 * mt * t2;
    let d = t2 * t;
    segment.start * a + segment.control1 * b + segment.control2 * c + segment.end * d
}

fn cubic_tangent(segment: CubicDrawSegment, t: f64) -> DrawPoint {
    let mt = 1.0 - t;
    let a = (segment.control1 - segment.start) * (3.0 * mt * mt);
    let b = (segment.control2 - segment.control1) * (6.0 * mt * t);
    let c = (segment.end - segment.control2) * (3.0 * t * t);
    a + b + c
}
