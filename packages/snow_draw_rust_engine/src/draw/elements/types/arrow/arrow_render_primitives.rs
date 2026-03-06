#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle, StrokeStyle};

/// Endpoint position for arrowhead primitive resolution.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowEndpointPosition {
    Start,
    End,
}

/// Fill mode attached to a render primitive.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowheadPrimitiveFillMode {
    None,
    Stroke,
    Background,
}

/// Dash semantics attached to a line primitive.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowheadPrimitiveDashMode {
    Solid,
    Inherit,
    DottedCap,
}

/// Engine-friendly render primitive descriptor for arrowheads.
#[derive(Clone, Debug, PartialEq)]
pub enum ArrowheadRenderPrimitiveData {
    Line {
        from: DrawPoint,
        to: DrawPoint,
        dash_mode: ArrowheadPrimitiveDashMode,
    },
    Polygon {
        points: Vec<DrawPoint>,
        fill_mode: ArrowheadPrimitiveFillMode,
    },
    Circle {
        center: DrawPoint,
        radius: f64,
        fill_mode: ArrowheadPrimitiveFillMode,
    },
}

/// Render-ready connector shaft primitives.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowRenderPrimitives {
    pub shaft_points: Vec<DrawPoint>,
}

impl ArrowRenderPrimitives {
    /// Builds render primitives for a single endpoint arrowhead.
    pub fn resolve_arrowhead_primitives(
        points: &[DrawPoint],
        _arrow_type: ArrowType,
        style: ArrowheadStyle,
        stroke_style: StrokeStyle,
        stroke_width: f64,
        position: ArrowEndpointPosition,
        direction_override: Option<DrawPoint>,
    ) -> Vec<ArrowheadRenderPrimitiveData> {
        if style == ArrowheadStyle::None || stroke_width <= 0.0 || points.len() < 2 {
            return Vec::new();
        }

        let (tip, direction) = match position {
            ArrowEndpointPosition::Start => (
                points[0],
                direction_override.unwrap_or(points[0] - points[1]),
            ),
            ArrowEndpointPosition::End => {
                let last = points.len() - 1;
                (
                    points[last],
                    direction_override.unwrap_or(points[last] - points[last - 1]),
                )
            }
        };

        build_arrowhead_primitives(tip, direction, style, stroke_style, stroke_width)
    }
}

fn build_arrowhead_primitives(
    tip: DrawPoint,
    direction: DrawPoint,
    style: ArrowheadStyle,
    stroke_style: StrokeStyle,
    stroke_width: f64,
) -> Vec<ArrowheadRenderPrimitiveData> {
    let Some(mut dir) = normalize_draw_vector(direction) else {
        return Vec::new();
    };
    let length = arrowhead_length(stroke_width);
    let width = length * 0.6;

    if style == ArrowheadStyle::InvertedTriangle {
        dir = -dir;
    }

    let perp = DrawPoint::new(-dir.y, dir.x);
    let line_dash_mode = match stroke_style {
        StrokeStyle::Dotted => ArrowheadPrimitiveDashMode::DottedCap,
        StrokeStyle::Dashed => ArrowheadPrimitiveDashMode::Inherit,
        StrokeStyle::Solid => ArrowheadPrimitiveDashMode::Solid,
    };

    match style {
        ArrowheadStyle::Standard => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            vec![
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: left,
                    dash_mode: line_dash_mode,
                },
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: right,
                    dash_mode: line_dash_mode,
                },
            ]
        }
        ArrowheadStyle::Triangle => polygon_primitive(
            triangle_vertices(tip, dir, perp, length, width),
            ArrowheadPrimitiveFillMode::Stroke,
        ),
        ArrowheadStyle::TriangleOutline => polygon_primitive(
            triangle_vertices(tip, dir, perp, length, width),
            ArrowheadPrimitiveFillMode::None,
        ),
        ArrowheadStyle::InvertedTriangle => polygon_primitive(
            triangle_vertices(tip, dir, perp, length, width),
            ArrowheadPrimitiveFillMode::Stroke,
        ),
        ArrowheadStyle::Square => {
            let side = length * 0.6;
            let half = side / 2.0;
            let center = subtract_scaled_draw_point(tip, dir, half);
            let corners = vec![
                add_draw_points(
                    add_scaled_draw_point(center, perp, half),
                    add_scaled_draw_point(DrawPoint::ZERO, dir, half),
                ),
                add_draw_points(
                    add_scaled_draw_point(center, perp, -half),
                    add_scaled_draw_point(DrawPoint::ZERO, dir, half),
                ),
                add_draw_points(
                    add_scaled_draw_point(center, perp, -half),
                    add_scaled_draw_point(DrawPoint::ZERO, dir, -half),
                ),
                add_draw_points(
                    add_scaled_draw_point(center, perp, half),
                    add_scaled_draw_point(DrawPoint::ZERO, dir, -half),
                ),
            ];
            polygon_primitive(corners, ArrowheadPrimitiveFillMode::Stroke)
        }
        ArrowheadStyle::Dot => vec![ArrowheadRenderPrimitiveData::Circle {
            center: subtract_scaled_draw_point(tip, dir, length * 0.3),
            radius: length * 0.3,
            fill_mode: ArrowheadPrimitiveFillMode::Stroke,
        }],
        ArrowheadStyle::Circle => vec![ArrowheadRenderPrimitiveData::Circle {
            center: subtract_scaled_draw_point(tip, dir, length * 0.3),
            radius: length * 0.3,
            fill_mode: ArrowheadPrimitiveFillMode::Stroke,
        }],
        ArrowheadStyle::CircleOutline => vec![ArrowheadRenderPrimitiveData::Circle {
            center: subtract_scaled_draw_point(tip, dir, length * 0.3),
            radius: length * 0.3,
            fill_mode: ArrowheadPrimitiveFillMode::None,
        }],
        ArrowheadStyle::Diamond => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let mid = subtract_scaled_draw_point(tip, dir, length / 2.0);
            let left = add_scaled_draw_point(mid, perp, width / 2.0);
            let right = add_scaled_draw_point(mid, perp, -width / 2.0);
            polygon_primitive(
                vec![tip, left, base, right],
                ArrowheadPrimitiveFillMode::Stroke,
            )
        }
        ArrowheadStyle::DiamondOutline => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let mid = subtract_scaled_draw_point(tip, dir, length / 2.0);
            let left = add_scaled_draw_point(mid, perp, width / 2.0);
            let right = add_scaled_draw_point(mid, perp, -width / 2.0);
            polygon_primitive(
                vec![tip, left, base, right],
                ArrowheadPrimitiveFillMode::None,
            )
        }
        ArrowheadStyle::CrowfootOne => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            vec![ArrowheadRenderPrimitiveData::Line {
                from: left,
                to: right,
                dash_mode: line_dash_mode,
            }]
        }
        ArrowheadStyle::CrowfootMany => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            vec![
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: left,
                    dash_mode: line_dash_mode,
                },
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: right,
                    dash_mode: line_dash_mode,
                },
            ]
        }
        ArrowheadStyle::CrowfootOneOrMany => {
            let base = subtract_scaled_draw_point(tip, dir, length);
            let left = add_scaled_draw_point(base, perp, width / 2.0);
            let right = add_scaled_draw_point(base, perp, -width / 2.0);
            vec![
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: left,
                    dash_mode: line_dash_mode,
                },
                ArrowheadRenderPrimitiveData::Line {
                    from: tip,
                    to: right,
                    dash_mode: line_dash_mode,
                },
                ArrowheadRenderPrimitiveData::Line {
                    from: left,
                    to: right,
                    dash_mode: line_dash_mode,
                },
            ]
        }
        ArrowheadStyle::VerticalLine => {
            let half = width / 2.0;
            let left = add_scaled_draw_point(tip, perp, half);
            let right = add_scaled_draw_point(tip, perp, -half);
            vec![ArrowheadRenderPrimitiveData::Line {
                from: left,
                to: right,
                dash_mode: line_dash_mode,
            }]
        }
        ArrowheadStyle::None => Vec::new(),
    }
}

fn triangle_vertices(
    tip: DrawPoint,
    dir: DrawPoint,
    perp: DrawPoint,
    length: f64,
    width: f64,
) -> Vec<DrawPoint> {
    let base = subtract_scaled_draw_point(tip, dir, length);
    let left = add_scaled_draw_point(base, perp, width / 2.0);
    let right = add_scaled_draw_point(base, perp, -width / 2.0);
    vec![tip, left, right]
}

fn polygon_primitive(
    points: Vec<DrawPoint>,
    fill_mode: ArrowheadPrimitiveFillMode,
) -> Vec<ArrowheadRenderPrimitiveData> {
    vec![ArrowheadRenderPrimitiveData::Polygon { points, fill_mode }]
}

fn arrowhead_length(stroke_width: f64) -> f64 {
    stroke_width * 4.0 + 12.0
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

fn normalize_draw_vector(value: DrawPoint) -> Option<DrawPoint> {
    let length = (value.x * value.x + value.y * value.y).sqrt();
    if length == 0.0 {
        return None;
    }
    Some(DrawPoint::new(value.x / length, value.y / length))
}
