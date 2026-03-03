use std::any::Any;
use std::fmt;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::text_data::TextData;

/// Hit tester for text elements.
///
/// Mirrors Dart `TextHitTester` behavior through [`Self::hit_test_text`],
/// including runtime payload validation against `TextData`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TextHitTester;

impl TextHitTester {
    /// Hit-tests a text element that carries payload data and rotation.
    ///
    /// Returns an error when `element.data` is not `TextData`, matching the
    /// Dart `StateError` behavior.
    pub fn hit_test_text(
        &self,
        element: &TextHitTestElement<'_>,
        position: DrawPoint,
        tolerance: f64,
    ) -> Result<bool, TextHitTestError> {
        if element.data.downcast_ref::<TextData>().is_none() {
            return Err(TextHitTestError::wrong_data_type());
        }

        Ok(hit_test_rotated_rect(
            element.rect,
            element.rotation,
            position,
            tolerance,
        ))
    }
}

impl ElementHitTester for TextHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        assert!(
            element.type_id().as_str() == TextData::TYPE_ID_TOKEN,
            "TextHitTester can only hit test TextData (got {})",
            element.type_id().as_str()
        );

        let data = TextData::from_json_value(&element.data.to_json_value())
            .expect("TextHitTester received invalid TextData payload");

        self.hit_test_text(
            &TextHitTestElement {
                rect: element.rect,
                rotation: element.rotation,
                data: &data,
            },
            position,
            tolerance,
        )
        .unwrap_or(false)
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        element.rect
    }
}

/// Text-only element snapshot used by [`TextHitTester::hit_test_text`].
#[derive(Debug)]
pub struct TextHitTestElement<'a> {
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a dyn Any,
}

/// Runtime mismatch returned when non-text payload data is used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TextHitTestError;

impl TextHitTestError {
    fn wrong_data_type() -> Self {
        Self
    }
}

impl fmt::Display for TextHitTestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("TextHitTester can only hit test TextData")
    }
}

impl std::error::Error for TextHitTestError {}

fn hit_test_rotated_rect(
    rect: DrawRect,
    rotation: f64,
    position: DrawPoint,
    tolerance: f64,
) -> bool {
    let local_position = if rotation == 0.0 {
        position
    } else {
        ElementSpace::new(rotation, rect.center()).from_world(position)
    };

    local_position.x >= rect.min_x - tolerance
        && local_position.x <= rect.max_x + tolerance
        && local_position.y >= rect.min_y - tolerance
        && local_position.y <= rect.max_y + tolerance
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hit_test_text_rejects_non_text_data() {
        let tester = TextHitTester;
        let marker = "not-text-data";
        let element = TextHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            data: &marker,
        };

        let result = tester.hit_test_text(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert!(result.is_err());
    }

    #[test]
    fn hit_test_text_accepts_text_data() {
        let tester = TextHitTester;
        let data = TextData::default();
        let element = TextHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            data: &data,
        };

        let result = tester.hit_test_text(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert_eq!(result, Ok(true));
    }

    #[test]
    fn hit_test_rotated_rect_handles_world_position() {
        let tester = TextHitTester;
        let data = TextData::default();
        let rect = DrawRect::new(0.0, 0.0, 20.0, 10.0);
        let rotation = std::f64::consts::FRAC_PI_2;
        let world_inside =
            ElementSpace::new(rotation, rect.center()).to_world(DrawPoint::new(5.0, 5.0));
        let element = TextHitTestElement {
            rect,
            rotation,
            data: &data,
        };

        let result = tester.hit_test_text(&element, world_inside, 0.0);
        assert_eq!(result, Ok(true));
    }
}
