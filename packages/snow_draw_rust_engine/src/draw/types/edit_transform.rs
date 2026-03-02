#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as ArrowEndpointBinding, ElbowFixedSegment as ArrowElbowFixedSegment,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Editable transform state for an edit session.
///
/// This mirrors the sealed `EditTransform` hierarchy from Dart as a Rust enum.
#[derive(Clone, Debug, PartialEq)]
pub enum EditTransform {
    Move(MoveTransform),
    Resize(ResizeTransform),
    Rotate(RotateTransform),
    ArrowPoint(ArrowPointTransform),
}

impl EditTransform {
    pub fn apply_to_point(&self, point: DrawPoint, pivot: Option<DrawPoint>) -> DrawPoint {
        match self {
            Self::Move(transform) => transform.apply_to_point(point, pivot),
            Self::Resize(transform) => transform.apply_to_point(point, pivot),
            Self::Rotate(transform) => transform.apply_to_point(point, pivot),
            Self::ArrowPoint(transform) => transform.apply_to_point(point, pivot),
        }
    }

    pub fn apply_to_rect(&self, rect: DrawRect, pivot: Option<DrawPoint>) -> DrawRect {
        match self {
            Self::Move(transform) => transform.apply_to_rect(rect, pivot),
            Self::Resize(transform) => transform.apply_to_rect(rect, pivot),
            Self::Rotate(transform) => transform.apply_to_rect(rect, pivot),
            Self::ArrowPoint(transform) => transform.apply_to_rect(rect, pivot),
        }
    }

    pub fn is_identity(&self) -> bool {
        match self {
            Self::Move(transform) => transform.is_identity(),
            Self::Resize(transform) => transform.is_identity(),
            Self::Rotate(transform) => transform.is_identity(),
            Self::ArrowPoint(transform) => transform.is_identity(),
        }
    }
}

impl Default for EditTransform {
    fn default() -> Self {
        Self::Move(MoveTransform::ZERO)
    }
}

impl From<MoveTransform> for EditTransform {
    fn from(value: MoveTransform) -> Self {
        Self::Move(value)
    }
}

impl From<ResizeTransform> for EditTransform {
    fn from(value: ResizeTransform) -> Self {
        Self::Resize(value)
    }
}

impl From<RotateTransform> for EditTransform {
    fn from(value: RotateTransform) -> Self {
        Self::Rotate(value)
    }
}

impl From<ArrowPointTransform> for EditTransform {
    fn from(value: ArrowPointTransform) -> Self {
        Self::ArrowPoint(value)
    }
}

/// Translation of Dart `MoveTransform`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MoveTransform {
    pub dx: f64,
    pub dy: f64,
}

impl MoveTransform {
    pub const ZERO: Self = Self { dx: 0.0, dy: 0.0 };

    pub const fn new(dx: f64, dy: f64) -> Self {
        Self { dx, dy }
    }

    pub fn is_identity(&self) -> bool {
        self.dx == 0.0 && self.dy == 0.0
    }

    pub fn apply_to_point(&self, point: DrawPoint, _pivot: Option<DrawPoint>) -> DrawPoint {
        point.translate(DrawPoint::new(self.dx, self.dy))
    }

    pub fn apply_to_rect(&self, rect: DrawRect, _pivot: Option<DrawPoint>) -> DrawRect {
        rect.translate(DrawPoint::new(self.dx, self.dy))
    }
}

/// Translation of Dart `ResizeTransform`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResizeTransform {
    pub current_position: DrawPoint,
    pub new_selection_bounds: Option<DrawRect>,
    pub scale_x: Option<f64>,
    pub scale_y: Option<f64>,
    pub anchor: Option<DrawPoint>,
}

impl ResizeTransform {
    pub fn new(
        current_position: DrawPoint,
        new_selection_bounds: Option<DrawRect>,
        scale_x: Option<f64>,
        scale_y: Option<f64>,
        anchor: Option<DrawPoint>,
    ) -> Self {
        let all_missing = new_selection_bounds.is_none()
            && scale_x.is_none()
            && scale_y.is_none()
            && anchor.is_none();
        let all_present = new_selection_bounds.is_some()
            && scale_x.is_some()
            && scale_y.is_some()
            && anchor.is_some();

        debug_assert!(
            all_missing || all_present,
            "ResizeTransform must be either fully complete or fully incomplete."
        );

        Self {
            current_position,
            new_selection_bounds,
            scale_x,
            scale_y,
            anchor,
        }
    }

    pub fn incomplete(current_position: DrawPoint) -> Self {
        Self::new(current_position, None, None, None, None)
    }

    pub fn complete(
        current_position: DrawPoint,
        new_selection_bounds: DrawRect,
        scale_x: f64,
        scale_y: f64,
        anchor: DrawPoint,
    ) -> Self {
        Self::new(
            current_position,
            Some(new_selection_bounds),
            Some(scale_x),
            Some(scale_y),
            Some(anchor),
        )
    }

    pub fn is_complete(&self) -> bool {
        self.new_selection_bounds.is_some()
    }

    pub fn is_identity(&self) -> bool {
        if !self.is_complete() {
            return true;
        }

        matches!((self.scale_x, self.scale_y), (Some(1.0), Some(1.0)))
    }

    pub fn apply_to_point(&self, point: DrawPoint, pivot: Option<DrawPoint>) -> DrawPoint {
        let Some((scale_x, scale_y, anchor)) = self.complete_parameters() else {
            return point;
        };

        scale_point(point, pivot.unwrap_or(anchor), scale_x, scale_y)
    }

    pub fn apply_to_rect(&self, rect: DrawRect, pivot: Option<DrawPoint>) -> DrawRect {
        let Some((scale_x, scale_y, anchor)) = self.complete_parameters() else {
            return rect;
        };

        let resolved_pivot = pivot.unwrap_or(anchor);

        let top_left = scale_point(
            DrawPoint::new(rect.min_x, rect.min_y),
            resolved_pivot,
            scale_x,
            scale_y,
        );
        let top_right = scale_point(
            DrawPoint::new(rect.max_x, rect.min_y),
            resolved_pivot,
            scale_x,
            scale_y,
        );
        let bottom_left = scale_point(
            DrawPoint::new(rect.min_x, rect.max_y),
            resolved_pivot,
            scale_x,
            scale_y,
        );
        let bottom_right = scale_point(
            DrawPoint::new(rect.max_x, rect.max_y),
            resolved_pivot,
            scale_x,
            scale_y,
        );

        bounding_rect(top_left, top_right, bottom_left, bottom_right)
    }

    fn complete_parameters(&self) -> Option<(f64, f64, DrawPoint)> {
        match (
            self.new_selection_bounds,
            self.scale_x,
            self.scale_y,
            self.anchor,
        ) {
            (Some(_), Some(scale_x), Some(scale_y), Some(anchor)) => {
                Some((scale_x, scale_y, anchor))
            }
            _ => None,
        }
    }
}

/// Translation of Dart `RotateTransform`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RotateTransform {
    pub raw_accumulated_angle: f64,
    pub applied_angle: f64,
    pub last_raw_angle: Option<f64>,
}

impl RotateTransform {
    pub const ZERO: Self = Self {
        raw_accumulated_angle: 0.0,
        applied_angle: 0.0,
        last_raw_angle: None,
    };

    pub const fn new(
        raw_accumulated_angle: f64,
        applied_angle: f64,
        last_raw_angle: Option<f64>,
    ) -> Self {
        Self {
            raw_accumulated_angle,
            applied_angle,
            last_raw_angle,
        }
    }

    pub fn copy_with(
        &self,
        raw_accumulated_angle: Option<f64>,
        applied_angle: Option<f64>,
        last_raw_angle: Option<f64>,
        clear_last_raw_angle: bool,
    ) -> Self {
        Self {
            raw_accumulated_angle: raw_accumulated_angle.unwrap_or(self.raw_accumulated_angle),
            applied_angle: applied_angle.unwrap_or(self.applied_angle),
            last_raw_angle: if clear_last_raw_angle {
                None
            } else {
                last_raw_angle.or(self.last_raw_angle)
            },
        }
    }

    pub fn is_identity(&self) -> bool {
        self.applied_angle == 0.0
    }

    pub fn apply_to_point(&self, point: DrawPoint, pivot: Option<DrawPoint>) -> DrawPoint {
        let origin = pivot.unwrap_or(DrawPoint::ZERO);
        let cos_a = self.applied_angle.cos();
        let sin_a = self.applied_angle.sin();
        let dx = point.x - origin.x;
        let dy = point.y - origin.y;

        DrawPoint::new(
            dx * cos_a - dy * sin_a + origin.x,
            dx * sin_a + dy * cos_a + origin.y,
        )
    }

    pub fn apply_to_rect(&self, rect: DrawRect, pivot: Option<DrawPoint>) -> DrawRect {
        let origin = pivot.unwrap_or(DrawPoint::ZERO);
        let new_center = self.apply_to_point(rect.center(), Some(origin));
        let half_width = rect.width() / 2.0;
        let half_height = rect.height() / 2.0;

        DrawRect::new(
            new_center.x - half_width,
            new_center.y - half_height,
            new_center.x + half_width,
            new_center.y + half_height,
        )
    }
}

/// Arrow endpoint binding payload used by edit transforms.
pub type ArrowBinding = ArrowEndpointBinding;

/// Elbow fixed-segment payload used by edit transforms.
pub type ElbowFixedSegment = ArrowElbowFixedSegment;

/// Translation of Dart `ArrowPointTransform`.
#[derive(Clone, Debug)]
pub struct ArrowPointTransform {
    pub current_position: DrawPoint,
    pub points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub active_index: Option<usize>,
    pub did_insert: bool,
    pub should_delete: bool,
    pub has_changes: bool,
}

impl ArrowPointTransform {
    pub fn new(current_position: DrawPoint, points: Vec<DrawPoint>) -> Self {
        Self {
            current_position,
            points,
            fixed_segments: None,
            start_binding: None,
            end_binding: None,
            active_index: None,
            did_insert: false,
            should_delete: false,
            has_changes: false,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_state(
        current_position: DrawPoint,
        points: Vec<DrawPoint>,
        fixed_segments: Option<Vec<ElbowFixedSegment>>,
        start_binding: Option<ArrowBinding>,
        end_binding: Option<ArrowBinding>,
        active_index: Option<usize>,
        did_insert: bool,
        should_delete: bool,
        has_changes: bool,
    ) -> Self {
        Self {
            current_position,
            points,
            fixed_segments,
            start_binding,
            end_binding,
            active_index,
            did_insert,
            should_delete,
            has_changes,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        &self,
        current_position: Option<DrawPoint>,
        points: Option<Vec<DrawPoint>>,
        fixed_segments: Option<Option<Vec<ElbowFixedSegment>>>,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
        active_index: Option<usize>,
        did_insert: Option<bool>,
        should_delete: Option<bool>,
        has_changes: Option<bool>,
    ) -> Self {
        Self {
            current_position: current_position.unwrap_or(self.current_position),
            points: points.unwrap_or_else(|| self.points.clone()),
            fixed_segments: match fixed_segments {
                Some(value) => value,
                None => self.fixed_segments.clone(),
            },
            start_binding: match start_binding {
                Some(value) => value,
                None => self.start_binding.clone(),
            },
            end_binding: match end_binding {
                Some(value) => value,
                None => self.end_binding.clone(),
            },
            active_index: active_index.or(self.active_index),
            did_insert: did_insert.unwrap_or(self.did_insert),
            should_delete: should_delete.unwrap_or(self.should_delete),
            has_changes: has_changes.unwrap_or(self.has_changes),
        }
    }

    pub fn is_identity(&self) -> bool {
        !self.has_changes
    }

    pub fn apply_to_point(&self, point: DrawPoint, _pivot: Option<DrawPoint>) -> DrawPoint {
        point
    }

    pub fn apply_to_rect(&self, rect: DrawRect, _pivot: Option<DrawPoint>) -> DrawRect {
        rect
    }
}

impl PartialEq for ArrowPointTransform {
    fn eq(&self, other: &Self) -> bool {
        self.current_position == other.current_position
            && point_list_equals(&self.points, &other.points)
            && fixed_segment_structure_equals(
                self.fixed_segments.as_deref(),
                other.fixed_segments.as_deref(),
            )
            && self.start_binding == other.start_binding
            && self.end_binding == other.end_binding
            && self.active_index == other.active_index
            && self.did_insert == other.did_insert
            && self.should_delete == other.should_delete
            && self.has_changes == other.has_changes
    }
}

fn point_list_equals(left: &[DrawPoint], right: &[DrawPoint]) -> bool {
    left == right
}

fn fixed_segment_structure_equals(
    left: Option<&[ElbowFixedSegment]>,
    right: Option<&[ElbowFixedSegment]>,
) -> bool {
    left == right
}

fn scale_point(point: DrawPoint, pivot: DrawPoint, scale_x: f64, scale_y: f64) -> DrawPoint {
    DrawPoint::new(
        (point.x - pivot.x) * scale_x + pivot.x,
        (point.y - pivot.y) * scale_y + pivot.y,
    )
}

fn bounding_rect(a: DrawPoint, b: DrawPoint, c: DrawPoint, d: DrawPoint) -> DrawRect {
    let min_x = a.x.min(b.x).min(c.x.min(d.x));
    let min_y = a.y.min(b.y).min(c.y.min(d.y));
    let max_x = a.x.max(b.x).max(c.x.max(d.x));
    let max_y = a.y.max(b.y).max(c.y.max(d.y));
    DrawRect::new(min_x, min_y, max_x, max_y)
}
