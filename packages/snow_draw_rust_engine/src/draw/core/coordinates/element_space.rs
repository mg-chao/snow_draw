#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use std::fmt;

/// Coordinate space for a single element's local frame.
///
/// This space represents an element's rotation around its center, and provides
/// helpers to transform points between world and element-local coordinates.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ElementSpace {
    pub rotation: f64,
    pub origin: DrawPoint,
}

impl ElementSpace {
    pub const fn new(rotation: f64, origin: DrawPoint) -> Self {
        Self { rotation, origin }
    }

    pub fn from_world(self, world_point: DrawPoint) -> DrawPoint {
        self.rotate_point(world_point, self.origin, -self.rotation)
    }

    pub fn to_world(self, local_point: DrawPoint) -> DrawPoint {
        self.rotate_point(local_point, self.origin, self.rotation)
    }

    pub fn rotate_vector_to_world(self, local_vector: DrawPoint) -> DrawPoint {
        if self.rotation == 0.0 {
            return local_vector;
        }
        rotate(local_vector.x, local_vector.y, self.rotation)
    }

    pub fn rotate_vector_to_local(self, world_vector: DrawPoint) -> DrawPoint {
        if self.rotation == 0.0 {
            return world_vector;
        }
        rotate(world_vector.x, world_vector.y, -self.rotation)
    }

    /// Rotates `point` around `center` by `angle`.
    pub fn rotate_point(self, point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
        if angle == 0.0 {
            return point;
        }

        let rotated = rotate(point.x - center.x, point.y - center.y, angle);
        DrawPoint::new(center.x + rotated.x, center.y + rotated.y)
    }
}

impl fmt::Display for ElementSpace {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ElementSpace(rotation: {}, origin: {})",
            self.rotation, self.origin
        )
    }
}

fn rotate(x: f64, y: f64, angle: f64) -> DrawPoint {
    let cos_a = angle.cos();
    let sin_a = angle.sin();
    DrawPoint::new(x * cos_a - y * sin_a, x * sin_a + y * cos_a)
}
