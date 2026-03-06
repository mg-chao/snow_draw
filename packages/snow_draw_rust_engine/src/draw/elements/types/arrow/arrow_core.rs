#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::arrow_binding::ArrowBinding;
use super::arrow_data::ElbowFixedSegment;
use super::arrow_like_data::NullableField;

pub const BIND_MODE_INSIDE: &str = "inside";
pub const BIND_MODE_ORBIT: &str = "orbit";
pub const BIND_MODE_SKIP: &str = "skip";
pub const DEFAULT_MAX_COORDINATE: f64 = 1e6;
pub type BindMode = &'static str;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowEndpointEdge {
    Start,
    End,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BindableShape {
    Rectangle,
    Ellipse,
    Diamond,
    Unknown,
}

impl BindableShape {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Rectangle => "rectangle",
            Self::Ellipse => "ellipse",
            Self::Diamond => "diamond",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindableState {
    pub id: String,
    pub shape: BindableShape,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub angle: f64,
    pub stroke_width: f64,
    pub z_index: Option<f64>,
    pub background_opaque: Option<bool>,
    pub binding_enabled: Option<bool>,
    pub interior_hit_enabled: Option<bool>,
    pub visibility_bounds: Option<DrawRect>,
}

impl BindableState {
    pub fn rect(&self) -> DrawRect {
        DrawRect::new(self.x, self.y, self.x + self.width, self.y + self.height)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowState {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub points: Vec<DrawPoint>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub start_arrowhead: Option<String>,
    pub end_arrowhead: Option<String>,
    pub elbowed: bool,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

impl ArrowState {
    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        &self,
        x: Option<f64>,
        y: Option<f64>,
        width: Option<f64>,
        height: Option<f64>,
        points: Option<Vec<DrawPoint>>,
        start_binding: NullableField<ArrowBinding>,
        end_binding: NullableField<ArrowBinding>,
        fixed_segments: NullableField<Vec<ElbowFixedSegment>>,
        start_is_special: NullableField<bool>,
        end_is_special: NullableField<bool>,
    ) -> Self {
        Self {
            id: self.id.clone(),
            x: x.unwrap_or(self.x),
            y: y.unwrap_or(self.y),
            width: width.unwrap_or(self.width),
            height: height.unwrap_or(self.height),
            points: points.unwrap_or_else(|| self.points.clone()),
            start_binding: resolve_nullable_update(start_binding, &self.start_binding),
            end_binding: resolve_nullable_update(end_binding, &self.end_binding),
            start_arrowhead: self.start_arrowhead.clone(),
            end_arrowhead: self.end_arrowhead.clone(),
            elbowed: self.elbowed,
            fixed_segments: resolve_nullable_update(fixed_segments, &self.fixed_segments),
            start_is_special: resolve_nullable_update(start_is_special, &self.start_is_special),
            end_is_special: resolve_nullable_update(end_is_special, &self.end_is_special),
        }
    }

    pub fn rect(&self) -> DrawRect {
        DrawRect::new(self.x, self.y, self.x + self.width, self.y + self.height)
    }
}

/// Shared execution context for arrow-core style helpers.
///
/// This mirrors the Dart bridge layer while staying fully native to Rust.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EngineContext {
    pub zoom: f64,
    pub is_binding_enabled: bool,
    pub bind_mode: &'static str,
    pub max_coordinate: f64,
}

impl EngineContext {
    /// Creates a new arrow engine context.
    pub const fn new(
        zoom: f64,
        is_binding_enabled: bool,
        bind_mode: &'static str,
        max_coordinate: f64,
    ) -> Self {
        Self {
            zoom,
            is_binding_enabled,
            bind_mode,
            max_coordinate,
        }
    }

    /// Returns a copied context with selectively replaced fields.
    pub fn copy_with(
        self,
        zoom: Option<f64>,
        is_binding_enabled: Option<bool>,
        bind_mode: Option<&'static str>,
        max_coordinate: Option<f64>,
    ) -> Self {
        Self {
            zoom: zoom.unwrap_or(self.zoom),
            is_binding_enabled: is_binding_enabled.unwrap_or(self.is_binding_enabled),
            bind_mode: bind_mode.unwrap_or(self.bind_mode),
            max_coordinate: max_coordinate.unwrap_or(self.max_coordinate),
        }
    }
}

/// Normalized world-space arrow geometry.
///
/// `x` and `y` store the minimum world origin, while [`Self::points`] become
/// local points relative to that origin.
#[derive(Clone, Debug, PartialEq)]
pub struct NormalizedArrowGeometry {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub points: Vec<DrawPoint>,
}

impl NormalizedArrowGeometry {
    /// Creates an empty normalized geometry record.
    pub fn empty() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            points: Vec::new(),
        }
    }
}

/// Normalizes world-space connector points into a stable local frame.
///
/// The Rust port keeps the same conceptual contract as Dart's arrow-core
/// adapter: geometry is converted into a local point set plus a world origin.
pub fn normalize_arrow_from_global_points(
    points: &[DrawPoint],
    max_coordinate: f64,
) -> NormalizedArrowGeometry {
    if points.is_empty() {
        return NormalizedArrowGeometry::empty();
    }

    let mut min_x = f64::INFINITY;
    let mut min_y = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut max_y = f64::NEG_INFINITY;

    for point in points {
        min_x = min_x.min(point.x);
        min_y = min_y.min(point.y);
        max_x = max_x.max(point.x);
        max_y = max_y.max(point.y);
    }

    let origin_x = clamp_coordinate(min_x, max_coordinate);
    let origin_y = clamp_coordinate(min_y, max_coordinate);
    let local_points = points
        .iter()
        .map(|point| DrawPoint::new(point.x - origin_x, point.y - origin_y))
        .collect::<Vec<_>>();

    NormalizedArrowGeometry {
        x: origin_x,
        y: origin_y,
        width: (max_x - min_x).max(0.0),
        height: (max_y - min_y).max(0.0),
        points: local_points,
    }
}

fn clamp_coordinate(value: f64, max_coordinate: f64) -> f64 {
    if !max_coordinate.is_finite() || max_coordinate <= 0.0 {
        return value;
    }
    value.clamp(-max_coordinate, max_coordinate)
}

fn resolve_nullable_update<T: Clone>(update: NullableField<T>, current: &Option<T>) -> Option<T> {
    match update {
        NullableField::Unset => current.clone(),
        NullableField::Null => None,
        NullableField::Value(value) => Some(value),
    }
}

#[cfg(test)]
mod tests {
    use super::{ArrowState, NullableField};
    use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
    use crate::draw::elements::types::arrow::arrow_data::ElbowFixedSegment;
    use crate::draw::types::draw_point::DrawPoint;

    fn binding(id: &str) -> ArrowBinding {
        ArrowBinding::new(
            id.to_owned(),
            DrawPoint::new(0.25, 0.75),
            ArrowBindingMode::Orbit,
        )
    }

    #[test]
    fn copy_with_updates_nullable_binding_and_segment_fields() {
        let state = ArrowState {
            id: "arrow".to_owned(),
            x: 0.0,
            y: 0.0,
            width: 10.0,
            height: 10.0,
            points: vec![DrawPoint::ZERO, DrawPoint::new(10.0, 10.0)],
            start_binding: Some(binding("start")),
            end_binding: Some(binding("end")),
            start_arrowhead: Some("none".to_owned()),
            end_arrowhead: Some("standard".to_owned()),
            elbowed: true,
            fixed_segments: Some(vec![ElbowFixedSegment {
                index: 1,
                start: DrawPoint::new(1.0, 2.0),
                end: DrawPoint::new(3.0, 4.0),
            }]),
            start_is_special: Some(true),
            end_is_special: Some(false),
        };

        let next = state.copy_with(
            None,
            None,
            None,
            None,
            None,
            NullableField::Null,
            NullableField::Value(binding("next-end")),
            NullableField::Null,
            NullableField::Value(false),
            NullableField::Null,
        );

        assert_eq!(next.start_binding, None);
        assert_eq!(next.end_binding, Some(binding("next-end")));
        assert_eq!(next.fixed_segments, None);
        assert_eq!(next.start_is_special, Some(false));
        assert_eq!(next.end_is_special, None);
    }
}
