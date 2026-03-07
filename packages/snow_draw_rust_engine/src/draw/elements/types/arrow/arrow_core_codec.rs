#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::ArrowheadStyle;
use serde_json::{Map, Value};

use super::arrow_binding::ArrowBinding;
use super::core::arrow_types::{Arrowhead, Point};

/// Encodes an engine point into an arrow-core point tuple.
pub const fn encode_arrow_core_point(point: DrawPoint) -> Point {
    point
}

/// Encodes engine points into arrow-core point tuples.
pub fn encode_arrow_core_points<I>(points: I) -> Vec<Point>
where
    I: IntoIterator<Item = DrawPoint>,
{
    points.into_iter().map(encode_arrow_core_point).collect()
}

/// Decodes an arrow-core point tuple into an engine point.
pub const fn decode_arrow_core_point(point: Point) -> DrawPoint {
    point
}

/// Decodes arrow-core point tuples into engine points.
pub fn decode_arrow_core_points<I>(points: I) -> Vec<DrawPoint>
where
    I: IntoIterator<Item = Point>,
{
    points.into_iter().map(decode_arrow_core_point).collect()
}

/// Encodes engine arrowhead styles into arrow-core arrowhead ids.
pub const fn encode_arrow_core_arrowhead(style: ArrowheadStyle) -> Option<Arrowhead> {
    match style {
        ArrowheadStyle::None => None,
        ArrowheadStyle::Standard => Some("arrow"),
        ArrowheadStyle::Triangle => Some("triangle"),
        ArrowheadStyle::TriangleOutline => Some("triangle_outline"),
        ArrowheadStyle::Square => Some("square"),
        ArrowheadStyle::Dot => Some("dot"),
        ArrowheadStyle::Circle => Some("circle"),
        ArrowheadStyle::CircleOutline => Some("circle_outline"),
        ArrowheadStyle::Diamond => Some("diamond"),
        ArrowheadStyle::DiamondOutline => Some("diamond_outline"),
        ArrowheadStyle::CrowfootOne => Some("crowfoot_one"),
        ArrowheadStyle::CrowfootMany => Some("crowfoot_many"),
        ArrowheadStyle::CrowfootOneOrMany => Some("crowfoot_one_or_many"),
        ArrowheadStyle::InvertedTriangle => Some("inverted_triangle"),
        ArrowheadStyle::VerticalLine => Some("bar"),
    }
}

/// Encodes a core point payload.
pub fn encode_core_point(point: DrawPoint) -> Value {
    serde_json::json!({"x": point.x, "y": point.y, "pressure": point.pressure})
}

/// Decodes a core point payload.
pub fn decode_core_point(value: &Value) -> Option<DrawPoint> {
    let json = value.as_object()?;
    Some(DrawPoint::new(
        json.get("x")?.as_f64()?,
        json.get("y")?.as_f64()?,
    ))
}

/// Encodes a core binding payload.
pub fn encode_core_binding(binding: &ArrowBinding) -> Value {
    binding.to_json()
}

/// Decodes a core binding payload.
pub fn decode_core_binding(value: &Value) -> Option<ArrowBinding> {
    ArrowBinding::from_json(value).ok()
}

/// Copies an object map while preserving insertion-order semantics from serde.
pub fn clone_object_map(map: &Map<String, Value>) -> Map<String, Value> {
    map.clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_point_tuple_helpers_round_trip() {
        let points = vec![DrawPoint::new(1.0, 2.0), DrawPoint::new(3.0, 4.0)];

        let encoded = encode_arrow_core_points(points.clone());
        let decoded = decode_arrow_core_points(encoded.clone());

        assert_eq!(encoded, points);
        assert_eq!(decoded, points);
    }

    #[test]
    fn arrowhead_encoding_matches_dart_names() {
        assert_eq!(encode_arrow_core_arrowhead(ArrowheadStyle::None), None);
        assert_eq!(
            encode_arrow_core_arrowhead(ArrowheadStyle::TriangleOutline),
            Some("triangle_outline")
        );
        assert_eq!(
            encode_arrow_core_arrowhead(ArrowheadStyle::CrowfootOneOrMany),
            Some("crowfoot_one_or_many")
        );
        assert_eq!(
            encode_arrow_core_arrowhead(ArrowheadStyle::VerticalLine),
            Some("bar")
        );
    }
}
