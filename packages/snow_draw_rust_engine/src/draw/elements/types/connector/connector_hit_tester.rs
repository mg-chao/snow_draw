#![allow(dead_code)]

use crate::draw::elements::core::element_hit_tester::{ElementHitTester, ElementState};
use crate::draw::elements::types::arrow::arrow_hit_tester::{
    ArrowHitTestElement, ArrowHitTester, ArrowLikeData as HitTestArrowLikeData,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Connector-only element snapshot used by [`ConnectorHitTester`].
#[derive(Clone, Copy, Debug)]
pub struct ConnectorHitTestElement<'a, D: HitTestArrowLikeData + ?Sized> {
    pub id: &'a str,
    pub rect: DrawRect,
    pub rotation: f64,
    pub data: &'a D,
}

/// Hit tester for connector-style elements.
///
/// The translated implementation still shares the heavy lifting with the
/// arrow hit tester, but the connector module now exposes its own wrapper type
/// and connector-focused entry point like the Dart engine.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ConnectorHitTester {
    delegate: ArrowHitTester,
}

impl ConnectorHitTester {
    pub const fn new() -> Self {
        Self {
            delegate: ArrowHitTester,
        }
    }

    pub fn hit_test_connector<D: HitTestArrowLikeData + ?Sized>(
        &self,
        element: &ConnectorHitTestElement<'_, D>,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        self.delegate.hit_test_arrow(
            &ArrowHitTestElement {
                id: element.id,
                rect: element.rect,
                rotation: element.rotation,
                data: element.data,
            },
            position,
            tolerance,
        )
    }
}

impl ElementHitTester for ConnectorHitTester {
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        self.delegate
            .hit_test_with_tolerance(element, position, tolerance)
    }

    fn get_bounds(&self, element: &ElementState) -> DrawRect {
        self.delegate.get_bounds(element)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::arrow_data::ArrowData;

    #[test]
    fn connector_hit_tester_exposes_distinct_type() {
        let tester = ConnectorHitTester::new();
        let element = ConnectorHitTestElement {
            id: "arrow",
            rect: DrawRect::new(0.0, 0.0, 100.0, 100.0),
            rotation: 0.0,
            data: &ArrowData::default(),
        };

        assert!(!tester.hit_test_connector(&element, DrawPoint::new(200.0, 200.0), 1.0,));
    }
}
