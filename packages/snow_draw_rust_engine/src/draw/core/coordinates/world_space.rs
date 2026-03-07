#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use super::coordinate_space::CoordinateSpace;

/// Coordinate space that is identical to world coordinates.
///
/// In this space there is no rotation and no translation, so conversions
/// to/from world are identity operations.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct WorldSpace;

impl WorldSpace {
    pub const fn new() -> Self {
        Self
    }

    pub const fn rotation(self) -> f64 {
        0.0
    }

    pub const fn origin(self) -> DrawPoint {
        DrawPoint::ZERO
    }

    pub const fn from_world(self, world_point: DrawPoint) -> DrawPoint {
        world_point
    }

    pub const fn to_world(self, local_point: DrawPoint) -> DrawPoint {
        local_point
    }

    pub const fn rotate_vector_to_world(self, local_vector: DrawPoint) -> DrawPoint {
        local_vector
    }

    pub const fn rotate_vector_to_local(self, world_vector: DrawPoint) -> DrawPoint {
        world_vector
    }
}

impl CoordinateSpace for WorldSpace {
    fn rotation(&self) -> f64 {
        0.0
    }

    fn origin(&self) -> DrawPoint {
        DrawPoint::ZERO
    }

    fn from_world(&self, world_point: DrawPoint) -> DrawPoint {
        world_point
    }

    fn to_world(&self, local_point: DrawPoint) -> DrawPoint {
        local_point
    }
}
