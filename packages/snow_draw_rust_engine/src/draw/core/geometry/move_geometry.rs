#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// Displacement produced by move gestures.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MoveDisplacement {
    pub dx: f64,
    pub dy: f64,
}

impl MoveDisplacement {
    pub const ZERO: Self = Self { dx: 0.0, dy: 0.0 };

    pub const fn new(dx: f64, dy: f64) -> Self {
        Self { dx, dy }
    }
}

/// Pure move geometry helpers.
///
/// Translated from `MoveGeometry` in:
/// `packages/snow_draw_engine/lib/draw/core/geometry/move_geometry.dart`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct MoveGeometry;

impl MoveGeometry {
    pub const fn calculate_displacement(start: DrawPoint, current: DrawPoint) -> MoveDisplacement {
        MoveDisplacement::new(current.x - start.x, current.y - start.y)
    }
}

#[cfg(test)]
mod tests {
    use super::{MoveDisplacement, MoveGeometry};
    use crate::draw::types::draw_point::DrawPoint;

    #[test]
    fn calculate_displacement_returns_delta_from_start_to_current() {
        let start = DrawPoint::new(10.0, 4.0);
        let current = DrawPoint::new(16.5, -2.5);

        let displacement = MoveGeometry::calculate_displacement(start, current);

        assert_eq!(displacement, MoveDisplacement::new(6.5, -6.5));
    }
}
