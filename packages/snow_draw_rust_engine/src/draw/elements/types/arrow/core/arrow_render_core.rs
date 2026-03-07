#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use super::arrow_types::{
    ArrowStrokeStyle, Arrowhead, ArrowheadDashMode, ArrowheadFillMode, CurvePathOp,
};

pub type ArrowEndpointPosition = &'static str;

pub const ARROW_ENDPOINT_POSITION_START: ArrowEndpointPosition = "start";
pub const ARROW_ENDPOINT_POSITION_END: ArrowEndpointPosition = "end";

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowheadPointsInput {
    pub arrow_points: Vec<DrawPoint>,
    pub stroke_width: f64,
    pub curve_ops: Vec<CurvePathOp>,
    pub position: ArrowEndpointPosition,
    pub arrowhead: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowheadRenderPrimitivesInput {
    pub arrow_points: Vec<DrawPoint>,
    pub stroke_width: f64,
    pub curve_ops: Vec<CurvePathOp>,
    pub position: ArrowEndpointPosition,
    pub arrowhead: String,
    pub stroke_style: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowheadLinePrimitive {
    pub from: DrawPoint,
    pub to: DrawPoint,
    pub dash_mode: String,
    pub roughness_cap: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowheadPolygonPrimitive {
    pub points: Vec<DrawPoint>,
    pub fill_mode: String,
    pub roughness_cap: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowheadCirclePrimitive {
    pub center: DrawPoint,
    pub diameter: f64,
    pub fill_mode: String,
    pub roughness_cap: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ArrowheadRenderPrimitive {
    Line {
        from: DrawPoint,
        to: DrawPoint,
        dash_mode: String,
        roughness_cap: Option<f64>,
    },
    Polygon {
        points: Vec<DrawPoint>,
        fill_mode: String,
        roughness_cap: Option<f64>,
    },
    Circle {
        center: DrawPoint,
        diameter: f64,
        fill_mode: String,
        roughness_cap: Option<f64>,
    },
}

impl From<ArrowheadLinePrimitive> for ArrowheadRenderPrimitive {
    fn from(value: ArrowheadLinePrimitive) -> Self {
        Self::Line {
            from: value.from,
            to: value.to,
            dash_mode: value.dash_mode,
            roughness_cap: value.roughness_cap,
        }
    }
}

impl From<ArrowheadPolygonPrimitive> for ArrowheadRenderPrimitive {
    fn from(value: ArrowheadPolygonPrimitive) -> Self {
        Self::Polygon {
            points: value.points,
            fill_mode: value.fill_mode,
            roughness_cap: value.roughness_cap,
        }
    }
}

impl From<ArrowheadCirclePrimitive> for ArrowheadRenderPrimitive {
    fn from(value: ArrowheadCirclePrimitive) -> Self {
        Self::Circle {
            center: value.center,
            diameter: value.diameter,
            fill_mode: value.fill_mode,
            roughness_cap: value.roughness_cap,
        }
    }
}

pub fn get_arrowhead_size(arrowhead: &str) -> f64 {
    match arrowhead {
        "arrow" => 25.0,
        "diamond" | "diamond_outline" => 12.0,
        "crowfoot_many" | "crowfoot_one" | "crowfoot_one_or_many" => 20.0,
        _ => 15.0,
    }
}

pub fn get_arrowhead_angle(arrowhead: &str) -> f64 {
    match arrowhead {
        "bar" => 90.0,
        "arrow" => 20.0,
        _ => 25.0,
    }
}

pub fn get_arrowhead_points(input: &ArrowheadPointsInput) -> Option<Vec<f64>> {
    let arrow_points = &input.arrow_points;
    if arrow_points.len() < 2 || input.stroke_width <= 0.0 {
        return None;
    }

    let is_end = input.position == ARROW_ENDPOINT_POSITION_END;
    let tip = if is_end {
        *arrow_points.last()?
    } else {
        arrow_points[0]
    };
    let neighbor = if is_end {
        arrow_points[arrow_points.len() - 2]
    } else {
        arrow_points[1]
    };

    let direction = normalize_direction(neighbor, tip)?;
    let size = get_arrowhead_size(&input.arrowhead) * (input.stroke_width / 2.0).max(1.0) / 2.0;
    let half = size / 2.0;
    let angle = get_arrowhead_angle(&input.arrowhead).to_radians();
    let shaft = DrawPoint::new(-direction.x, -direction.y);
    let perpendicular = DrawPoint::new(-shaft.y, shaft.x);

    let base_center = DrawPoint::new(tip.x + shaft.x * size, tip.y + shaft.y * size);
    let left = rotate_around(base_center + perpendicular * half, tip, angle);
    let right = rotate_around(base_center - perpendicular * half, tip, -angle);

    match input.arrowhead.as_str() {
        "dot" | "circle" | "circle_outline" => Some(vec![tip.x, tip.y, size]),
        "square" => {
            let c1 = base_center + perpendicular * half + shaft * half;
            let c2 = base_center - perpendicular * half + shaft * half;
            let c3 = base_center - perpendicular * half - shaft * half;
            let c4 = base_center + perpendicular * half - shaft * half;
            Some(vec![c1.x, c1.y, c2.x, c2.y, c3.x, c3.y, c4.x, c4.y])
        }
        "diamond" | "diamond_outline" => {
            let base = DrawPoint::new(tip.x + shaft.x * size, tip.y + shaft.y * size);
            let back = DrawPoint::new(tip.x + shaft.x * size * 2.0, tip.y + shaft.y * size * 2.0);
            let left_mid = base + perpendicular * half;
            let right_mid = base - perpendicular * half;
            Some(vec![
                tip.x,
                tip.y,
                left_mid.x,
                left_mid.y,
                back.x,
                back.y,
                right_mid.x,
                right_mid.y,
            ])
        }
        _ => Some(vec![tip.x, tip.y, left.x, left.y, right.x, right.y]),
    }
}

pub fn get_arrowhead_render_primitives(
    input: &ArrowheadRenderPrimitivesInput,
) -> Vec<ArrowheadRenderPrimitive> {
    let Some(points) = get_arrowhead_points(&ArrowheadPointsInput {
        arrow_points: input.arrow_points.clone(),
        stroke_width: input.stroke_width,
        curve_ops: input.curve_ops.clone(),
        position: input.position,
        arrowhead: input.arrowhead.clone(),
    }) else {
        return Vec::new();
    };

    match input.arrowhead.as_str() {
        "dot" => vec![ArrowheadRenderPrimitive::Circle {
            center: DrawPoint::new(points[0], points[1]),
            diameter: points[2],
            fill_mode: "stroke".to_string(),
            roughness_cap: Some(1.0),
        }],
        "circle" | "circle_outline" => vec![ArrowheadRenderPrimitive::Circle {
            center: DrawPoint::new(points[0], points[1]),
            diameter: points[2],
            fill_mode: if input.arrowhead == "circle_outline" {
                "background".to_string()
            } else {
                "stroke".to_string()
            },
            roughness_cap: Some(1.0),
        }],
        "square" => vec![ArrowheadRenderPrimitive::Polygon {
            points: vec![
                DrawPoint::new(points[0], points[1]),
                DrawPoint::new(points[2], points[3]),
                DrawPoint::new(points[4], points[5]),
                DrawPoint::new(points[6], points[7]),
            ],
            fill_mode: "stroke".to_string(),
            roughness_cap: Some(1.0),
        }],
        "diamond" | "diamond_outline" => vec![ArrowheadRenderPrimitive::Polygon {
            points: vec![
                DrawPoint::new(points[0], points[1]),
                DrawPoint::new(points[2], points[3]),
                DrawPoint::new(points[4], points[5]),
                DrawPoint::new(points[6], points[7]),
                DrawPoint::new(points[0], points[1]),
            ],
            fill_mode: if input.arrowhead == "diamond_outline" {
                "background".to_string()
            } else {
                "stroke".to_string()
            },
            roughness_cap: Some(1.0),
        }],
        _ => {
            if points.len() != 6 {
                return Vec::new();
            }
            let dash_mode = if input.stroke_style == "dotted" {
                "dotted-cap"
            } else {
                "solid"
            };
            vec![
                ArrowheadRenderPrimitive::Line {
                    from: DrawPoint::new(points[2], points[3]),
                    to: DrawPoint::new(points[0], points[1]),
                    dash_mode: dash_mode.to_string(),
                    roughness_cap: Some(1.0),
                },
                ArrowheadRenderPrimitive::Line {
                    from: DrawPoint::new(points[4], points[5]),
                    to: DrawPoint::new(points[0], points[1]),
                    dash_mode: dash_mode.to_string(),
                    roughness_cap: Some(1.0),
                },
            ]
        }
    }
}

pub fn generate_elbow_arrow_path(points: &[DrawPoint], radius: f64) -> String {
    if points.is_empty() {
        return String::new();
    }
    if points.len() == 1 {
        return format!(
            "M {} {}",
            format_number(points[0].x),
            format_number(points[0].y)
        );
    }

    let mut subpoints = Vec::<DrawPoint>::new();
    for index in 1..points.len() - 1 {
        let previous = points[index - 1];
        let point = points[index];
        let next = points[index + 1];
        let prev_is_horizontal = (point.x - previous.x).abs() > (point.y - previous.y).abs();
        let next_is_horizontal = (next.x - point.x).abs() > (next.y - point.y).abs();
        let corner = radius
            .min(point.distance(next) / 2.0)
            .min(point.distance(previous) / 2.0);

        subpoints.push(if prev_is_horizontal {
            DrawPoint::new(
                if previous.x < point.x {
                    point.x - corner
                } else {
                    point.x + corner
                },
                point.y,
            )
        } else {
            DrawPoint::new(
                point.x,
                if previous.y < point.y {
                    point.y - corner
                } else {
                    point.y + corner
                },
            )
        });
        subpoints.push(point);
        subpoints.push(if next_is_horizontal {
            DrawPoint::new(
                if next.x < point.x {
                    point.x - corner
                } else {
                    point.x + corner
                },
                point.y,
            )
        } else {
            DrawPoint::new(
                point.x,
                if next.y < point.y {
                    point.y - corner
                } else {
                    point.y + corner
                },
            )
        });
    }

    let mut path = vec![format!(
        "M {} {}",
        format_number(points[0].x),
        format_number(points[0].y)
    )];
    let mut index = 0usize;
    while index + 2 < subpoints.len() {
        path.push(format!(
            "L {} {}",
            format_number(subpoints[index].x),
            format_number(subpoints[index].y)
        ));
        path.push(format!(
            "Q {} {}, {} {}",
            format_number(subpoints[index + 1].x),
            format_number(subpoints[index + 1].y),
            format_number(subpoints[index + 2].x),
            format_number(subpoints[index + 2].y)
        ));
        index += 3;
    }
    if let Some(last) = points.last() {
        path.push(format!(
            "L {} {}",
            format_number(last.x),
            format_number(last.y)
        ));
    }
    path.join(" ")
}

fn normalize_direction(from: DrawPoint, to: DrawPoint) -> Option<DrawPoint> {
    let dx = to.x - from.x;
    let dy = to.y - from.y;
    let length = (dx * dx + dy * dy).sqrt();
    (length > 1e-6).then_some(DrawPoint::new(dx / length, dy / length))
}

fn rotate_around(point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
    let translated_x = point.x - center.x;
    let translated_y = point.y - center.y;
    let cos = angle.cos();
    let sin = angle.sin();
    DrawPoint::new(
        center.x + translated_x * cos - translated_y * sin,
        center.y + translated_x * sin + translated_y * cos,
    )
}

fn format_number(value: f64) -> String {
    if value == value.trunc() {
        (value as i64).to_string()
    } else {
        value.to_string()
    }
}
