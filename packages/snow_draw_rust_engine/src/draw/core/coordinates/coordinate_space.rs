#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// A coordinate space that can convert points to and from world coordinates.
///
/// This is primarily used for edit operations where we need to reason about a
/// rotated overlay (multi-select) or a rotated element.
pub trait CoordinateSpace {
    fn rotation(&self) -> f64;
    fn origin(&self) -> DrawPoint;

    fn from_world(&self, world_point: DrawPoint) -> DrawPoint;
    fn to_world(&self, local_point: DrawPoint) -> DrawPoint;

    fn rotate_vector_to_world(&self, local_vector: DrawPoint) -> DrawPoint {
        let rotation = self.rotation();
        if rotation == 0.0 {
            return local_vector;
        }

        rotate(local_vector.x, local_vector.y, rotation)
    }

    fn rotate_vector_to_local(&self, world_vector: DrawPoint) -> DrawPoint {
        let rotation = self.rotation();
        if rotation == 0.0 {
            return world_vector;
        }

        rotate(world_vector.x, world_vector.y, -rotation)
    }

    /// Rotates `point` around `center` by `angle`.
    fn rotate_point(&self, point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
        if angle == 0.0 {
            return point;
        }

        let rotated = rotate(point.x - center.x, point.y - center.y, angle);
        DrawPoint::new(center.x + rotated.x, center.y + rotated.y)
    }
}

fn rotate(x: f64, y: f64, angle: f64) -> DrawPoint {
    let cos_a = angle.cos();
    let sin_a = angle.sin();
    DrawPoint::new(x * cos_a - y * sin_a, x * sin_a + y * cos_a)
}
