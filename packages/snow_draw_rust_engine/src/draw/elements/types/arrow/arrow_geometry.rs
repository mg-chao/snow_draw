#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

const DEFAULT_POINTS: [DrawPoint; 2] = [DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];
const CUBIC_LENGTH_STEPS: usize = 8;
const CUBIC_ROOT_EPSILON: f64 = 1e-9;

#[derive(Clone, Copy, Debug, PartialEq)]
struct CubicSegment {
    start: DrawPoint,
    control1: DrawPoint,
    control2: DrawPoint,
    end: DrawPoint,
}

/// Direction-resolution options for arrow endpoints.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct DirectionResolveOptions {
    pub start_inset: f64,
    pub end_inset: f64,
    pub direction_offset: f64,
}

impl DirectionResolveOptions {
    pub const fn new(start_inset: f64, end_inset: f64, direction_offset: f64) -> Self {
        Self {
            start_inset,
            end_inset,
            direction_offset,
        }
    }
}

/// Geometry helpers translated from Dart `ArrowGeometry`.
pub struct ArrowGeometry;

impl ArrowGeometry {
    pub fn resolve_local_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
        let points = Self::ensure_min_points(normalized_points);
        let width = rect.width();
        let height = rect.height();
        points
            .into_iter()
            .map(|point| DrawPoint::new(point.x * width, point.y * height))
            .collect()
    }

    pub fn resolve_world_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
        let points = Self::ensure_min_points(normalized_points);
        let width = rect.width();
        let height = rect.height();
        points
            .into_iter()
            .map(|point| {
                DrawPoint::new(rect.min_x + point.x * width, rect.min_y + point.y * height)
            })
            .collect()
    }

    pub fn normalize_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
        let points = Self::ensure_min_points(world_points);
        let width = rect.width();
        let height = rect.height();

        points
            .into_iter()
            .map(|point| {
                let x = if width == 0.0 {
                    0.0
                } else {
                    (point.x - rect.min_x) / width
                };
                let y = if height == 0.0 {
                    0.0
                } else {
                    (point.y - rect.min_y) / height
                };
                DrawPoint::with_pressure_and_timestamp(
                    Self::clamp01(x),
                    Self::clamp01(y),
                    point.pressure,
                    0,
                )
            })
            .collect()
    }

    pub fn calculate_shaft_length(points: &[DrawPoint], arrow_type: ArrowType) -> f64 {
        if points.len() < 2 {
            return 0.0;
        }
        if arrow_type == ArrowType::Curved && points.len() > 2 {
            return Self::approximate_curved_length(points);
        }
        Self::calculate_polyline_length(points)
    }

    pub fn resolve_start_direction(
        points: &[DrawPoint],
        arrow_type: ArrowType,
        options: DirectionResolveOptions,
    ) -> Option<DrawPoint> {
        if points.len() < 2 {
            return None;
        }

        let has_insets = options.start_inset > 0.0 || options.end_inset > 0.0;
        let working_points = if has_insets {
            Self::apply_insets(points, options.start_inset, options.end_inset)
        } else {
            points.to_vec()
        };
        if working_points.len() < 2 {
            return None;
        }

        if arrow_type == ArrowType::Curved && working_points.len() > 2 {
            let effective_offset = (options.direction_offset - options.start_inset).max(0.0);
            let direction =
                CurvedPathAnalysis::new(&working_points).direction_from_start(effective_offset);
            if let Some(direction) = direction {
                return Some(-direction);
            }
        }

        let vector = working_points[0] - working_points[1];
        Self::normalize(vector)
    }

    pub fn resolve_end_direction(
        points: &[DrawPoint],
        arrow_type: ArrowType,
        options: DirectionResolveOptions,
    ) -> Option<DrawPoint> {
        if points.len() < 2 {
            return None;
        }

        let has_insets = options.start_inset > 0.0 || options.end_inset > 0.0;
        let working_points = if has_insets {
            Self::apply_insets(points, options.start_inset, options.end_inset)
        } else {
            points.to_vec()
        };
        if working_points.len() < 2 {
            return None;
        }

        if arrow_type == ArrowType::Curved && working_points.len() > 2 {
            let effective_offset = (options.direction_offset - options.end_inset).max(0.0);
            let direction =
                CurvedPathAnalysis::new(&working_points).direction_from_end(effective_offset);
            if direction.is_some() {
                return direction;
            }
        }

        let last = working_points.len() - 1;
        let vector = working_points[last] - working_points[last - 1];
        Self::normalize(vector)
    }

    /// Calculates a point on the curved path.
    pub fn calculate_curve_draw_point(
        points: &[DrawPoint],
        segment_index: usize,
        t: f64,
    ) -> Option<DrawPoint> {
        if points.len() < 2 || segment_index >= points.len() - 1 {
            return None;
        }

        if points.len() < 3 {
            let p1 = points[segment_index];
            let p2 = points[segment_index + 1];
            return Some(DrawPoint::new(
                p1.x + (p2.x - p1.x) * t,
                p1.y + (p2.y - p1.y) * t,
            ));
        }

        Some(Self::evaluate_cubic(
            Self::build_cubic_segment(points, segment_index),
            t,
        ))
    }

    pub fn calculate_arrowhead_inset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
        if stroke_width <= 0.0 {
            return 0.0;
        }

        let length = Self::resolve_arrowhead_length(stroke_width);
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
            | ArrowheadStyle::VerticalLine => 0.0,
            ArrowheadStyle::None => 0.0,
        }
    }

    pub fn calculate_arrowhead_direction_offset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
        if stroke_width <= 0.0 {
            return 0.0;
        }

        let length = Self::resolve_arrowhead_length(stroke_width);
        match style {
            ArrowheadStyle::Dot | ArrowheadStyle::Circle | ArrowheadStyle::CircleOutline => {
                length * 0.6
            }
            ArrowheadStyle::Square => length * 0.6,
            ArrowheadStyle::VerticalLine => length * 0.6,
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

    /// Resolves canonical arrowhead length from `stroke_width`.
    pub fn resolve_arrowhead_length(stroke_width: f64) -> f64 {
        stroke_width * 4.0 + 12.0
    }

    pub fn calculate_path_bounds(world_points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
        if world_points.is_empty() {
            return DrawRect::default();
        }

        if arrow_type != ArrowType::Curved || world_points.len() < 3 {
            return Self::bounds_from_points(world_points);
        }

        let mut min_x = world_points[0].x;
        let mut max_x = world_points[0].x;
        let mut min_y = world_points[0].y;
        let mut max_y = world_points[0].y;

        for i in 0..(world_points.len() - 1) {
            let segment = Self::build_cubic_segment(world_points, i);
            Self::expand_bounds_for_cubic(segment, &mut min_x, &mut max_x, &mut min_y, &mut max_y);
        }

        DrawRect::new(min_x, min_y, max_x, max_y)
    }

    fn bounds_from_points(points: &[DrawPoint]) -> DrawRect {
        DrawRect::from_point_cloud(points.iter().copied())
    }

    fn clamp01(value: f64) -> f64 {
        if !value.is_finite() {
            return 0.0;
        }
        value.clamp(0.0, 1.0)
    }

    fn normalize(value: DrawPoint) -> Option<DrawPoint> {
        let length = value.distance(DrawPoint::ZERO);
        if length == 0.0 {
            return None;
        }
        Some(DrawPoint::new(value.x / length, value.y / length))
    }

    fn approximate_curved_length(points: &[DrawPoint]) -> f64 {
        if points.len() < 2 {
            return 0.0;
        }

        let mut length = 0.0;
        for i in 0..(points.len() - 1) {
            let segment = Self::build_cubic_segment(points, i);
            length += Self::approximate_cubic_length(segment);
        }
        length
    }

    fn calculate_polyline_length(points: &[DrawPoint]) -> f64 {
        let mut length = 0.0;
        for i in 1..points.len() {
            length += (points[i] - points[i - 1]).distance(DrawPoint::ZERO);
        }
        length
    }

    fn build_cubic_segment(points: &[DrawPoint], index: usize) -> CubicSegment {
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
        CubicSegment {
            start: p1,
            control1,
            control2,
            end: p2,
        }
    }

    fn approximate_cubic_length(segment: CubicSegment) -> f64 {
        let mut length = 0.0;
        let mut previous = segment.start;
        for i in 1..=CUBIC_LENGTH_STEPS {
            let t = i as f64 / CUBIC_LENGTH_STEPS as f64;
            let point = Self::evaluate_cubic(segment, t);
            length += (point - previous).distance(DrawPoint::ZERO);
            previous = point;
        }
        length
    }

    fn evaluate_cubic(segment: CubicSegment, t: f64) -> DrawPoint {
        let mt = 1.0 - t;
        let mt2 = mt * mt;
        let t2 = t * t;
        let a = mt2 * mt;
        let b = 3.0 * mt2 * t;
        let c = 3.0 * mt * t2;
        let d = t2 * t;
        segment.start * a + segment.control1 * b + segment.control2 * c + segment.end * d
    }

    fn cubic_tangent(segment: CubicSegment, t: f64) -> DrawPoint {
        let mt = 1.0 - t;
        let a = (segment.control1 - segment.start) * (3.0 * mt * mt);
        let b = (segment.control2 - segment.control1) * (6.0 * mt * t);
        let c = (segment.end - segment.control2) * (3.0 * t * t);
        a + b + c
    }

    fn expand_bounds_for_cubic(
        segment: CubicSegment,
        min_x: &mut f64,
        max_x: &mut f64,
        min_y: &mut f64,
        max_y: &mut f64,
    ) {
        let mut t_values = vec![0.0, 1.0];
        for t in Self::cubic_derivative_roots(
            segment.start.x,
            segment.control1.x,
            segment.control2.x,
            segment.end.x,
        ) {
            push_unique_t(&mut t_values, t);
        }
        for t in Self::cubic_derivative_roots(
            segment.start.y,
            segment.control1.y,
            segment.control2.y,
            segment.end.y,
        ) {
            push_unique_t(&mut t_values, t);
        }

        for t in t_values {
            let point = Self::evaluate_cubic(segment, t);
            *min_x = (*min_x).min(point.x);
            *max_x = (*max_x).max(point.x);
            *min_y = (*min_y).min(point.y);
            *max_y = (*max_y).max(point.y);
        }
    }

    fn cubic_derivative_roots(p0: f64, p1: f64, p2: f64, p3: f64) -> Vec<f64> {
        let a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
        let b = 3.0 * p0 - 6.0 * p1 + 3.0 * p2;
        let c = -3.0 * p0 + 3.0 * p1;

        if a.abs() < CUBIC_ROOT_EPSILON {
            if b.abs() < CUBIC_ROOT_EPSILON {
                return Vec::new();
            }
            let t = -c / (2.0 * b);
            if (0.0..1.0).contains(&t) {
                return vec![t];
            }
            return Vec::new();
        }

        let quad_a = 3.0 * a;
        let quad_b = 2.0 * b;
        let quad_c = c;
        let discriminant = quad_b * quad_b - 4.0 * quad_a * quad_c;
        if discriminant < 0.0 {
            return Vec::new();
        }
        let sqrt_disc = discriminant.sqrt();
        let denom = 2.0 * quad_a;
        if denom.abs() < CUBIC_ROOT_EPSILON {
            return Vec::new();
        }

        let t1 = (-quad_b + sqrt_disc) / denom;
        let t2 = (-quad_b - sqrt_disc) / denom;
        let mut roots = Vec::with_capacity(2);
        if (0.0..1.0).contains(&t1) {
            roots.push(t1);
        }
        if (0.0..1.0).contains(&t2) {
            roots.push(t2);
        }
        roots
    }

    fn ensure_min_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
        if points.len() >= 2 {
            return points.to_vec();
        }
        if points.is_empty() {
            return DEFAULT_POINTS.to_vec();
        }
        vec![points[0], points[0]]
    }

    /// Applies start/end shaft insets and returns the shortened point list.
    pub fn apply_insets(points: &[DrawPoint], start_inset: f64, end_inset: f64) -> Vec<DrawPoint> {
        if points.len() < 2 {
            return points.to_vec();
        }

        let mut adjusted_points = points.to_vec();
        if start_inset > 0.0 {
            adjusted_points = Self::inset_from_start(&adjusted_points, start_inset);
            if adjusted_points.len() < 2 {
                return adjusted_points;
            }
        }
        if end_inset > 0.0 {
            adjusted_points = Self::inset_from_end(&adjusted_points, end_inset);
        }

        adjusted_points
    }

    fn inset_from_start(points: &[DrawPoint], inset: f64) -> Vec<DrawPoint> {
        if points.len() < 2 || inset <= 0.0 {
            return points.to_vec();
        }

        let mut remaining_inset = inset;
        for i in 0..(points.len() - 1) {
            let segment_vector = points[i + 1] - points[i];
            let segment_length = segment_vector.distance(DrawPoint::ZERO);
            if segment_length <= 0.0 {
                continue;
            }

            if remaining_inset < segment_length {
                let direction = segment_vector / segment_length;
                let new_start = points[i] + direction * remaining_inset;
                let mut result = Vec::with_capacity(points.len() - i);
                result.push(new_start);
                result.extend_from_slice(&points[(i + 1)..]);
                return result;
            }

            remaining_inset -= segment_length;
        }

        vec![points[points.len() - 1]]
    }

    fn inset_from_end(points: &[DrawPoint], inset: f64) -> Vec<DrawPoint> {
        if points.len() < 2 || inset <= 0.0 {
            return points.to_vec();
        }

        let mut remaining_inset = inset;
        for i in (1..points.len()).rev() {
            let segment_vector = points[i - 1] - points[i];
            let segment_length = segment_vector.distance(DrawPoint::ZERO);
            if segment_length <= 0.0 {
                continue;
            }

            if remaining_inset < segment_length {
                let direction = segment_vector / segment_length;
                let new_end = points[i] + direction * remaining_inset;
                let mut result = Vec::with_capacity(i + 1);
                result.extend_from_slice(&points[..i]);
                result.push(new_end);
                return result;
            }

            remaining_inset -= segment_length;
        }

        vec![points[0]]
    }
}

/// Minimal shape required by `ArrowGeometryDescriptor`.
pub trait ArrowLikeData {
    fn points(&self) -> &[DrawPoint];
    fn arrow_type(&self) -> ArrowType;
    fn start_arrowhead(&self) -> ArrowheadStyle;
    fn end_arrowhead(&self) -> ArrowheadStyle;
    fn stroke_width(&self) -> f64;
}

/// Cached geometry helper mirroring Dart `ArrowGeometryDescriptor`.
#[derive(Clone, Debug)]
pub struct ArrowGeometryDescriptor<D>
where
    D: ArrowLikeData,
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

impl<D> ArrowGeometryDescriptor<D>
where
    D: ArrowLikeData,
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
            self.local_draw_points = Some(ArrowGeometry::resolve_local_points(
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
        let value = ArrowGeometry::calculate_arrowhead_inset(
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
        let value = ArrowGeometry::calculate_arrowhead_inset(
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
        let value = ArrowGeometry::calculate_arrowhead_direction_offset(
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
        let value = ArrowGeometry::calculate_arrowhead_direction_offset(
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
                ArrowGeometry::apply_insets(&local_points, start_inset, end_inset)
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
        let resolved = ArrowGeometry::resolve_start_direction(
            &local_points,
            self.data.arrow_type(),
            DirectionResolveOptions::new(
                self.start_inset(),
                self.end_inset(),
                self.start_direction_offset(),
            ),
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
        let resolved = ArrowGeometry::resolve_end_direction(
            &local_points,
            self.data.arrow_type(),
            DirectionResolveOptions::new(
                self.start_inset(),
                self.end_inset(),
                self.end_direction_offset(),
            ),
        );
        if let Some(point) = resolved {
            self.end_direction_point = Some(point);
        }
        resolved
    }
}

#[derive(Clone, Debug)]
struct CurvedPathAnalysis {
    segments: Vec<CubicSegment>,
    lengths: Vec<f64>,
    total_length: f64,
}

impl CurvedPathAnalysis {
    fn new(points: &[DrawPoint]) -> Self {
        let segment_count = points.len().saturating_sub(1);
        let mut segments = Vec::with_capacity(segment_count);
        for index in 0..segment_count {
            segments.push(ArrowGeometry::build_cubic_segment(points, index));
        }

        let mut lengths = Vec::with_capacity(segment_count);
        let mut total = 0.0;
        for &segment in &segments {
            let length = ArrowGeometry::approximate_cubic_length(segment);
            lengths.push(length);
            total += length;
        }

        Self {
            segments,
            lengths,
            total_length: total,
        }
    }

    fn direction_from_start(&self, offset: f64) -> Option<DrawPoint> {
        if self.segments.is_empty() {
            return None;
        }

        let mut remaining = if offset.is_finite() { offset } else { 0.0 };
        if remaining < 0.0 {
            remaining = 0.0;
        }

        for i in 0..self.segments.len() {
            let length = self.lengths[i];
            if length <= 0.0 {
                continue;
            }
            if remaining <= length || i == self.segments.len() - 1 {
                let t = (remaining / length).clamp(0.0, 1.0);
                let tangent = ArrowGeometry::cubic_tangent(self.segments[i], t);
                return ArrowGeometry::normalize(tangent);
            }
            remaining -= length;
        }
        None
    }

    fn direction_from_end(&self, offset: f64) -> Option<DrawPoint> {
        if self.segments.is_empty() {
            return None;
        }

        let mut remaining = if offset.is_finite() { offset } else { 0.0 };
        if remaining < 0.0 {
            remaining = 0.0;
        }

        for i in (0..self.segments.len()).rev() {
            let length = self.lengths[i];
            if length <= 0.0 {
                continue;
            }
            if remaining <= length || i == 0 {
                let t = (1.0 - (remaining / length)).clamp(0.0, 1.0);
                let tangent = ArrowGeometry::cubic_tangent(self.segments[i], t);
                return ArrowGeometry::normalize(tangent);
            }
            remaining -= length;
        }
        None
    }
}

fn push_unique_t(values: &mut Vec<f64>, t: f64) {
    if values
        .iter()
        .any(|existing| (*existing - t).abs() <= CUBIC_ROOT_EPSILON)
    {
        return;
    }
    values.push(t);
}
