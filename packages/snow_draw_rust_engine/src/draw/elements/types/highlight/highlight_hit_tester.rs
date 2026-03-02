use std::any::Any;
use std::fmt;

use super::highlight_data::HighlightData;
use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::HighlightShape;

/// Hit tester for highlight elements.
///
/// Mirrors Dart `HighlightHitTester` behavior through
/// [`Self::hit_test_highlight`], including runtime payload validation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HighlightHitTester;

/// Highlight-only element snapshot used by [`HighlightHitTester`].
pub struct HighlightHitTestElement<'a> {
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a dyn Any,
}

/// Runtime mismatch returned when non-highlight payload data is used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HighlightHitTestError;

impl HighlightHitTestError {
    fn wrong_data_type() -> Self {
        Self
    }
}

impl fmt::Display for HighlightHitTestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("HighlightHitTester can only hit test HighlightData")
    }
}

impl std::error::Error for HighlightHitTestError {}

impl HighlightHitTester {
    /// Hit-tests a highlight element that carries payload data and rotation.
    ///
    /// Returns an error when `element.data` is not `HighlightData`, matching
    /// the Dart `StateError` behavior.
    pub fn hit_test_highlight(
        &self,
        element: &HighlightHitTestElement<'_>,
        position: DrawPoint,
        tolerance: f64,
    ) -> Result<bool, HighlightHitTestError> {
        let Some(data) = element.data.downcast_ref::<HighlightData>() else {
            return Err(HighlightHitTestError::wrong_data_type());
        };

        let rect = element.rect;
        let local_position = if element.rotation == 0.0 {
            position
        } else {
            ElementSpace::new(element.rotation, rect.center()).from_world(position)
        };

        let hit = match data.shape {
            HighlightShape::Rectangle => {
                test_rect_stroke(rect, local_position, data.stroke_width, tolerance)
                    || rect.contains_point(local_position)
            }
            HighlightShape::Ellipse => {
                test_ellipse_stroke(rect, local_position, data.stroke_width, tolerance)
                    || ellipse_contains(
                        local_position.x - rect.center_x(),
                        local_position.y - rect.center_y(),
                        rect.width() / 2.0,
                        rect.height() / 2.0,
                    )
            }
        };

        Ok(hit)
    }
}

impl ElementHitTester for HighlightHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        // The shared fallback `ElementState` currently exposes only `rect`,
        // so this path performs tolerant axis-aligned bounds hit testing.
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

fn ellipse_contains(dx: f64, dy: f64, rx: f64, ry: f64) -> bool {
    if rx <= 0.0 || ry <= 0.0 {
        return false;
    }

    let nx = dx / rx;
    let ny = dy / ry;
    (nx * nx) + (ny * ny) <= 1.0
}

fn test_rect_stroke(
    rect: DrawRect,
    position: DrawPoint,
    stroke_width: f64,
    tolerance: f64,
) -> bool {
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

    let inner_min_x = rect.min_x + stroke_margin;
    let inner_max_x = rect.max_x - stroke_margin;
    let inner_min_y = rect.min_y + stroke_margin;
    let inner_max_y = rect.max_y - stroke_margin;

    inner_min_x >= inner_max_x
        || inner_min_y >= inner_max_y
        || position.x <= inner_min_x
        || position.x >= inner_max_x
        || position.y <= inner_min_y
        || position.y >= inner_max_y
}

fn test_ellipse_stroke(
    rect: DrawRect,
    position: DrawPoint,
    stroke_width: f64,
    tolerance: f64,
) -> bool {
    if stroke_width <= 0.0 {
        return false;
    }

    let rx = rect.width() / 2.0;
    let ry = rect.height() / 2.0;
    if rx <= 0.0 || ry <= 0.0 {
        return false;
    }

    let margin = (stroke_width / 2.0) + tolerance;
    let outer_rx = rx + margin;
    let outer_ry = ry + margin;
    let dx = position.x - rect.center_x();
    let dy = position.y - rect.center_y();

    if !ellipse_contains(dx, dy, outer_rx, outer_ry) {
        return false;
    }

    let inner_rx = rx - margin;
    let inner_ry = ry - margin;
    inner_rx <= 0.0 || inner_ry <= 0.0 || !ellipse_contains(dx, dy, inner_rx, inner_ry)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::draw_color::DrawColor;

    fn highlight_data(shape: HighlightShape, stroke_width: f64) -> HighlightData {
        HighlightData {
            shape,
            stroke_width,
            color: DrawColor::new(0xFF11_2233),
            stroke_color: DrawColor::new(0xFF22_3344),
        }
    }

    #[test]
    fn hit_test_highlight_rejects_non_highlight_data() {
        let tester = HighlightHitTester;
        let marker = "not-highlight-data";
        let element = HighlightHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            data: &marker,
        };

        let result = tester.hit_test_highlight(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert!(result.is_err());
    }

    #[test]
    fn rectangle_hit_tests_fill_and_stroke() {
        let tester = HighlightHitTester;
        let data = highlight_data(HighlightShape::Rectangle, 10.0);
        let element = HighlightHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 100.0, 60.0),
            rotation: 0.0,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(50.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(2.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(120.0, 30.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn ellipse_hit_tests_fill_and_stroke() {
        let tester = HighlightHitTester;
        let data = highlight_data(HighlightShape::Ellipse, 8.0);
        let element = HighlightHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 100.0, 60.0),
            rotation: 0.0,
            data: &data,
        };

        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(50.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(100.0, 30.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_highlight(&element, DrawPoint::new(120.0, 30.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn hit_test_highlight_handles_rotation() {
        let tester = HighlightHitTester;
        let data = highlight_data(HighlightShape::Rectangle, 0.0);
        let rect = DrawRect::new(0.0, 0.0, 20.0, 10.0);
        let rotation = std::f64::consts::FRAC_PI_2;
        let world_inside =
            ElementSpace::new(rotation, rect.center()).to_world(DrawPoint::new(5.0, 5.0));
        let element = HighlightHitTestElement {
            rect,
            rotation,
            data: &data,
        };

        let result = tester.hit_test_highlight(&element, world_inside, 0.0);
        assert_eq!(result, Ok(true));
    }
}
