use std::any::Any;
use std::fmt;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

use super::filter_data::FilterData;

/// Hit tester for filter elements.
///
/// Mirrors Dart `FilterHitTester` behavior for the typed path through
/// [`Self::hit_test_filter`], including the runtime FilterData guard.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FilterHitTester;

impl FilterHitTester {
    /// Hit-tests a filter element that carries payload data and rotation.
    ///
    /// Returns an error when `element.data` is not `FilterData`, matching the
    /// Dart `StateError` behavior.
    pub fn hit_test_filter(
        &self,
        element: &FilterHitTestElement<'_>,
        position: DrawPoint,
        tolerance: f64,
    ) -> Result<bool, FilterHitTestError> {
        if element.data.downcast_ref::<FilterData>().is_none() {
            return Err(FilterHitTestError::wrong_data_type());
        }

        Ok(hit_test_rotated_rect(
            element.rect,
            element.rotation,
            position,
            tolerance,
        ))
    }
}

impl ElementHitTester for FilterHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        assert!(
            element.type_id().as_str() == FilterData::TYPE_ID_TOKEN,
            "FilterHitTester can only hit test FilterData (got {})",
            element.type_id().as_str()
        );

        let data = FilterData::from_json_value(&element.data.to_json_value())
            .expect("FilterHitTester received invalid FilterData payload");

        self.hit_test_filter(
            &FilterHitTestElement {
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

/// Filter-only element snapshot used by [`FilterHitTester::hit_test_filter`].
#[derive(Debug)]
pub struct FilterHitTestElement<'a> {
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a dyn Any,
}

/// Runtime mismatch returned when non-filter payload data is used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FilterHitTestError;

impl FilterHitTestError {
    fn wrong_data_type() -> Self {
        Self
    }
}

impl fmt::Display for FilterHitTestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("FilterHitTester can only hit test FilterData")
    }
}

impl std::error::Error for FilterHitTestError {}

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
    fn hit_test_filter_rejects_non_filter_data() {
        let tester = FilterHitTester;
        let marker = "not-filter-data";
        let element = FilterHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            data: &marker,
        };

        let result = tester.hit_test_filter(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert!(result.is_err());
    }

    #[test]
    fn hit_test_filter_accepts_filter_data() {
        let tester = FilterHitTester;
        let data = FilterData::default();
        let element = FilterHitTestElement {
            rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            rotation: 0.0,
            data: &data,
        };

        let result = tester.hit_test_filter(&element, DrawPoint::new(5.0, 5.0), 0.0);
        assert_eq!(result, Ok(true));
    }

    #[test]
    fn hit_test_rotated_rect_handles_world_position() {
        let tester = FilterHitTester;
        let data = FilterData::default();
        let rect = DrawRect::new(0.0, 0.0, 20.0, 10.0);
        let rotation = std::f64::consts::FRAC_PI_2;
        let world_inside =
            ElementSpace::new(rotation, rect.center()).to_world(DrawPoint::new(5.0, 5.0));
        let element = FilterHitTestElement {
            rect,
            rotation,
            data: &data,
        };

        let result = tester.hit_test_filter(&element, world_inside, 0.0);
        assert_eq!(result, Ok(true));
    }
}
