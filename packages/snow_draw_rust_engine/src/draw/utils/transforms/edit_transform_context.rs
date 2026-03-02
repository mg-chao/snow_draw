#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;

/// Coordinate transform helpers used by resize calculations.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EditTransformContext {
    /// Selection bounds at the start of the resize operation.
    pub start_bounds: DrawRect,

    /// Selection center in world coordinates.
    pub center: DrawPoint,

    /// Selection overlay transform space.
    pub overlay_space: OverlaySpace,
}

impl EditTransformContext {
    pub fn new(start_bounds: DrawRect, rotation: f64, center: DrawPoint) -> Self {
        Self {
            start_bounds,
            center,
            overlay_space: OverlaySpace::new(rotation, center),
        }
    }

    /// Aspect ratio of the start bounds (width / height).
    /// Returns `None` if width or height is zero.
    pub fn aspect_ratio(self) -> Option<f64> {
        let width = self.start_bounds.width();
        let height = self.start_bounds.height();
        if width == 0.0 || height == 0.0 {
            None
        } else {
            Some(width / height)
        }
    }

    /// Transforms pointer position with handle offset applied.
    pub fn transform_pointer_with_offset(
        self,
        current_pointer_world: DrawPoint,
        handle_offset_local: DrawPoint,
    ) -> DrawPoint {
        current_pointer_world
            + self
                .overlay_space
                .rotate_vector_to_world(handle_offset_local)
    }

    /// Gets the anchor point for a resize operation.
    pub fn get_anchor_point(self, mode: ResizeMode, resize_from_center: bool) -> DrawPoint {
        if resize_from_center {
            self.center
        } else {
            self.overlay_space
                .to_world(opposite_bound_point_local(self.start_bounds, mode))
        }
    }

    /// Gets the padding offset for a resize mode.
    pub fn get_padding_offset(self, mode: ResizeMode, padding: f64) -> DrawPoint {
        self.overlay_space
            .rotate_vector_to_world(handle_padding_offset_local(mode, padding))
    }
}

/// Coordinate space for multi-select overlay transforms.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OverlaySpace {
    pub rotation: f64,
    pub origin: DrawPoint,
}

impl OverlaySpace {
    pub const fn new(rotation: f64, origin: DrawPoint) -> Self {
        Self { rotation, origin }
    }

    pub fn to_world(self, local_point: DrawPoint) -> DrawPoint {
        rotate_point(local_point, self.origin, self.rotation)
    }

    pub fn rotate_vector_to_world(self, local_vector: DrawPoint) -> DrawPoint {
        rotate_vector(local_vector, self.rotation)
    }
}

/// Returns the opposite anchor point for a given resize handle mode.
pub fn opposite_bound_point_local(rect: DrawRect, mode: ResizeMode) -> DrawPoint {
    match mode {
        ResizeMode::TopLeft => DrawPoint::new(rect.max_x, rect.max_y),
        ResizeMode::TopRight => DrawPoint::new(rect.min_x, rect.max_y),
        ResizeMode::BottomRight => DrawPoint::new(rect.min_x, rect.min_y),
        ResizeMode::BottomLeft => DrawPoint::new(rect.max_x, rect.min_y),
        ResizeMode::Top => DrawPoint::new(rect.center_x(), rect.max_y),
        ResizeMode::Bottom => DrawPoint::new(rect.center_x(), rect.min_y),
        ResizeMode::Left => DrawPoint::new(rect.max_x, rect.center_y()),
        ResizeMode::Right => DrawPoint::new(rect.min_x, rect.center_y()),
    }
}

fn handle_padding_offset_local(mode: ResizeMode, padding: f64) -> DrawPoint {
    match mode {
        ResizeMode::TopLeft => DrawPoint::new(-padding, -padding),
        ResizeMode::TopRight => DrawPoint::new(padding, -padding),
        ResizeMode::BottomRight => DrawPoint::new(padding, padding),
        ResizeMode::BottomLeft => DrawPoint::new(-padding, padding),
        ResizeMode::Top => DrawPoint::new(0.0, -padding),
        ResizeMode::Bottom => DrawPoint::new(0.0, padding),
        ResizeMode::Left => DrawPoint::new(-padding, 0.0),
        ResizeMode::Right => DrawPoint::new(padding, 0.0),
    }
}

fn rotate_vector(vector: DrawPoint, angle: f64) -> DrawPoint {
    if angle == 0.0 {
        return vector;
    }
    let cos_a = angle.cos();
    let sin_a = angle.sin();
    DrawPoint::new(
        vector.x * cos_a - vector.y * sin_a,
        vector.x * sin_a + vector.y * cos_a,
    )
}

fn rotate_point(point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
    if angle == 0.0 {
        return point;
    }
    let translated = DrawPoint::new(point.x - center.x, point.y - center.y);
    let rotated = rotate_vector(translated, angle);
    DrawPoint::new(center.x + rotated.x, center.y + rotated.y)
}
