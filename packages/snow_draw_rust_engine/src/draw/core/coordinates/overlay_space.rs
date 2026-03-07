#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use core::fmt;
use core::hash::{Hash, Hasher};

/// Coordinate space for multi-select overlay transforms.
///
/// This space represents the rotation of a multi-select overlay around its
/// center. Use this when transforming points relative to a multi-select
/// selection overlay.
///
/// The transform behavior is intentionally identical to element-local space,
/// but this dedicated type prevents mixing coordinate domains by mistake.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OverlaySpace {
    pub rotation: f64,
    pub origin: DrawPoint,
}

impl OverlaySpace {
    pub const fn new(rotation: f64, origin: DrawPoint) -> Self {
        Self { rotation, origin }
    }

    pub fn from_world(self, world_point: DrawPoint) -> DrawPoint {
        rotate_point(world_point, self.origin, -self.rotation)
    }

    pub fn to_world(self, local_point: DrawPoint) -> DrawPoint {
        rotate_point(local_point, self.origin, self.rotation)
    }

    pub fn rotate_vector_to_world(self, local_vector: DrawPoint) -> DrawPoint {
        rotate_vector(local_vector, self.rotation)
    }

    pub fn rotate_vector_to_local(self, world_vector: DrawPoint) -> DrawPoint {
        rotate_vector(world_vector, -self.rotation)
    }
}

impl Hash for OverlaySpace {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.rotation.to_bits().hash(state);
        self.origin.hash(state);
    }
}

impl fmt::Display for OverlaySpace {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "OverlaySpace(rotation: {}, origin: {})",
            self.rotation, self.origin
        )
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

    let rotated = rotate_vector(
        DrawPoint::new(point.x - center.x, point.y - center.y),
        angle,
    );
    DrawPoint::new(center.x + rotated.x, center.y + rotated.y)
}
