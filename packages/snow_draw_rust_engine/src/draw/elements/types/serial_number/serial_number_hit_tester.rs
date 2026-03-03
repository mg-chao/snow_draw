use std::any::{type_name_of_val, Any};
use std::fmt;

use crate::draw::config::draw_config::ConfigDefaults;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::serial_number_data::SerialNumberData;

/// Hit tester for serial-number elements.
///
/// Mirrors Dart `SerialNumberHitTester` behavior for the typed path through
/// [`Self::hit_test_serial_number`], including the runtime `SerialNumberData`
/// guard.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SerialNumberHitTester;

impl SerialNumberHitTester {
    /// Hit-tests a serial-number element that carries payload data.
    ///
    /// Returns an error when `element.data` is not `SerialNumberData`,
    /// matching the Dart `StateError` behavior.
    pub fn hit_test_serial_number(
        &self,
        element: &SerialNumberHitTestElement<'_>,
        position: DrawPoint,
        tolerance: f64,
    ) -> Result<bool, SerialNumberHitTestError> {
        let Some(data) = element.data.downcast_ref::<SerialNumberData>() else {
            return Err(SerialNumberHitTestError::wrong_data_type(element.data));
        };

        let stroke_width = resolve_serial_number_stroke_width(data, 0.0);
        Ok(hit_test_serial_number_circle(
            element.rect,
            position,
            stroke_width,
            tolerance,
        ))
    }
}

impl ElementHitTester for SerialNumberHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        assert!(
            element.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN,
            "SerialNumberHitTester can only hit test SerialNumberData (got {})",
            element.type_id().as_str()
        );

        let data = SerialNumberData::from_json_value(&element.data.to_json_value())
            .expect("SerialNumberHitTester received invalid SerialNumberData payload");

        self.hit_test_serial_number(
            &SerialNumberHitTestElement {
                rect: element.rect,
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

/// Serial-number-only element snapshot used by
/// [`SerialNumberHitTester::hit_test_serial_number`].
#[derive(Debug)]
pub struct SerialNumberHitTestElement<'a> {
    pub rect: DrawRect,
    pub data: &'a dyn Any,
}

/// Runtime mismatch returned when non-serial-number payload data is used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SerialNumberHitTestError {
    actual_type: &'static str,
}

impl SerialNumberHitTestError {
    fn wrong_data_type(data: &dyn Any) -> Self {
        Self {
            actual_type: type_name_of_val(data),
        }
    }
}

impl fmt::Display for SerialNumberHitTestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SerialNumberHitTester can only hit test SerialNumberData (got {})",
            self.actual_type
        )
    }
}

impl std::error::Error for SerialNumberHitTestError {}

fn hit_test_serial_number_circle(
    rect: DrawRect,
    position: DrawPoint,
    stroke_width: f64,
    tolerance: f64,
) -> bool {
    let radius = rect.width().min(rect.height()) / 2.0;
    if radius <= 0.0 {
        return false;
    }

    let effective_radius = radius + (stroke_width / 2.0) + tolerance;
    if effective_radius <= 0.0 {
        return false;
    }

    let dx = position.x - rect.center_x();
    let dy = position.y - rect.center_y();
    dx * dx + dy * dy <= effective_radius * effective_radius
}

fn resolve_serial_number_stroke_width(data: &SerialNumberData, min_stroke_width: f64) -> f64 {
    let base_font_size = ConfigDefaults::DEFAULT_SERIAL_NUMBER_FONT_SIZE;
    if base_font_size <= 0.0 {
        return data.stroke_width.max(min_stroke_width);
    }

    let scaled = data.stroke_width * (data.font_size / base_font_size);
    if !scaled.is_finite() {
        return min_stroke_width;
    }

    scaled.max(min_stroke_width)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hit_test_serial_number_rejects_non_serial_number_data() {
        let tester = SerialNumberHitTester;
        let marker = "not-serial-number-data";
        let element = SerialNumberHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 20.0, 20.0),
            data: &marker,
        };

        let result = tester.hit_test_serial_number(&element, DrawPoint::new(10.0, 10.0), 0.0);
        assert!(result.is_err());
    }

    #[test]
    fn hit_test_serial_number_hits_within_effective_circle() {
        let tester = SerialNumberHitTester;
        let data = SerialNumberData::default();
        let element = SerialNumberHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 20.0, 20.0),
            data: &data,
        };

        assert_eq!(
            tester.hit_test_serial_number(&element, DrawPoint::new(20.9, 10.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_serial_number(&element, DrawPoint::new(21.1, 10.0), 0.0),
            Ok(false)
        );
    }

    #[test]
    fn hit_test_serial_number_scales_stroke_with_font_size() {
        let tester = SerialNumberHitTester;
        let data = SerialNumberData {
            stroke_width: 2.0,
            font_size: 32.0,
            ..SerialNumberData::default()
        };
        let element = SerialNumberHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 20.0, 20.0),
            data: &data,
        };

        // Radius 10 + scaled half stroke (2.0) -> 12.0 effective radius.
        assert_eq!(
            tester.hit_test_serial_number(&element, DrawPoint::new(22.0, 10.0), 0.0),
            Ok(true)
        );
        assert_eq!(
            tester.hit_test_serial_number(&element, DrawPoint::new(22.1, 10.0), 0.0),
            Ok(false)
        );
    }
}
