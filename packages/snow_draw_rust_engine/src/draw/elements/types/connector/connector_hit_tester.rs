#![allow(dead_code)]

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::{LazyLock, Mutex};

use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::arrow::arrow_render_primitives::{
    ArrowEndpointPosition, ArrowRenderPrimitives, ArrowheadPrimitiveFillMode,
    ArrowheadRenderPrimitiveData,
};
use crate::draw::elements::types::connector::connector_geometry::{
    ConnectorGeometry, ConnectorGeometryData, ConnectorGeometryDescriptor,
};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::shared::hit_test_geometry::{
    distance_squared_to_segment, is_point_inside_polygon, is_point_inside_rect,
    resolve_element_local_position,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle, StrokeStyle};
use crate::draw::utils::lru_cache::LruCache;

/// Minimal connector payload surface required by hit testing.
pub trait ConnectorHitTestData: ConnectorGeometryData + Clone {
    fn stroke_style(&self) -> StrokeStyle;
}

impl ConnectorHitTestData for ArrowData {
    fn stroke_style(&self) -> StrokeStyle {
        self.stroke_style
    }
}

impl ConnectorHitTestData for LineData {
    fn stroke_style(&self) -> StrokeStyle {
        self.stroke_style
    }
}

/// Connector-only element snapshot used by [`ConnectorHitTester`].
#[derive(Clone, Copy, Debug)]
pub struct ConnectorHitTestElement<'a, D: ConnectorHitTestData> {
    pub id: &'a str,
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a D,
}

/// Hit tester for connector-style elements.
///
/// Mirrors the newer Dart connector hit-testing path by sampling the visible
/// shaft geometry and hit-testing render primitives for arrowheads.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ConnectorHitTester;

impl ConnectorHitTester {
    const CACHE_LIMIT: usize = 512;
    const POLYGON_EPSILON: f64 = 1e-9;

    pub const fn new() -> Self {
        Self
    }

    pub fn hit_test_connector<D: ConnectorHitTestData>(
        &self,
        element: &ConnectorHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        if element.data.stroke_width() <= 0.0 {
            return false;
        }

        let local_position =
            resolve_element_local_position(element.rect, element.rotation, position);
        let rect = element.rect;
        let radius = (element.data.stroke_width() / 2.0) + tolerance;
        let bounds_padding = radius + arrowhead_extent(element.data);
        if !is_point_inside_rect(rect, local_position, bounds_padding) {
            return false;
        }

        let cache = resolve_cache(element);
        let test_point =
            DrawPoint::new(local_position.x - rect.min_x, local_position.y - rect.min_y);

        let radius_sq = radius * radius;
        if hit_test_segments(&cache.shaft_points, test_point, radius_sq) {
            return true;
        }

        hit_test_arrowheads(&cache.arrowhead_targets, test_point, radius, radius_sq)
    }
}

impl ElementHitTester for ConnectorHitTester {
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
                .expect("ConnectorHitTester received invalid ArrowData payload");
            return self.hit_test_connector(
                &ConnectorHitTestElement {
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
                .expect("ConnectorHitTester received invalid LineData payload");
            return self.hit_test_connector(
                &ConnectorHitTestElement {
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
            "ConnectorHitTester can only hit test connector-style data (got {})",
            type_value
        );
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

#[derive(Clone, Debug)]
struct ConnectorHitTestCacheEntry {
    width: f64,
    height: f64,
    data_signature: u64,
    shaft_points: Vec<DrawPoint>,
    arrowhead_targets: Vec<ArrowheadHitTarget>,
}

impl ConnectorHitTestCacheEntry {
    fn matches(&self, width: f64, height: f64, data_signature: u64) -> bool {
        self.width == width && self.height == height && self.data_signature == data_signature
    }

    fn build<D: ConnectorHitTestData>(
        element: &ConnectorHitTestElement<'_, D>,
        data_signature: u64,
    ) -> Self {
        let mut geometry = ConnectorGeometryDescriptor::new(element.data.clone(), element.rect);
        let shaft_points = ConnectorGeometry::sample_shaft_for_hit_test(
            geometry.inset_draw_points(),
            element.data.arrow_type(),
            element.data.stroke_width(),
        );
        let arrowhead_targets = build_arrowhead_targets(&mut geometry);

        Self {
            width: element.rect.width(),
            height: element.rect.height(),
            data_signature,
            shaft_points,
            arrowhead_targets,
        }
    }
}

static HIT_TEST_CACHE: LazyLock<Mutex<LruCache<String, ConnectorHitTestCacheEntry>>> =
    LazyLock::new(|| Mutex::new(LruCache::new(ConnectorHitTester::CACHE_LIMIT)));

fn resolve_cache<D: ConnectorHitTestData>(
    element: &ConnectorHitTestElement<'_, D>,
) -> ConnectorHitTestCacheEntry {
    let id = element.id;
    let id_key = id.to_owned();
    let rect = element.rect;
    let width = rect.width();
    let height = rect.height();
    let data_signature = connector_data_signature(element.data);

    let mut cache = HIT_TEST_CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(cached) = cache.get(&id_key).cloned() {
        if cached.matches(width, height, data_signature) {
            return cached;
        }
    }

    let next = ConnectorHitTestCacheEntry::build(element, data_signature);
    cache.put(id_key, next.clone());
    next
}

fn connector_data_signature<D: ConnectorHitTestData>(data: &D) -> u64 {
    let mut hasher = DefaultHasher::new();
    data.stroke_width().to_bits().hash(&mut hasher);
    stroke_style_discriminant(data.stroke_style()).hash(&mut hasher);
    arrow_type_discriminant(data.arrow_type()).hash(&mut hasher);
    arrowhead_style_discriminant(data.start_arrowhead()).hash(&mut hasher);
    arrowhead_style_discriminant(data.end_arrowhead()).hash(&mut hasher);
    data.points().len().hash(&mut hasher);
    for point in data.points() {
        point.x.to_bits().hash(&mut hasher);
        point.y.to_bits().hash(&mut hasher);
        point.pressure.to_bits().hash(&mut hasher);
        point.timestamp.hash(&mut hasher);
    }
    hasher.finish()
}

fn stroke_style_discriminant(style: StrokeStyle) -> u8 {
    match style {
        StrokeStyle::Solid => 0,
        StrokeStyle::Dashed => 1,
        StrokeStyle::Dotted => 2,
    }
}

fn arrow_type_discriminant(value: ArrowType) -> u8 {
    match value {
        ArrowType::Straight => 0,
        ArrowType::Curved => 1,
        ArrowType::Elbow => 2,
    }
}

fn arrowhead_style_discriminant(value: ArrowheadStyle) -> u8 {
    match value {
        ArrowheadStyle::None => 0,
        ArrowheadStyle::Standard => 1,
        ArrowheadStyle::Triangle => 2,
        ArrowheadStyle::TriangleOutline => 3,
        ArrowheadStyle::Square => 4,
        ArrowheadStyle::Dot => 5,
        ArrowheadStyle::Circle => 6,
        ArrowheadStyle::CircleOutline => 7,
        ArrowheadStyle::Diamond => 8,
        ArrowheadStyle::DiamondOutline => 9,
        ArrowheadStyle::CrowfootOne => 10,
        ArrowheadStyle::CrowfootMany => 11,
        ArrowheadStyle::CrowfootOneOrMany => 12,
        ArrowheadStyle::InvertedTriangle => 13,
        ArrowheadStyle::VerticalLine => 14,
    }
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
    Polygon {
        vertices: Vec<DrawPoint>,
        fill_mode: ArrowheadPrimitiveFillMode,
    },
    Circle {
        center: DrawPoint,
        radius: f64,
        fill_mode: ArrowheadPrimitiveFillMode,
    },
}

impl ArrowheadHitTarget {
    fn hit_test(&self, position: DrawPoint, tolerance: f64, radius_sq: f64) -> bool {
        match self {
            Self::Segments(segments) => segments.iter().any(|segment| {
                distance_squared_to_segment(position, segment.start, segment.end) <= radius_sq
            }),
            Self::Polygon {
                vertices,
                fill_mode,
            } => {
                if hit_test_segments(&polygon_outline(vertices), position, radius_sq) {
                    return true;
                }
                *fill_mode == ArrowheadPrimitiveFillMode::Stroke
                    && is_point_inside_polygon(
                        position,
                        vertices,
                        ConnectorHitTester::POLYGON_EPSILON,
                    )
            }
            Self::Circle {
                center,
                radius,
                fill_mode,
            } => {
                let dx = position.x - center.x;
                let dy = position.y - center.y;
                let distance_sq = dx * dx + dy * dy;
                let max = radius + tolerance;
                if *fill_mode == ArrowheadPrimitiveFillMode::Stroke {
                    return distance_sq <= max * max;
                }
                let min = (radius - tolerance).max(0.0);
                distance_sq >= min * min && distance_sq <= max * max
            }
        }
    }
}

fn arrowhead_extent<D: ConnectorHitTestData>(data: &D) -> f64 {
    let has_arrowhead = data.start_arrowhead() != ArrowheadStyle::None
        || data.end_arrowhead() != ArrowheadStyle::None;
    if !has_arrowhead {
        return 0.0;
    }
    let length = ConnectorGeometry::resolve_arrowhead_length(data.stroke_width());
    length * 0.3
}

fn build_arrowhead_targets<D: ConnectorHitTestData>(
    geometry: &mut ConnectorGeometryDescriptor<D>,
) -> Vec<ArrowheadHitTarget> {
    let data = geometry.data.clone();
    let points = geometry.local_draw_points().to_vec();
    let start_direction = geometry.start_direction_point();
    let end_direction = geometry.end_direction_point();

    let mut targets = Vec::new();
    if data.start_arrowhead() != ArrowheadStyle::None {
        let primitives = ArrowRenderPrimitives::resolve_arrowhead_primitives(
            &points,
            data.arrow_type(),
            data.start_arrowhead(),
            data.stroke_style(),
            data.stroke_width(),
            ArrowEndpointPosition::Start,
            start_direction,
        );
        for primitive in primitives {
            targets.push(primitive_to_target(primitive));
        }
    }

    if data.end_arrowhead() != ArrowheadStyle::None {
        let primitives = ArrowRenderPrimitives::resolve_arrowhead_primitives(
            &points,
            data.arrow_type(),
            data.end_arrowhead(),
            data.stroke_style(),
            data.stroke_width(),
            ArrowEndpointPosition::End,
            end_direction,
        );
        for primitive in primitives {
            targets.push(primitive_to_target(primitive));
        }
    }

    targets
}

fn primitive_to_target(primitive: ArrowheadRenderPrimitiveData) -> ArrowheadHitTarget {
    match primitive {
        ArrowheadRenderPrimitiveData::Line {
            from,
            to,
            dash_mode: _,
        } => ArrowheadHitTarget::Segments(vec![ArrowheadSegment {
            start: from,
            end: to,
        }]),
        ArrowheadRenderPrimitiveData::Polygon { points, fill_mode } => {
            ArrowheadHitTarget::Polygon {
                vertices: points,
                fill_mode,
            }
        }
        ArrowheadRenderPrimitiveData::Circle {
            center,
            radius,
            fill_mode,
        } => ArrowheadHitTarget::Circle {
            center,
            radius,
            fill_mode,
        },
    }
}

fn polygon_outline(vertices: &[DrawPoint]) -> Vec<DrawPoint> {
    if vertices.is_empty() {
        return Vec::new();
    }
    let mut outline = Vec::with_capacity(vertices.len() + 1);
    outline.extend_from_slice(vertices);
    outline.push(vertices[0]);
    outline
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::connector::connector_geometry::{
        ConnectorGeometry, ConnectorGeometryDescriptor,
    };

    fn straight_arrow_with_triangle() -> ArrowData {
        ArrowData {
            points: vec![DrawPoint::new(0.1, 0.5), DrawPoint::new(0.9, 0.5)],
            stroke_width: 4.0,
            end_arrowhead: ArrowheadStyle::Triangle,
            ..ArrowData::default()
        }
    }

    fn elbow_arrow() -> ArrowData {
        ArrowData {
            points: vec![
                DrawPoint::new(0.1, 0.1),
                DrawPoint::new(0.1, 0.9),
                DrawPoint::new(0.9, 0.9),
            ],
            stroke_width: 4.0,
            arrow_type: ArrowType::Elbow,
            ..ArrowData::default()
        }
    }

    #[test]
    fn connector_hit_tester_exposes_distinct_type() {
        let tester = ConnectorHitTester::new();
        let data = ArrowData::default();
        let element = ConnectorHitTestElement {
            id: "arrow",
            rect: DrawRect::new(0.0, 0.0, 100.0, 100.0),
            rotation: 0.0,
            data: &data,
        };

        assert!(!tester.hit_test_connector(&element, DrawPoint::new(200.0, 200.0), 1.0,));
    }

    #[test]
    fn connector_hit_tester_hits_triangle_arrowhead_interior() {
        let tester = ConnectorHitTester::new();
        let data = straight_arrow_with_triangle();
        let element = ConnectorHitTestElement {
            id: "arrow",
            rect: DrawRect::new(0.0, 0.0, 100.0, 100.0),
            rotation: 0.0,
            data: &data,
        };

        assert!(tester.hit_test_connector(&element, DrawPoint::new(74.0, 55.0), 0.0));
    }

    #[test]
    fn connector_hit_tester_hits_sampled_elbow_curve() {
        let tester = ConnectorHitTester::new();
        let data = elbow_arrow();
        let mut geometry =
            ConnectorGeometryDescriptor::new(data.clone(), DrawRect::new(0.0, 0.0, 100.0, 100.0));
        let sampled = ConnectorGeometry::sample_shaft_for_hit_test(
            geometry.inset_draw_points(),
            data.arrow_type,
            data.stroke_width,
        );
        let curve_point = sampled
            .iter()
            .copied()
            .find(|point| point.x > 10.0 && point.x < 30.0 && point.y > 70.0 && point.y < 90.0)
            .unwrap_or_else(|| sampled[sampled.len() / 2]);
        let element = ConnectorHitTestElement {
            id: "arrow",
            rect: DrawRect::new(0.0, 0.0, 100.0, 100.0),
            rotation: 0.0,
            data: &data,
        };

        assert!(sampled.len() > data.points.len());
        assert!(tester.hit_test_connector(&element, curve_point, 1.0));
    }
}
