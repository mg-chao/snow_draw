use std::any::Any;
use std::fmt;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::rectangle_data::RectangleData;

/// Hit tester for rectangle elements.
///
/// Mirrors Dart `RectangleHitTester` behavior for the typed path through
/// [`Self::hit_test_rectangle`], including the runtime RectangleData guard.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RectangleHitTester;

impl RectangleHitTester {
    /// Hit-tests a rectangle element that carries payload data and rotation.
    ///
    /// Returns an error when `element.data` is not `RectangleData`, matching
    /// the Dart `StateError` behavior.
    pub fn hit_test_rectangle(
        &self,
        element: &RectangleHitTestElement<'_>,
        position: DrawPoint,
        tolerance: f64,
    ) -> Result<bool, RectangleHitTestError> {
        let Some(data) = element.data.downcast_ref::<RectangleData>() else {
            return Err(RectangleHitTestError::wrong_data_type());
        };

        let rect = element.rect;
        let local_position = resolve_element_local_position(rect, element.rotation, position);
        if hits_stroke(rect, local_position, data.stroke_width, tolerance) {
            return Ok(true);
        }

        let fill_opacity = data.fill_color.a() * element.opacity;
        Ok(fill_opacity > 0.0 && rect.contains_point(local_position))
    }
}

impl ElementHitTester for RectangleHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        // The shared fallback `ElementState` currently exposes only `rect`,
        // so this path performs axis-aligned bounds hit testing.
        let expanded = DrawRect::new(
            element.rect.min_x - tolerance,
            element.rect.min_y - tolerance,
            element.rect.max_x + tolerance,
            element.rect.max_y + tolerance,
        );
        expanded.contains_point(position)
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

/// Rectangle-only element snapshot used by
/// [`RectangleHitTester::hit_test_rectangle`].
#[derive(Debug)]
pub struct RectangleHitTestElement<'a> {
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub data: &'a dyn Any,
}

/// Runtime mismatch returned when non-rectangle payload data is used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RectangleHitTestError;

impl RectangleHitTestError {
    fn wrong_data_type() -> Self {
        Self
    }
}

impl fmt::Display for RectangleHitTestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("RectangleHitTester can only hit test RectangleData")
    }
}

impl std::error::Error for RectangleHitTestError {}

fn resolve_element_local_position(rect: DrawRect, rotation: f64, position: DrawPoint) -> DrawPoint {
    if rotation == 0.0 {
        return position;
    }

    ElementSpace::new(rotation, rect.center()).from_world(position)
}

fn hits_stroke(rect: DrawRect, position: DrawPoint, stroke_width: f64, tolerance: f64) -> bool {
    if stroke_width <= 0.0 {
        return false;
    }

    let stroke_margin = (stroke_width / 2.0) + tolerance;
    let outer_rect = DrawRect::new(
        rect.min_x - stroke_margin,
        rect.min_y - stroke_margin,
        rect.max_x + stroke_margin,
        rect.max_y + stroke_margin,
    );
    if !outer_rect.contains_point(position) {
        return false;
    }

    let inner_rect = DrawRect::new(
        rect.min_x + stroke_margin,
        rect.min_y + stroke_margin,
        rect.max_x - stroke_margin,
        rect.max_y - stroke_margin,
    );
    if inner_rect.min_x >= inner_rect.max_x || inner_rect.min_y >= inner_rect.max_y {
        return true;
    }

    !is_strictly_inside(inner_rect, position)
}

fn is_strictly_inside(rect: DrawRect, position: DrawPoint) -> bool {
    position.x > rect.min_x
        && position.x < rect.max_x
        && position.y > rect.min_y
        && position.y < rect.max_y
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::draw_color::DrawColor;

    fn rectangle_data(stroke_width: f64, fill_argb: u32) -> RectangleData {
        RectangleData {
            stroke_width,
            fill_color: DrawColor::new(fill_argb),
            ..RectangleData::default()
        }
    }

    #[test]
    fn hit_test_rectangle_rejects_non_rectangle_data() {
        let tester = RectangleHitTester;
        let marker = "not-rectangle-data";
        let element = RectangleHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            opacity: 1.0,
            data: &marker,
        };

        let result = tester.hit_test_rectangle(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert!(result.is_err());
    }

    #[test]
    fn hit_test_rectangle_hits_stroke_when_fill_is_transparent() {
        let tester = RectangleHitTester;
        let data = rectangle_data(10.0, 0x0000_0000);
        let element = RectangleHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 100.0, 60.0),
            rotation: 0.0,
            opacity: 1.0,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(2.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(50.0, 30.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn hit_test_rectangle_hits_fill_when_visible() {
        let tester = RectangleHitTester;
        let data = rectangle_data(0.0, 0xFF12_3456);
        let element = RectangleHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 100.0, 60.0),
            rotation: 0.0,
            opacity: 0.5,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(50.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(120.0, 30.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn hit_test_rectangle_respects_element_opacity_for_fill() {
        let tester = RectangleHitTester;
        let data = rectangle_data(0.0, 0xFFAA_BBCC);
        let element = RectangleHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 100.0, 60.0),
            rotation: 0.0,
            opacity: 0.0,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(50.0, 30.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn hit_test_rectangle_handles_rotation() {
        let tester = RectangleHitTester;
        let data = rectangle_data(0.0, 0xFF11_2233);
        let rect = DrawRect::new(0.0, 0.0, 20.0, 10.0);
        let rotation = std::f64::consts::FRAC_PI_2;
        let world_inside =
            ElementSpace::new(rotation, rect.center()).to_world(DrawPoint::new(5.0, 5.0));
        let element = RectangleHitTestElement {
            rect,
            rotation,
            opacity: 1.0,
            data: &data,
        };

        let result = tester.hit_test_rectangle(&element, world_inside, 0.0);
        assert_eq!(result, Ok(true));
    }

    #[test]
    fn hit_test_rectangle_hits_when_stroke_covers_entire_rect() {
        let tester = RectangleHitTester;
        let data = rectangle_data(24.0, 0x0000_0000);
        let element = RectangleHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 20.0, 10.0),
            rotation: 0.0,
            opacity: 1.0,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_rectangle(&element, DrawPoint::new(10.0, 5.0), 0.0),
            Ok(true)
        );
    }
}
