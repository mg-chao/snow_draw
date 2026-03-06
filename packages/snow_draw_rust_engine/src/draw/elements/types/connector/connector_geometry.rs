#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_geometry::{ArrowGeometry, DirectionResolveOptions};
use crate::draw::elements::types::arrow::arrow_layout::{
    resolve_arrow_geometry_update, ArrowGeometryUpdate,
};
use crate::draw::elements::types::arrow::core::arrow_render_core::generate_elbow_arrow_path;
use crate::draw::elements::types::connector::connector_data::ConnectorData;
use crate::draw::elements::types::shared::hit_test_geometry::flatten_catmull_rom_draw_points;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

pub type ConnectorGeometryUpdate = ArrowGeometryUpdate;

const CATMULL_ROM_MAX_POINTS: usize = 120;
const CATMULL_ROM_TENSION: f64 = 1.0;

/// Typed connector path commands.
#[derive(Clone, Debug, PartialEq)]
pub enum ConnectorPathCommand {
    Move(DrawPoint),
    Line(DrawPoint),
    Quadratic {
        control_point: DrawPoint,
        point: DrawPoint,
    },
}

/// Shared geometry helpers for connector-style elements.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ConnectorGeometry;

impl ConnectorGeometry {
    pub const fn new() -> Self {
        Self
    }

    pub fn resolve_local_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
        ArrowGeometry::resolve_local_points(rect, normalized_points)
    }

    pub fn resolve_world_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
        ArrowGeometry::resolve_world_points(rect, normalized_points)
    }

    pub fn normalize_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
        ArrowGeometry::normalize_points(world_points, rect)
    }

    pub fn generate_elbow_path_data(points: &[DrawPoint], radius: f64) -> String {
        let safe_radius = if radius.is_finite() && radius > 0.0 {
            radius
        } else {
            0.0
        };
        generate_elbow_arrow_path(points, safe_radius)
    }

    pub fn resolve_elbow_path_commands(
        points: &[DrawPoint],
        radius: f64,
    ) -> Vec<ConnectorPathCommand> {
        if points.is_empty() {
            return Vec::new();
        }

        parse_path_commands(&Self::generate_elbow_path_data(points, radius))
            .filter(|commands| !commands.is_empty())
            .unwrap_or_else(|| build_straight_path_commands(points))
    }

    pub fn calculate_shaft_length(points: &[DrawPoint], arrow_type: ArrowType) -> f64 {
        ArrowGeometry::calculate_shaft_length(points, arrow_type)
    }

    pub fn resolve_start_direction(
        points: &[DrawPoint],
        arrow_type: ArrowType,
        start_inset: f64,
        end_inset: f64,
        direction_offset: f64,
    ) -> Option<DrawPoint> {
        ArrowGeometry::resolve_start_direction(
            points,
            arrow_type,
            DirectionResolveOptions::new(start_inset, end_inset, direction_offset),
        )
    }

    pub fn resolve_end_direction(
        points: &[DrawPoint],
        arrow_type: ArrowType,
        start_inset: f64,
        end_inset: f64,
        direction_offset: f64,
    ) -> Option<DrawPoint> {
        ArrowGeometry::resolve_end_direction(
            points,
            arrow_type,
            DirectionResolveOptions::new(start_inset, end_inset, direction_offset),
        )
    }

    pub fn calculate_curve_draw_point(
        points: &[DrawPoint],
        segment_index: usize,
        t: f64,
    ) -> Option<DrawPoint> {
        ArrowGeometry::calculate_curve_draw_point(points, segment_index, t)
    }

    pub fn calculate_arrowhead_inset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
        ArrowGeometry::calculate_arrowhead_inset(style, stroke_width)
    }

    pub fn calculate_arrowhead_direction_offset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
        ArrowGeometry::calculate_arrowhead_direction_offset(style, stroke_width)
    }

    pub fn resolve_arrowhead_length(stroke_width: f64) -> f64 {
        ArrowGeometry::resolve_arrowhead_length(stroke_width)
    }

    pub fn calculate_path_bounds(world_points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
        ArrowGeometry::calculate_path_bounds(world_points, arrow_type)
    }

    pub fn apply_insets(points: &[DrawPoint], start_inset: f64, end_inset: f64) -> Vec<DrawPoint> {
        ArrowGeometry::apply_insets(points, start_inset, end_inset)
    }

    pub fn sample_shaft_for_hit_test(
        points: &[DrawPoint],
        arrow_type: ArrowType,
        stroke_width: f64,
    ) -> Vec<DrawPoint> {
        if points.len() < 2 {
            return points.to_vec();
        }

        if arrow_type == ArrowType::Curved && points.len() > 2 {
            return flatten_catmull_rom_draw_points(
                points,
                stroke_width,
                CATMULL_ROM_MAX_POINTS,
                CATMULL_ROM_TENSION,
                true,
            );
        }

        if arrow_type == ArrowType::Elbow && points.len() > 2 {
            return sample_elbow_path(points, stroke_width);
        }

        points.to_vec()
    }
}

/// Cached connector geometry helper mirroring the Dart API surface.
#[derive(Clone, Debug)]
pub struct ConnectorGeometryDescriptor<D>
where
    D: ConnectorData,
{
    pub data: D,
    pub rect: DrawRect,
    local_draw_points: Option<Vec<DrawPoint>>,
    inset_draw_points: Option<Vec<DrawPoint>>,
    start_direction_point: Option<DrawPoint>,
    end_direction_point: Option<DrawPoint>,
    start_inset: Option<f64>,
    end_inset: Option<f64>,
    start_direction_offset: Option<f64>,
    end_direction_offset: Option<f64>,
}

impl<D> ConnectorGeometryDescriptor<D>
where
    D: ConnectorData,
{
    pub fn new(data: D, rect: DrawRect) -> Self {
        Self {
            data,
            rect,
            local_draw_points: None,
            inset_draw_points: None,
            start_direction_point: None,
            end_direction_point: None,
            start_inset: None,
            end_inset: None,
            start_direction_offset: None,
            end_direction_offset: None,
        }
    }

    pub fn local_draw_points(&mut self) -> &[DrawPoint] {
        if self.local_draw_points.is_none() {
            self.local_draw_points = Some(ConnectorGeometry::resolve_local_points(
                self.rect,
                self.data.points(),
            ));
        }
        self.local_draw_points.as_deref().unwrap_or(&[])
    }

    pub fn start_inset(&mut self) -> f64 {
        if let Some(value) = self.start_inset {
            return value;
        }
        let value = ConnectorGeometry::calculate_arrowhead_inset(
            self.data.start_arrowhead(),
            self.data.stroke_width(),
        );
        self.start_inset = Some(value);
        value
    }

    pub fn end_inset(&mut self) -> f64 {
        if let Some(value) = self.end_inset {
            return value;
        }
        let value = ConnectorGeometry::calculate_arrowhead_inset(
            self.data.end_arrowhead(),
            self.data.stroke_width(),
        );
        self.end_inset = Some(value);
        value
    }

    pub fn start_direction_offset(&mut self) -> f64 {
        if let Some(value) = self.start_direction_offset {
            return value;
        }
        let value = ConnectorGeometry::calculate_arrowhead_direction_offset(
            self.data.start_arrowhead(),
            self.data.stroke_width(),
        );
        self.start_direction_offset = Some(value);
        value
    }

    pub fn end_direction_offset(&mut self) -> f64 {
        if let Some(value) = self.end_direction_offset {
            return value;
        }
        let value = ConnectorGeometry::calculate_arrowhead_direction_offset(
            self.data.end_arrowhead(),
            self.data.stroke_width(),
        );
        self.end_direction_offset = Some(value);
        value
    }

    pub fn inset_draw_points(&mut self) -> &[DrawPoint] {
        if self.inset_draw_points.is_none() {
            let start_inset = self.start_inset();
            let end_inset = self.end_inset();
            let local_points = self.local_draw_points().to_vec();
            let applied = if start_inset <= 0.0 && end_inset <= 0.0 {
                local_points
            } else {
                ConnectorGeometry::apply_insets(&local_points, start_inset, end_inset)
            };
            self.inset_draw_points = Some(applied);
        }
        self.inset_draw_points.as_deref().unwrap_or(&[])
    }

    pub fn start_direction_point(&mut self) -> Option<DrawPoint> {
        if let Some(value) = self.start_direction_point {
            return Some(value);
        }
        let local_points = self.local_draw_points().to_vec();
        let resolved = ConnectorGeometry::resolve_start_direction(
            &local_points,
            self.data.arrow_type(),
            self.start_inset(),
            self.end_inset(),
            self.start_direction_offset(),
        );
        if let Some(point) = resolved {
            self.start_direction_point = Some(point);
        }
        resolved
    }

    pub fn end_direction_point(&mut self) -> Option<DrawPoint> {
        if let Some(value) = self.end_direction_point {
            return Some(value);
        }
        let local_points = self.local_draw_points().to_vec();
        let resolved = ConnectorGeometry::resolve_end_direction(
            &local_points,
            self.data.arrow_type(),
            self.start_inset(),
            self.end_inset(),
            self.end_direction_offset(),
        );
        if let Some(point) = resolved {
            self.end_direction_point = Some(point);
        }
        resolved
    }
}

/// Calculates connector bounds from world-space points.
pub fn calculate_connector_rect(points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
    ConnectorGeometry::calculate_path_bounds(points, arrow_type)
}

/// Resolves connector local-space points from normalized element-local points.
pub fn resolve_connector_local_points(
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    ConnectorGeometry::resolve_local_points(rect, normalized_points)
}

/// Normalizes connector world-space points into element-local space.
pub fn normalize_connector_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
    ConnectorGeometry::normalize_points(world_points, rect)
}

/// Resolves world-space connector points from normalized element-local points.
pub fn resolve_connector_world_points(
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    ConnectorGeometry::resolve_world_points(rect, normalized_points)
}

/// Recomputes connector geometry after local point edits.
pub fn resolve_connector_geometry_update(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ConnectorGeometryUpdate {
    resolve_arrow_geometry_update(local_points, old_rect, rotation, arrow_type)
}

fn parse_path_commands(path_data: &str) -> Option<Vec<ConnectorPathCommand>> {
    let trimmed = path_data.trim();
    if trimmed.is_empty() {
        return Some(Vec::new());
    }

    let tokens = trimmed
        .replace(',', " ")
        .split_whitespace()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    if tokens.is_empty() {
        return Some(Vec::new());
    }

    let mut commands = Vec::new();
    let mut index = 0;
    while index < tokens.len() {
        let token = tokens[index].as_str();
        index += 1;
        if token.len() != 1 {
            return None;
        }

        let mut read_number = || {
            let value = tokens.get(index)?.parse::<f64>().ok()?;
            index += 1;
            Some(value)
        };

        match token.to_ascii_uppercase().as_str() {
            "M" => {
                let x = read_number()?;
                let y = read_number()?;
                commands.push(ConnectorPathCommand::Move(DrawPoint::new(x, y)));
            }
            "L" => {
                let x = read_number()?;
                let y = read_number()?;
                commands.push(ConnectorPathCommand::Line(DrawPoint::new(x, y)));
            }
            "Q" => {
                let cx = read_number()?;
                let cy = read_number()?;
                let x = read_number()?;
                let y = read_number()?;
                commands.push(ConnectorPathCommand::Quadratic {
                    control_point: DrawPoint::new(cx, cy),
                    point: DrawPoint::new(x, y),
                });
            }
            _ => return None,
        }
    }

    Some(commands)
}

fn build_straight_path_commands(points: &[DrawPoint]) -> Vec<ConnectorPathCommand> {
    let Some(first) = points.first().copied() else {
        return Vec::new();
    };

    let mut commands = vec![ConnectorPathCommand::Move(first)];
    commands.extend(
        points
            .iter()
            .skip(1)
            .copied()
            .map(ConnectorPathCommand::Line),
    );
    commands
}

fn sample_elbow_path(points: &[DrawPoint], stroke_width: f64) -> Vec<DrawPoint> {
    let commands = ConnectorGeometry::resolve_elbow_path_commands(points, 16.0);
    let Some(first_move) = commands.first() else {
        return points.to_vec();
    };

    let mut sampled = Vec::new();
    let mut cursor = match first_move {
        ConnectorPathCommand::Move(point) => {
            sampled.push(*point);
            *point
        }
        ConnectorPathCommand::Line(point) => {
            sampled.push(points[0]);
            sampled.push(*point);
            *point
        }
        ConnectorPathCommand::Quadratic {
            control_point: _,
            point,
        } => {
            sampled.push(points[0]);
            sampled.push(*point);
            *point
        }
    };

    for command in commands.into_iter().skip(1) {
        match command {
            ConnectorPathCommand::Move(point) => {
                if sampled.last().copied() != Some(point) {
                    sampled.push(point);
                }
                cursor = point;
            }
            ConnectorPathCommand::Line(point) => {
                if sampled.last().copied() != Some(point) {
                    sampled.push(point);
                }
                cursor = point;
            }
            ConnectorPathCommand::Quadratic {
                control_point,
                point,
            } => {
                append_quadratic_samples(&mut sampled, cursor, control_point, point, stroke_width);
                cursor = point;
            }
        }
    }

    sampled
}

fn append_quadratic_samples(
    output: &mut Vec<DrawPoint>,
    start: DrawPoint,
    control: DrawPoint,
    end: DrawPoint,
    stroke_width: f64,
) {
    let approx_length = start.distance(control) + control.distance(end);
    let step = stroke_width.max(1.0);
    let segments = ((approx_length / step).ceil() as usize).clamp(4, 32);
    for segment in 1..=segments {
        let t = segment as f64 / segments as f64;
        let one_minus_t = 1.0 - t;
        let point = DrawPoint::new(
            (one_minus_t * one_minus_t * start.x)
                + (2.0 * one_minus_t * t * control.x)
                + (t * t * end.x),
            (one_minus_t * one_minus_t * start.y)
                + (2.0 * one_minus_t * t * control.y)
                + (t * t * end.y),
        );
        if output.last().copied() != Some(point) {
            output.push(point);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::arrow_data::ArrowData;

    #[test]
    fn resolve_elbow_path_commands_falls_back_to_polyline_for_empty_path() {
        let points = vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(10.0, 10.0)];
        let commands = ConnectorGeometry::resolve_elbow_path_commands(&points, 16.0);

        assert_eq!(commands.len(), 2);
        assert!(matches!(commands[0], ConnectorPathCommand::Move(_)));
        assert!(matches!(commands[1], ConnectorPathCommand::Line(_)));
    }

    #[test]
    fn sample_shaft_for_hit_test_flattens_elbow_path() {
        let points = vec![
            DrawPoint::new(0.0, 0.0),
            DrawPoint::new(40.0, 0.0),
            DrawPoint::new(40.0, 40.0),
        ];
        let sampled = ConnectorGeometry::sample_shaft_for_hit_test(&points, ArrowType::Elbow, 2.0);

        assert!(sampled.len() >= points.len());
        assert_eq!(sampled.first().copied(), Some(points[0]));
        assert_eq!(sampled.last().copied(), Some(points[points.len() - 1]));
    }

    #[test]
    fn geometry_descriptor_caches_arrowhead_metrics() {
        let mut descriptor = ConnectorGeometryDescriptor::new(
            ArrowData::default(),
            DrawRect::new(0.0, 0.0, 100.0, 100.0),
        );

        assert!(descriptor.start_inset() >= 0.0);
        assert!(descriptor.end_inset() >= 0.0);
        assert_eq!(descriptor.local_draw_points().len(), 2);
    }
}
